/// scr_audio - the audio core (engine; shipped in the Player and the Editor).
/// docs/ENGINE_DESIGN.md §7.
///
/// Two reSID chips (sid64 slots AUD_SLOT_A / AUD_SLOT_B, each 6581 or 8580)
/// plus one 8-bit PCM channel are clocked and mixed inside the sid64 DLL
/// (sid64_render_dual). GML only produces one 32-byte register record per chip
/// per 50 Hz frame (the render_log format) and streams the mixed s16 audio
/// through one play queue: AUD_CHUNK_FRAMES frames (80 ms) per buffer, about
/// AUD_AHEAD_MS queued ahead, refilled from the Async Audio Playback event
/// (ADAM's music_preview_* pattern).
///
/// Record layout (32 bytes per chip per frame):
///   [0..24]  SID registers $00..$18
///   [25..28] u32 write mask, bit r = write reg r this frame (0 = write all 25)
///   [29..31] PCM command, chip A's record only:
///            [29] 0 = nothing, 1..96 = trigger note [29]-1 (C0 = 0), 0xff = stop
///            [30] 0x80 | volume (0..15) sets the volume, 0 = keep
///            [31] PCM sample slot (0..15) to trigger
///
/// A stream source is a struct with a method frame(_log_a, _log_b, _off) that
/// writes one record per chip at byte _off and returns false once it is finished.
///
/// State lives in obj_engine (initialised in its Create): aud_*.

#macro AUD_RATE            44100
#macro AUD_PAL_CLOCK       985248
#macro AUD_CYCLES_FRAME    19656
#macro AUD_CHUNK_FRAMES    4       // 4 x 20 ms = 80 ms per queued buffer
#macro AUD_AHEAD_MS        240     // keep this much audio queued ahead of the speaker
#macro AUD_SLOT_A          1       // sid64 slot of chip A (left)
#macro AUD_SLOT_B          2       // sid64 slot of chip B (right)
#macro AUD_REC             32      // bytes per register record
#macro AUD_PCM_ROOT        48      // C-4: the PCM note that plays a sample at its own rate
#macro AUD_PCM_RATE        11025
#macro AUD_DEAD_MS         1500    // stopped-queue buffers are freed this long after the stop

/// @desc Check the sid64 extension and create the stream's log buffers.
/// Call from obj_engine Create after the aud_* variables are initialised.
function audio_init()
{
    aud_ok = false;
    try
    {
        if (sid64_version() >= 4)
        {
            aud_ok = true;
        }
        else
        {
            show_debug_message("audio: sid64 is older than version 4, no audio");
        }
    }
    catch (_e)
    {
        show_debug_message("audio: sid64 extension unavailable, no audio (" + string(_e.message) + ")");
        aud_ok = false;
    }
    // room for one chunk of sample frames (+ slack for rounding)
    aud_cap = ceil(AUD_CHUNK_FRAMES * AUD_CYCLES_FRAME * AUD_RATE / AUD_PAL_CLOCK) + 64;
    aud_log_a = buffer_create(AUD_CHUNK_FRAMES * AUD_REC, buffer_fixed, 1);
    aud_log_b = buffer_create(AUD_CHUNK_FRAMES * AUD_REC, buffer_fixed, 1);
    buffer_fill(aud_log_a, 0, buffer_u8, 0, AUD_CHUNK_FRAMES * AUD_REC);
    buffer_fill(aud_log_b, 0, buffer_u8, 0, AUD_CHUNK_FRAMES * AUD_REC);
    if (aud_ok)
    {
        audio_chips_init();
    }
}

/// @desc (Re)initialise both chips with aud_model_a / aud_model_b and settle them.
function audio_chips_init()
{
    if (!aud_ok)
    {
        return;
    }
    sid64_select(AUD_SLOT_A);
    sid64_init(AUD_PAL_CLOCK, AUD_RATE, aud_model_a, aud_engine);
    sid64_set_gain(aud_gain);
    sid64_set_cycles_per_frame(AUD_CYCLES_FRAME);
    sid64_settle(0x0f, 100);
    sid64_select(AUD_SLOT_B);
    sid64_init(AUD_PAL_CLOCK, AUD_RATE, aud_model_b, aud_engine);
    sid64_set_gain(aud_gain);
    sid64_set_cycles_per_frame(AUD_CYCLES_FRAME);
    sid64_settle(0x0f, 100);
    sid64_select(0);
    sid64_pcm_stop();
    var _stereo = 0;
    if (aud_stereo)
    {
        _stereo = 1;
    }
    sid64_dual_config(AUD_SLOT_A, AUD_SLOT_B, _stereo, aud_cap);
}

/// @desc Bytes per sample frame of the stream (4 stereo, 2 mono).
function audio_frame_bytes()
{
    if (aud_stereo)
    {
        return 4;
    }
    return 2;
}

/// @desc Write one register record at byte _off of _buf.
/// _regs: array of 25 register values. _mask: u32 write mask (0 = all).
/// _pcm: [note (0..95, or -1 none, -2 stop), volume (0..15, or -1 keep), slot]
function audio_rec_put(_buf, _off, _regs, _mask, _pcm)
{
    for (var _r = 0; _r < 25; _r++)
    {
        buffer_poke(_buf, _off + _r, buffer_u8, _regs[_r] & 0xff);
    }
    buffer_poke(_buf, _off + 25, buffer_u32, _mask);
    var _cmd = 0;
    var _vol = 0;
    var _slot = 0;
    if (is_array(_pcm))
    {
        if (_pcm[0] >= 0)
        {
            _cmd = clamp(_pcm[0], 0, 95) + 1;
        }
        else if (_pcm[0] == -2)
        {
            _cmd = 0xff;
        }
        if (_pcm[1] >= 0)
        {
            _vol = 0x80 | (_pcm[1] & 15);
        }
        _slot = _pcm[2] & 15;
    }
    buffer_poke(_buf, _off + 29, buffer_u8, _cmd);
    buffer_poke(_buf, _off + 30, buffer_u8, _vol);
    buffer_poke(_buf, _off + 31, buffer_u8, _slot);
}

/// @desc SID frequency register value for note _n (C0 = 0, A-4 = 57 = 440 Hz), PAL clock.
function audio_note_freq(_n)
{
    var _hz = 440 * power(2, (_n - 57) / 12);
    return clamp(round(_hz * 16777216 / AUD_PAL_CLOCK), 0, 0xffff);
}

/// @desc Load signed 8-bit samples from buffer _buf (_len bytes) into PCM slot _slot.
function audio_pcm_load(_slot, _buf, _len, _rate)
{
    if (!aud_ok)
    {
        return;
    }
    sid64_pcm_load(_slot, buffer_get_address(_buf), _len);
    sid64_pcm_rate(_slot, _rate);
}

/// @desc Start streaming source _src (see the header). Returns false without sid64.
function audio_stream_start(_src)
{
    if (!aud_ok || !is_struct(_src))
    {
        return false;
    }
    audio_stream_stop();
    audio_chips_init();
    var _ch = audio_mono;
    if (aud_stereo)
    {
        _ch = audio_stereo;
    }
    aud_queue = audio_create_play_queue(buffer_s16, AUD_RATE, _ch);
    aud_src = _src;
    aud_src_done = false;
    aud_frames_queued = 0;
    aud_playing = true;
    aud_t0 = get_timer();
    audio_stream_fill();
    aud_inst = audio_play_sound(aud_queue, 10, false);
    aud_t0 = get_timer();
    return true;
}

/// @desc Render and queue chunks until about AUD_AHEAD_MS of audio is waiting.
function audio_stream_fill()
{
    if (!aud_playing || aud_src_done)
    {
        return;
    }
    var _elapsed = (get_timer() - aud_t0) / 1000000 * AUD_RATE;
    var _ahead = AUD_RATE * AUD_AHEAD_MS / 1000;
    var _bpf = audio_frame_bytes();
    var _guard = 0;
    while (aud_frames_queued < _elapsed + _ahead && _guard < 8 && !aud_src_done)
    {
        var _n = 0;
        for (var _i = 0; _i < AUD_CHUNK_FRAMES; _i++)
        {
            if (aud_src.frame(aud_log_a, aud_log_b, _i * AUD_REC))
            {
                _n += 1;
            }
            else
            {
                aud_src_done = true;
                break;
            }
        }
        if (_n == 0)
        {
            break;
        }
        var _b = buffer_create(aud_cap * _bpf, buffer_fixed, 1);
        var _got = sid64_render_dual(buffer_get_address(aud_log_a), buffer_get_address(aud_log_b), _n, buffer_get_address(_b));
        if (_got > 0)
        {
            // the DLL wrote through the pointer, so tell GameMaker how much is filled
            buffer_set_used_size(_b, _got * _bpf);
            audio_queue_sound(aud_queue, _b, 0, _got * _bpf);
            array_push(aud_bufs, _b);
            aud_frames_queued += _got;
        }
        else
        {
            buffer_delete(_b);
        }
        _guard += 1;
    }
}

/// @desc Stop the stream. Its buffers are freed AUD_DEAD_MS later (the queue may still hold them).
function audio_stream_stop()
{
    if (aud_inst != -1)
    {
        audio_stop_sound(aud_inst);
        aud_inst = -1;
    }
    if (aud_queue != -1)
    {
        audio_free_play_queue(aud_queue);
        aud_queue = -1;
    }
    for (var _i = 0; _i < array_length(aud_bufs); _i++)
    {
        array_push(aud_dead, [aud_bufs[_i], current_time]);
    }
    aud_bufs = [];
    aud_playing = false;
    aud_src = -1;
    aud_src_done = false;
}

/// @desc Step: frees old buffers, keeps the queue fed, stops when the source has played out.
function audio_stream_step()
{
    for (var _i = array_length(aud_dead) - 1; _i >= 0; _i--)
    {
        if (current_time - aud_dead[_i][1] > AUD_DEAD_MS)
        {
            if (buffer_exists(aud_dead[_i][0]))
            {
                buffer_delete(aud_dead[_i][0]);
            }
            array_delete(aud_dead, _i, 1);
        }
    }
    if (!aud_playing)
    {
        return;
    }
    var _elapsed = (get_timer() - aud_t0) / 1000000 * AUD_RATE;
    if (_elapsed > aud_frames_queued)
    {
        if (aud_src_done)
        {
            audio_stream_stop();
            return;
        }
        // the queue ran dry (window dragged, game paused): carry on from here
        aud_t0 = get_timer() - aud_frames_queued / AUD_RATE * 1000000;
    }
    audio_stream_fill();
    if (aud_inst == -1 || !audio_is_playing(aud_inst))
    {
        aud_inst = audio_play_sound(aud_queue, 10, false);
    }
}

/// @desc Async Audio Playback event: free a played buffer, then top the queue up.
function audio_stream_async()
{
    var _b = async_load[? "buffer_id"];
    if (is_undefined(_b))
    {
        return;
    }
    for (var _i = 0; _i < array_length(aud_bufs); _i++)
    {
        if (aud_bufs[_i] == _b)
        {
            array_delete(aud_bufs, _i, 1);
            if (buffer_exists(_b))
            {
                buffer_delete(_b);
            }
            aud_played += 1;
            break;
        }
    }
    audio_stream_fill();
}

/// @desc Milliseconds of audio queued ahead of the speaker (debug display).
function audio_stream_ahead_ms()
{
    if (!aud_playing)
    {
        return 0;
    }
    var _elapsed = (get_timer() - aud_t0) / 1000000 * AUD_RATE;
    return max(0, round((aud_frames_queued - _elapsed) * 1000 / AUD_RATE));
}

/// @desc Free everything (CleanUp).
function audio_free()
{
    audio_stream_stop();
    for (var _i = 0; _i < array_length(aud_dead); _i++)
    {
        if (buffer_exists(aud_dead[_i][0]))
        {
            buffer_delete(aud_dead[_i][0]);
        }
    }
    aud_dead = [];
    if (buffer_exists(aud_log_a))
    {
        buffer_delete(aud_log_a);
    }
    if (buffer_exists(aud_log_b))
    {
        buffer_delete(aud_log_b);
    }
    if (buffer_exists(aud_test_pcm))
    {
        buffer_delete(aud_test_pcm);
    }
    aud_log_a = -1;
    aud_log_b = -1;
    aud_test_pcm = -1;
    if (aud_ok)
    {
        sid64_select(AUD_SLOT_A);
        sid64_free();
        sid64_select(AUD_SLOT_B);
        sid64_free();
        sid64_select(0);
    }
}

// ---------------------------------------------------------------------------
// Test (F9, and the -Shot self-test): 5 s of hand-written register frames.
//   0.0 - 1.0 s  chip A (6581, left):  pulse arpeggio C-5 E-5 G-5 C-6 E-6
//   1.0 - 2.0 s  chip B (8580, right): sawtooth bass C-3 / G-2
//   2.0 - 3.5 s  both together
//   3.5 - 5.0 s  PCM blips on both sides: C-4, E-4, G-4, C-5 at volume 15, C-5 at volume 4
// ---------------------------------------------------------------------------
#macro AUD_TEST_FRAMES 250

/// @desc A ~0.15 s 8-bit "bloop" (pitch falls onto C-4) in aud_test_pcm, loaded into PCM slot 0.
function audio_test_pcm_make()
{
    var _n = 1650;
    if (!buffer_exists(aud_test_pcm))
    {
        aud_test_pcm = buffer_create(_n, buffer_fixed, 1);
    }
    var _ph = 0;
    for (var _i = 0; _i < _n; _i++)
    {
        var _hz = 261.63 * (1 + exp(-_i / 160));
        _ph += 2 * pi * _hz / AUD_PCM_RATE;
        var _v = sin(_ph) * exp(-_i / 550);
        buffer_poke(aud_test_pcm, _i, buffer_s8, clamp(round(_v * 127), -128, 127));
    }
    audio_pcm_load(0, aud_test_pcm, _n, AUD_PCM_RATE);
}

/// @desc The test as a stream source struct.
function audio_test_source()
{
    var _src = {
        t : 0,
        regs_a : array_create(25, 0),
        regs_b : array_create(25, 0),
        frame : function(_log_a, _log_b, _off)
        {
            if (t >= AUD_TEST_FRAMES)
            {
                return false;
            }
            audio_test_frame(t, regs_a, regs_b);
            audio_rec_put(_log_a, _off, regs_a, 0, audio_test_pcm_cmd(t));
            audio_rec_put(_log_b, _off, regs_b, 0, undefined);
            t += 1;
            return true;
        }
    };
    return _src;
}

/// @desc Set both chips' registers for test frame _t.
function audio_test_frame(_t, _ra, _rb)
{
    // chip A, voice 1: pulse arpeggio, a note every 10 frames, gate held 7
    var _arp = [60, 64, 67, 72, 76];
    var _a_on = (_t < 50) || (_t >= 100 && _t < 175);
    var _fa = audio_note_freq(_arp[(_t div 10) mod 5]);
    _ra[0x00] = _fa & 0xff;
    _ra[0x01] = (_fa >> 8) & 0xff;
    _ra[0x02] = 0x00;
    _ra[0x03] = 0x08;               // pulse width 50 %
    _ra[0x05] = 0x09;               // attack 0, decay 9
    _ra[0x06] = 0x40;               // sustain 4, release 0
    _ra[0x04] = 0x40;               // pulse, gate off
    if (_a_on && (_t mod 10) < 7)
    {
        _ra[0x04] = 0x41;
    }
    _ra[0x18] = 0x0f;

    // chip B, voice 1: sawtooth bass, a note every 12 frames, gate held 9
    var _bass = [36, 31];
    var _b_on = (_t >= 50 && _t < 175);
    var _fb = audio_note_freq(_bass[(_t div 12) mod 2]);
    _rb[0x00] = _fb & 0xff;
    _rb[0x01] = (_fb >> 8) & 0xff;
    _rb[0x05] = 0x08;               // attack 0, decay 8
    _rb[0x06] = 0xa4;               // sustain 10, release 4
    _rb[0x04] = 0x20;               // sawtooth, gate off
    if (_b_on && (_t mod 12) < 9)
    {
        _rb[0x04] = 0x21;
    }
    _rb[0x18] = 0x0f;
}

/// @desc PCM command for test frame _t ([note, volume, slot] or undefined).
function audio_test_pcm_cmd(_t)
{
    if (_t == 175)
    {
        return [48, 15, 0];
    }
    if (_t == 187)
    {
        return [52, 15, 0];
    }
    if (_t == 199)
    {
        return [55, 15, 0];
    }
    if (_t == 211)
    {
        return [60, 15, 0];
    }
    if (_t == 223)
    {
        return [60, 4, 0];
    }
    return undefined;
}

/// @desc F9: start the test, or stop it if it is playing.
function audio_test_toggle()
{
    if (aud_playing)
    {
        audio_stream_stop();
        return;
    }
    audio_test_pcm_make();
    audio_stream_start(audio_test_source());
}

/// @desc Self-test (-Shot): report the live stream, then render the test offline,
/// check left / right / PCM levels and save it as _wav_path.
function audio_selftest(_wav_path)
{
    if (!aud_ok)
    {
        show_debug_message("AUTOSHOT audio FAIL - sid64 extension unavailable");
        return;
    }
    show_debug_message("AUTOSHOT audio stream: " + string(aud_frames_queued) + " sample frames queued, "
        + string(aud_played) + " buffers played");
    audio_stream_stop();
    audio_chips_init();
    audio_test_pcm_make();
    var _src = audio_test_source();
    var _bpf = audio_frame_bytes();
    var _total = ceil(AUD_TEST_FRAMES * AUD_CYCLES_FRAME * AUD_RATE / AUD_PAL_CLOCK) + 64;
    var _all = buffer_create(_total * _bpf, buffer_fixed, 1);
    var _chunk = buffer_create(aud_cap * _bpf, buffer_fixed, 1);
    var _starts = array_create(AUD_TEST_FRAMES + 1, 0);
    var _pos = 0;
    // one frame per render so each frame's first sample is known
    for (var _f = 0; _f < AUD_TEST_FRAMES; _f++)
    {
        _starts[_f] = _pos;
        _src.frame(aud_log_a, aud_log_b, 0);
        var _got = sid64_render_dual(buffer_get_address(aud_log_a), buffer_get_address(aud_log_b), 1, buffer_get_address(_chunk));
        buffer_set_used_size(_chunk, _got * _bpf);
        if (_pos + _got > _total)
        {
            _got = _total - _pos;
        }
        buffer_copy(_chunk, 0, _got * _bpf, _all, _pos * _bpf);
        _pos += _got;
    }
    _starts[AUD_TEST_FRAMES] = _pos;
    buffer_set_used_size(_all, _pos * _bpf);
    buffer_delete(_chunk);

    // peaks [left, right] over frame ranges
    var _s1 = audio_selftest_peaks(_all, _starts, 0, 50);       // chip A alone
    var _s2 = audio_selftest_peaks(_all, _starts, 60, 100);     // chip B alone (after A's release)
    var _s3 = audio_selftest_peaks(_all, _starts, 100, 175);    // both
    // PCM only, centred: L and R match within 15 % (B's release tail and the chips' DC differ a little)
    var _s4 = audio_selftest_peaks(_all, _starts, 190, 210);
    var _ok = _pos > 0 && _s1[0] > 2000 && _s1[1] < 300 && _s2[1] > 2000 && _s2[0] < 300
        && _s3[0] > 2000 && _s3[1] > 2000 && _s4[0] > 2000 && abs(_s4[0] - _s4[1]) < max(_s4[0], _s4[1]) * 0.15;
    var _res = "FAIL";
    if (_ok)
    {
        _res = "ok";
    }
    show_debug_message("AUTOSHOT audio " + _res + " - " + string(_pos) + " sample frames; peaks L/R: A-only "
        + string(_s1[0]) + "/" + string(_s1[1]) + ", B-only " + string(_s2[0]) + "/" + string(_s2[1])
        + ", both " + string(_s3[0]) + "/" + string(_s3[1]) + ", PCM " + string(_s4[0]) + "/" + string(_s4[1]));
    audio_wav_save(_all, _pos, _wav_path);
    show_debug_message("AUTOSHOT audio saved " + _wav_path);
    buffer_delete(_all);
}

/// @desc [peak left, peak right] of _buf over test frames [_f0, _f1).
function audio_selftest_peaks(_buf, _starts, _f0, _f1)
{
    var _pl = 0;
    var _pr = 0;
    var _bpf = audio_frame_bytes();
    for (var _i = _starts[_f0]; _i < _starts[_f1]; _i++)
    {
        var _l = abs(buffer_peek(_buf, _i * _bpf, buffer_s16));
        var _r = _l;
        if (aud_stereo)
        {
            _r = abs(buffer_peek(_buf, _i * _bpf + 2, buffer_s16));
        }
        _pl = max(_pl, _l);
        _pr = max(_pr, _r);
    }
    return [_pl, _pr];
}

/// @desc Save _frames sample frames of s16 audio from _buf as a .wav file.
function audio_wav_save(_buf, _frames, _path)
{
    var _ch = 1;
    if (aud_stereo)
    {
        _ch = 2;
    }
    var _data = _frames * _ch * 2;
    var _w = buffer_create(44 + _data, buffer_fixed, 1);
    buffer_seek(_w, buffer_seek_start, 0);
    buffer_write(_w, buffer_u8, ord("R"));
    buffer_write(_w, buffer_u8, ord("I"));
    buffer_write(_w, buffer_u8, ord("F"));
    buffer_write(_w, buffer_u8, ord("F"));
    buffer_write(_w, buffer_u32, 36 + _data);
    buffer_write(_w, buffer_u8, ord("W"));
    buffer_write(_w, buffer_u8, ord("A"));
    buffer_write(_w, buffer_u8, ord("V"));
    buffer_write(_w, buffer_u8, ord("E"));
    buffer_write(_w, buffer_u8, ord("f"));
    buffer_write(_w, buffer_u8, ord("m"));
    buffer_write(_w, buffer_u8, ord("t"));
    buffer_write(_w, buffer_u8, ord(" "));
    buffer_write(_w, buffer_u32, 16);
    buffer_write(_w, buffer_u16, 1);                    // PCM
    buffer_write(_w, buffer_u16, _ch);
    buffer_write(_w, buffer_u32, AUD_RATE);
    buffer_write(_w, buffer_u32, AUD_RATE * _ch * 2);
    buffer_write(_w, buffer_u16, _ch * 2);
    buffer_write(_w, buffer_u16, 16);
    buffer_write(_w, buffer_u8, ord("d"));
    buffer_write(_w, buffer_u8, ord("a"));
    buffer_write(_w, buffer_u8, ord("t"));
    buffer_write(_w, buffer_u8, ord("a"));
    buffer_write(_w, buffer_u32, _data);
    buffer_copy(_buf, 0, _data, _w, 44);
    buffer_set_used_size(_w, 44 + _data);
    buffer_save(_w, _path);
    buffer_delete(_w);
}
