// sid64 - reSID / reSID-fp wrapper for GameMaker
// Forked from C64 Dev Machine (tools/sid64) for NOTtheC64GameEngine.
// reSID / reSID-fp are GPL v2 (see COPYING); so is this wrapper.
//
// All exports: cdecl, double args, double return (GameMaker extension friendly).
// Buffer args: pass buffer_get_address(buf) (declare as string/pointer in the extension).
// GameMaker allows mixed argument types only up to 4 arguments.
//
// Version 4 (NOTtheC64GameEngine) adds:
//   sid64_dual_config / sid64_render_dual  two chips clocked from per-frame
//                                          register logs and mixed here (stereo or mono)
//   sid64_pcm_*                            one 8-bit signed PCM channel (~11025 Hz),
//                                          note-pitched, volume 0..15, mixed after the SIDs
//   sid64_settle                           no longer loops forever when clock returns 0
#include <string.h>
#include <math.h>
#include <vector>
#include "resid/sid.h"
#include "resid-fp/sidfp.h"

#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif

// Nine independent chips ("slots"). The engine uses slots 1 and 2 for the
// dual-SID stream; slot 0 is free for auditions.
// sid64_select picks the slot every single-chip call works on.
#define SID64_SLOTS 9
static SID   *g_sid_s[SID64_SLOTS];
static SIDFP *g_sidfp_s[SID64_SLOTS];
static unsigned char g_regs_s[SID64_SLOTS][32];
static double g_gain_s[SID64_SLOTS] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 };
static int g_slot = 0;
#define g_sid   g_sid_s[g_slot]
#define g_sidfp g_sidfp_s[g_slot]
#define g_regs  g_regs_s[g_slot]
#define g_gain  g_gain_s[g_slot]
static int g_clock = 985248;
static int g_rate = 44100;
static int g_cycles_per_frame = 19656;

// Write order within a frame. Per voice: CTRL first, then AD, SR, then pitch
// and pulse width (gate before AD/SR avoids the ADSR delay bug).
static const unsigned char k_order[25] = {
  0x18,0x17,0x16,0x15,
  0x12,0x13,0x14,0x0e,0x0f,0x10,0x11,
  0x0b,0x0c,0x0d,0x07,0x08,0x09,0x0a,
  0x04,0x05,0x06,0x00,0x01,0x02,0x03 };
#define WRITE_DELAY 9

static bool chip_present() { return g_sid != 0 || g_sidfp != 0; }

static void chip_write(int r, int v) {
  if (g_sid) g_sid->write(r, v);
  if (g_sidfp) g_sidfp->write(r, v);
  g_regs[r & 31] = (unsigned char)v;
}
static int chip_clock(int &cycles, short *out, int n) {
  cycle_count c = cycles;
  int got = 0;
  if (g_sid) got = g_sid->clock(c, out, n);
  if (g_sidfp) got = g_sidfp->clock(c, out, n);
  cycles = (int)c;
  if (g_gain != 1.0) {
    for (int i = 0; i < got; i++) {
      double v = out[i] * g_gain;
      if (v > 32767.0) v = 32767.0;
      if (v < -32768.0) v = -32768.0;
      out[i] = (short)v;
    }
  }
  return got;
}
// Clock 'cycles' into out (room for 'left' samples). Stops when the cycles are
// used up, the buffer is full, or the chip makes no progress (no chip, n == 0).
static int chip_clock_all(int cycles, short *out, int left) {
  int total = 0;
  while (cycles > 0) {
    int before = cycles;
    int got = chip_clock(cycles, out, left);
    out += got; left -= got; total += got;
    if (got == 0 && cycles == before) break;
    if (left <= 0) break;
  }
  return total;
}
// One 32-byte log record on the selected chip: register writes in k_order
// (WRITE_DELAY cycles apart), then the rest of the frame.
static int chip_render_frame(const unsigned char *rec, short *out, int left) {
  unsigned mask = rec[25] | (rec[26] << 8) | (rec[27] << 16) | ((unsigned)rec[28] << 24);
  int budget = g_cycles_per_frame, total = 0;
  for (int k = 0; k < 25; k++) {
    int r = k_order[k];
    if (mask != 0 && !(mask & (1u << r))) continue;
    chip_write(r, rec[r]);
    int got = chip_clock_all(WRITE_DELAY, out, left);
    out += got; left -= got; total += got; budget -= WRITE_DELAY;
  }
  if (budget > 0 && left > 0) total += chip_clock_all(budget, out, left);
  return total;
}
static void free_chip() {
  if (g_sid) { delete g_sid; g_sid = 0; }
  if (g_sidfp) { delete g_sidfp; g_sidfp = 0; }
}

// model: 0 = 6581, 1 = 8580. engine: 0 = reSID, 1 = reSID-fp (better 6581 filter/distortion)
EXPORT double sid64_init(double clock_hz, double sample_rate, double model, double engine) {
  free_chip();
  g_clock = (int)clock_hz;
  g_rate = (int)sample_rate;
  if ((int)engine == 1) {
    g_sidfp = new SIDFP;
    g_sidfp->set_chip_model(((int)model == 1) ? MOS8580 : MOS6581);
    g_sidfp->set_sampling_parameters(g_clock, SAMPLE_INTERPOLATE, g_rate);   // no resampler FIR latency
    g_sidfp->get_filter().set_distortion_properties(0.50f, 3.3e6f, 1.0e-4f);
    g_sidfp->get_filter().set_type3_properties(1147036.4394268463f, 274228796.97550374f, 1.0066634233403395f, 16125.154840564108f);
    g_sidfp->get_filter().set_type4_properties(5.5f, 20.f);
    g_sidfp->set_voice_nonlinearity(0.9613160610660189f);
    g_sidfp->reset();
  } else {
    g_sid = new SID;
    g_sid->set_chip_model(((int)model == 1) ? MOS8580 : MOS6581);
    g_sid->set_sampling_parameters(g_clock, SAMPLE_INTERPOLATE, g_rate);
    g_sid->reset();
  }
  memset(g_regs, 0, sizeof(g_regs));
  return 1;
}

EXPORT double sid64_reset() {
  if (g_sid) g_sid->reset();
  if (g_sidfp) g_sidfp->reset();
  memset(g_regs, 0, sizeof(g_regs));
  return 1;
}

EXPORT double sid64_free() { free_chip(); return 1; }

EXPORT double sid64_write(double reg, double val) {
  if (!chip_present()) return 0;
  chip_write(((int)reg) & 31, ((int)val) & 255);
  return 1;
}

// Render 'cycles' SID clocks into s16 mono at buf_ptr (max 'max_samples'). Returns samples written.
EXPORT double sid64_clock(const char *buf_ptr, double cycles, double max_samples) {
  if (!chip_present()) return 0;
  return chip_clock_all((int)cycles, (short*)buf_ptr, (int)max_samples);
}

// Frame length for every log render (19656 PAL / 17095 NTSC).
EXPORT double sid64_set_cycles_per_frame(double cycles) {
  if (cycles >= 1) g_cycles_per_frame = (int)cycles;
  return 1;
}

// Offline render of a register log on the selected chip.
// frames_ptr: 'frames' records of 32 bytes: [0..24] register values, [25..28] u32 write mask
//   (bit r = write reg r this frame; 0 = write all 25), [29..31] PCM command (see
//   sid64_render_dual; ignored here).
// out_ptr: s16 mono buffer with room for out_max samples. Returns samples written.
EXPORT double sid64_render_log(const char *frames_ptr, double frames, const char *out_ptr,
                               double out_max) {
  if (!chip_present()) return 0;
  const unsigned char *f = (const unsigned char*)frames_ptr;
  short *out = (short*)out_ptr;
  int nf = (int)frames, left = (int)out_max, total = 0;
  for (int i = 0; i < nf && left > 0; i++) {
    int got = chip_render_frame(f + i * 32, out, left);
    out += got; left -= got; total += got;
  }
  return total;
}

// Write volume/filter reg $18 and run the chip silently for 'ms' milliseconds, discarding output.
// Lets the 6581 volume-write DC step and the external filter settle before a render starts.
EXPORT double sid64_settle(double vol_reg, double ms) {
  if (!chip_present()) return 0;
  chip_write(0x18, ((int)vol_reg) & 255);
  short scratch[1024];
  int c = (int)((double)g_clock * ms / 1000.0);
  while (c > 0) {
    int before = c;
    int got = chip_clock(c, scratch, 1024);
    // the old loop spun forever here when clock() returned 0 without using cycles
    if (got == 0 && c == before) break;
  }
  return 1;
}

EXPORT double sid64_read(double reg) {
  int r = ((int)reg) & 31;
  if (g_sid && r >= 0x19) return g_sid->read(r);
  if (g_sidfp && r >= 0x19) return g_sidfp->read(r);
  return g_regs[r];
}

// Output gain of the selected chip (1.0 = reSID's native level).
EXPORT double sid64_set_gain(double gain) { g_gain = gain; return 1; }

// Select the chip slot.
EXPORT double sid64_select(double slot) {
  int s = (int)slot;
  if (s < 0 || s >= SID64_SLOTS) return 0;
  g_slot = s;
  return 1;
}

// ---------------------------------------------------------------------------
// PCM channel: one voice of 8-bit signed samples, nearest-sample playback (the
// crunchy Amiga / C64-digi sound), note-pitched, volume 0..15.
// Up to PCM_SLOTS samples are held here (copied in by sid64_pcm_load).
// Note PCM_ROOT_NOTE (48 = C-4, C0 = 0) plays a sample at its own rate.
// ---------------------------------------------------------------------------
#define PCM_SLOTS 16
#define PCM_ROOT_NOTE 48
struct PcmSample {
  std::vector<signed char> data;
  double rate;
  int loop_start, loop_end;     // loop_end <= loop_start: one-shot
};
static PcmSample g_pcm[PCM_SLOTS];
static int g_pcm_cur = -1;        // sample playing, -1 = silent
static double g_pcm_pos = 0;      // position in source samples
static double g_pcm_step = 0;     // source samples per output sample
static int g_pcm_vol = 15;
static double g_pcm_gain = 64.0;  // s8 * gain at volume 15 (127 * 64 ~ one loud SID voice)

static void pcm_init_slots() {
  static bool done = false;
  if (done) return;
  for (int i = 0; i < PCM_SLOTS; i++) {
    g_pcm[i].rate = 11025.0;
    g_pcm[i].loop_start = 0;
    g_pcm[i].loop_end = 0;
  }
  done = true;
}
static void pcm_trigger(int slot, int note, int vol) {
  pcm_init_slots();
  if (slot < 0 || slot >= PCM_SLOTS || g_pcm[slot].data.empty()) { g_pcm_cur = -1; return; }
  g_pcm_cur = slot;
  g_pcm_pos = 0;
  g_pcm_step = g_pcm[slot].rate * pow(2.0, (note - PCM_ROOT_NOTE) / 12.0) / (double)g_rate;
  if (vol >= 0) g_pcm_vol = vol & 15;
}
// Next PCM output value (already scaled), advancing the channel.
static int pcm_next() {
  if (g_pcm_cur < 0) return 0;
  PcmSample &s = g_pcm[g_pcm_cur];
  int len = (int)s.data.size();
  int i = (int)g_pcm_pos;
  if (i >= len || (s.loop_end > s.loop_start && i >= s.loop_end)) {
    if (s.loop_end > s.loop_start) {
      g_pcm_pos -= (double)(s.loop_end - s.loop_start);
      i = (int)g_pcm_pos;
      if (i < 0 || i >= len) { g_pcm_cur = -1; return 0; }
    } else {
      g_pcm_cur = -1;
      return 0;
    }
  }
  g_pcm_pos += g_pcm_step;
  return (int)(s.data[i] * g_pcm_gain * g_pcm_vol / 15.0);
}
// Frame command in a log record's spare bytes (chip 1's log only):
//   [29] 0 = nothing, 1..96 = trigger note [29]-1, 0xff = stop
//   [30] bit 7 set = set volume to bits 0..3 (applied before a trigger)
//   [31] sample slot for the trigger
static void pcm_frame_command(const unsigned char *rec) {
  if (rec[30] & 0x80) g_pcm_vol = rec[30] & 15;
  if (rec[29] == 0xff) g_pcm_cur = -1;
  else if (rec[29] >= 1 && rec[29] <= 96) pcm_trigger(rec[31], rec[29] - 1, -1);
}

// Copy 'len' signed 8-bit samples into PCM slot 'slot'. Resets its loop.
EXPORT double sid64_pcm_load(double slot, const char *data_ptr, double len) {
  pcm_init_slots();
  int s = (int)slot, n = (int)len;
  if (s < 0 || s >= PCM_SLOTS || n < 0) return 0;
  if (g_pcm_cur == s) g_pcm_cur = -1;
  g_pcm[s].data.assign((const signed char*)data_ptr, (const signed char*)data_ptr + n);
  g_pcm[s].loop_start = 0;
  g_pcm[s].loop_end = 0;
  return n;
}
// Native rate of a PCM slot in Hz (default 11025).
EXPORT double sid64_pcm_rate(double slot, double hz) {
  pcm_init_slots();
  int s = (int)slot;
  if (s < 0 || s >= PCM_SLOTS || hz <= 0) return 0;
  g_pcm[s].rate = hz;
  return 1;
}
// Loop a PCM slot between sample offsets [start, end). end <= start = one-shot.
EXPORT double sid64_pcm_loop(double slot, double start, double end) {
  pcm_init_slots();
  int s = (int)slot;
  if (s < 0 || s >= PCM_SLOTS) return 0;
  g_pcm[s].loop_start = (int)start;
  g_pcm[s].loop_end = (int)end;
  return 1;
}
// Start a PCM slot now (takes effect from the next render). vol 0..15, -1 = keep.
EXPORT double sid64_pcm_trigger(double slot, double note, double vol) {
  pcm_trigger((int)slot, (int)note, (int)vol);
  return 1;
}
EXPORT double sid64_pcm_stop() { g_pcm_cur = -1; return 1; }
// PCM level: output = s8 * gain * vol / 15 (default 64).
EXPORT double sid64_pcm_gain(double gain) { g_pcm_gain = gain; return 1; }

// ---------------------------------------------------------------------------
// Dual render: two chips + PCM, mixed here.
//   stereo: L = chip A + PCM, R = chip B + PCM (interleaved s16 L/R)
//   mono:   (A + B) / 2 + PCM (s16)
// ---------------------------------------------------------------------------
static int g_dual_a = 1, g_dual_b = 2, g_dual_stereo = 1, g_dual_cap = 0;
static std::vector<short> g_dual_sa, g_dual_sb;

// Which slots are chip A (left) and chip B (right), stereo 1 / mono 0, and how
// many sample frames the output buffer of sid64_render_dual holds.
EXPORT double sid64_dual_config(double slot_a, double slot_b, double stereo, double out_frames) {
  int a = (int)slot_a, b = (int)slot_b;
  if (a < 0 || a >= SID64_SLOTS || b < 0 || b >= SID64_SLOTS || a == b) return 0;
  g_dual_a = a;
  g_dual_b = b;
  g_dual_stereo = ((int)stereo != 0) ? 1 : 0;
  g_dual_cap = (int)out_frames;
  return 1;
}

static inline short clamp16(int v) {
  if (v > 32767) return 32767;
  if (v < -32768) return -32768;
  return (short)v;
}

// Render 'frames' log records of chip A (log_a, its spare bytes carry the PCM
// commands) and chip B (log_b) into out_ptr. Returns sample frames written
// (stereo: each frame is 2 shorts). Stops early when the output is full.
EXPORT double sid64_render_dual(const char *log_a, const char *log_b, double frames, const char *out_ptr) {
  int keep = g_slot;
  short *out = (short*)out_ptr;
  const unsigned char *fa = (const unsigned char*)log_a;
  const unsigned char *fb = (const unsigned char*)log_b;
  int nf = (int)frames, total = 0, left = g_dual_cap;
  int per = (int)((double)g_cycles_per_frame * g_rate / g_clock) + 64;
  if ((int)g_dual_sa.size() < per) { g_dual_sa.resize(per); g_dual_sb.resize(per); }
  for (int i = 0; i < nf && left > 0; i++) {
    const unsigned char *ra = fa + i * 32, *rb = fb + i * 32;
    int na = 0, nb = 0;
    g_slot = g_dual_a;
    if (chip_present()) na = chip_render_frame(ra, &g_dual_sa[0], per);
    g_slot = g_dual_b;
    if (chip_present()) nb = chip_render_frame(rb, &g_dual_sb[0], per);
    // chips clocked alike give the same count; if one is missing or drifted,
    // chip A's count rules (B padded with its last sample / silence)
    int n = na;
    if (n == 0) n = nb;
    if (n > left) n = left;
    pcm_frame_command(ra);
    for (int k = 0; k < n; k++) {
      int sa = 0, sb = 0;
      if (k < na) sa = g_dual_sa[k];
      if (k < nb) sb = g_dual_sb[k];
      else if (nb > 0) sb = g_dual_sb[nb - 1];
      int p = pcm_next();
      if (g_dual_stereo) {
        out[0] = clamp16(sa + p);
        out[1] = clamp16(sb + p);
        out += 2;
      } else {
        out[0] = clamp16((sa + sb) / 2 + p);
        out += 1;
      }
    }
    total += n;
    left -= n;
  }
  g_slot = keep;
  return total;
}

EXPORT double sid64_version() { return 4.0; }
