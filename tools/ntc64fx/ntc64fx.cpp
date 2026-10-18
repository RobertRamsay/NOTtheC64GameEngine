// ntc64fx - native picture effects for NOTtheC64GameEngine (GameMaker extension).
//
// Error-diffusion dithering to the 16 Pepto colours. Error diffusion is
// sequential (each pixel's error feeds the pixels after it), so it cannot run in
// the palette-lock shader; at 320 x 200 it costs well under a millisecond here.
//
// Our own code (not GPL). Build: see build.txt.
//
// GameMaker passes buffers as pointers (argument type "string") and numbers as
// doubles; every export returns a double.

#include <cstring>
#include <cmath>
#include <vector>

#ifdef _WIN32
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif

#define FX_VERSION 1

static float g_pal[16][3];
static unsigned char g_pal8[16][3];
static int g_pal_n = 0;
static std::vector<float> g_work;

// Same metric as pepto_nearest() and sh_pepto_lock: RGB weighted 2:4:3
static inline float dist(const float *c, const float *p) {
  float dr = c[0] - p[0], dg = c[1] - p[1], db = c[2] - p[2];
  return 2.0f * dr * dr + 4.0f * dg * dg + 3.0f * db * db;
}

static inline int nearest(const float *c) {
  int best = 0;
  float bd = 1e30f;
  for (int i = 0; i < g_pal_n; i++) {
    float d = dist(c, g_pal[i]);
    if (d < bd) { bd = d; best = i; }
  }
  return best;
}

EXPORT double fx_version() { return FX_VERSION; }

// rgb_ptr: n * 3 bytes (r, g, b 0..255). Returns the number of colours taken.
EXPORT double fx_set_palette(const char *rgb_ptr, double n) {
  const unsigned char *p = (const unsigned char *)rgb_ptr;
  g_pal_n = (int)n;
  if (g_pal_n < 1) g_pal_n = 1;
  if (g_pal_n > 16) g_pal_n = 16;
  for (int i = 0; i < g_pal_n; i++) {
    for (int k = 0; k < 3; k++) {
      g_pal8[i][k] = p[i * 3 + k];
      g_pal[i][k] = (float)p[i * 3 + k];
    }
  }
  return g_pal_n;
}

// Kernels: { dx, dy, weight } rows, divided by the kernel's total.
struct Tap { int dx, dy; float w; };

static const Tap K_FLOYD[] = { {1,0,7}, {-1,1,3}, {0,1,5}, {1,1,1} };                // /16
static const Tap K_ATKINSON[] = { {1,0,1}, {2,0,1}, {-1,1,1}, {0,1,1}, {1,1,1}, {0,2,1} }; // /8 (only 6/8 spread)
static const Tap K_SIERRA_LITE[] = { {1,0,2}, {-1,1,1}, {0,1,1} };                   // /4
static const Tap K_JJN[] = {                                                           // /48
  {1,0,7}, {2,0,5},
  {-2,1,3}, {-1,1,5}, {0,1,7}, {1,1,5}, {2,1,3},
  {-2,2,1}, {-1,2,3}, {0,2,5}, {1,2,3}, {2,2,1} };

static int g_kernel = 0;
static double g_amount = 1.0;
static double g_serpentine = 1.0;

// GameMaker allows at most 4 mixed-type arguments, so the options are set here:
//   kernel     0 Floyd-Steinberg, 1 Atkinson, 2 Sierra Lite, 3 Jarvis-Judice-Ninke
//   amount     0..1, how much of the error is passed on (0 = plain nearest colour)
//   serpentine 1 = every other row runs right to left (fewer diagonal "worms")
EXPORT double fx_dither_config(double kernel, double amount, double serpentine) {
  g_kernel = (int)kernel;
  g_amount = amount;
  g_serpentine = serpentine;
  return 1;
}

// In place: rgba_ptr is w * h * 4 bytes (r, g, b, a). Every pixel comes out as
// an exact palette colour with alpha 255. Returns the number of pixels written.
EXPORT double fx_dither_ed(const char *rgba_ptr, double w_d, double h_d) {
  const double kernel = g_kernel;
  const double amount = g_amount;
  const double serpentine = g_serpentine;
  if (g_pal_n <= 0) return 0;
  unsigned char *px = (unsigned char *)rgba_ptr;
  const int w = (int)w_d, h = (int)h_d;
  if (w <= 0 || h <= 0) return 0;

  const Tap *taps = K_FLOYD;
  int ntaps = 4;
  float div = 16.0f;
  switch ((int)kernel) {
    case 1: taps = K_ATKINSON; ntaps = 6; div = 8.0f; break;
    case 2: taps = K_SIERRA_LITE; ntaps = 3; div = 4.0f; break;
    case 3: taps = K_JJN; ntaps = 12; div = 48.0f; break;
    default: break;
  }
  float amt = (float)amount;
  if (amt < 0.0f) amt = 0.0f;
  if (amt > 1.0f) amt = 1.0f;

  g_work.assign((size_t)w * h * 3, 0.0f);
  float *wk = g_work.data();
  for (int i = 0; i < w * h; i++) {
    wk[i * 3 + 0] = px[i * 4 + 0];
    wk[i * 3 + 1] = px[i * 4 + 1];
    wk[i * 3 + 2] = px[i * 4 + 2];
  }

  for (int y = 0; y < h; y++) {
    const bool rtl = (serpentine != 0.0) && (y & 1);
    for (int xi = 0; xi < w; xi++) {
      const int x = rtl ? (w - 1 - xi) : xi;
      float *c = wk + ((size_t)y * w + x) * 3;
      float cc[3] = { c[0], c[1], c[2] };
      for (int k = 0; k < 3; k++) {
        if (cc[k] < 0.0f) cc[k] = 0.0f;
        if (cc[k] > 255.0f) cc[k] = 255.0f;
      }
      const int pi = nearest(cc);
      unsigned char *o = px + ((size_t)y * w + x) * 4;
      o[0] = g_pal8[pi][0];
      o[1] = g_pal8[pi][1];
      o[2] = g_pal8[pi][2];
      o[3] = 255;
      if (amt <= 0.0f) continue;
      const float er = (cc[0] - g_pal[pi][0]) * amt / div;
      const float eg = (cc[1] - g_pal[pi][1]) * amt / div;
      const float eb = (cc[2] - g_pal[pi][2]) * amt / div;
      for (int t = 0; t < ntaps; t++) {
        const int nx = x + (rtl ? -taps[t].dx : taps[t].dx);
        const int ny = y + taps[t].dy;
        if (nx < 0 || nx >= w || ny >= h) continue;
        float *n = wk + ((size_t)ny * w + nx) * 3;
        n[0] += er * taps[t].w;
        n[1] += eg * taps[t].w;
        n[2] += eb * taps[t].w;
      }
    }
  }
  return (double)w * h;
}
