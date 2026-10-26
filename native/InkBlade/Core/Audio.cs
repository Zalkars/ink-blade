using NAudio.Wave;

namespace InkBlade;

public sealed class ToneOptions
{
    public string Type = "sine";
    public float Freq = 220f;
    public float? Freq2;
    public float Dur = 0.2f;
    public float Gain = 0.16f;
    public float Delay;
    public float Attack = 0.005f;
    public float Filter;
    public float Q = 0.7f;
}

public sealed class NoiseOptions
{
    public float Freq = 1200f;
    public float? Freq2;
    public float Dur = 0.2f;
    public float Gain = 0.12f;
    public float Delay;
    public float Attack = 0.004f;
    public string Type = "bandpass";
    public float Q = 1f;
    public float Rate = 1f;
}

public static class Audio
{
    static Mixer? _mixer;
    static WaveOutEvent? _output;
    static bool _started;
    static bool _initTried;
    public static bool Muted;
    public static int SampleRate = 44100;

    public static void Init()
    {
        if (_initTried) return;
        _initTried = true;
        try
        {
            _mixer = new Mixer(SampleRate);
            _output = new WaveOutEvent { DesiredLatency = 70, NumberOfBuffers = 3 };
            _output.Init(_mixer);
            _output.Play();
        }
        catch
        {
            _mixer = null;
            _output = null;
        }
    }

    public static void Unlock()
    {
        Init();
        if (_mixer is null || _started) return;
        _started = true;
        _mixer.AmbientOn = true;
    }

    public static void SetMuted(bool muted)
    {
        Muted = muted;
        if (_mixer is not null) _mixer.TargetMaster = muted ? 0f : 0.72f;
    }

    public static void Shutdown()
    {
        try
        {
            _output?.Stop();
            _output?.Dispose();
        }
        catch { }
        _output = null;
        _mixer = null;
    }

    public static void ToggleMuted() => SetMuted(!Muted);

    public static void Tone(ToneOptions o)
    {
        if (_mixer is null || Muted) return;
        _mixer.Add(new ToneVoice(o, SampleRate));
    }

    public static void Noise(NoiseOptions o)
    {
        if (_mixer is null || Muted) return;
        _mixer.Add(new NoiseVoice(o, SampleRate));
    }

    /* ---------- эффекты ---------- */

    public static void Jump()
    {
        Tone(new ToneOptions { Type = "triangle", Freq = 300, Freq2 = 540, Dur = 0.14f, Gain = 0.10f });
        Noise(new NoiseOptions { Freq = 1600, Dur = 0.09f, Gain = 0.035f, Type = "highpass" });
    }

    public static void Land(float force)
    {
        float f = Math.Clamp(force, 0f, 1f);
        Tone(new ToneOptions { Type = "sine", Freq = 110, Freq2 = 55, Dur = 0.11f, Gain = 0.12f * f });
        Noise(new NoiseOptions { Freq = 700, Dur = 0.08f, Gain = 0.05f * f, Type = "lowpass" });
    }

    public static void Dash()
    {
        Noise(new NoiseOptions { Freq = 900, Freq2 = 2800, Dur = 0.18f, Gain = 0.10f, Q = 0.8f });
        Tone(new ToneOptions { Type = "sawtooth", Freq = 160, Freq2 = 90, Dur = 0.14f, Gain = 0.04f, Filter = 900 });
    }

    public static void Slash(int step)
    {
        int p = Math.Clamp(step, 1, 3);
        Noise(new NoiseOptions { Freq = 2400 - p * 260, Freq2 = 700, Dur = 0.1f + p * 0.015f, Gain = 0.08f, Q = 1.2f });
        Tone(new ToneOptions { Type = "triangle", Freq = 700 - p * 90, Freq2 = 220, Dur = 0.09f, Gain = 0.05f });
    }

    public static void Hit(bool heavy)
    {
        float h = heavy ? 1.25f : 1f;
        Tone(new ToneOptions { Type = "square", Freq = 150 / h, Freq2 = 60, Dur = 0.08f, Gain = 0.10f, Filter = 700 });
        Tone(new ToneOptions { Type = "sine", Freq = 90, Freq2 = 44, Dur = 0.12f, Gain = 0.14f * h });
        Noise(new NoiseOptions { Freq = 1500, Freq2 = 500, Dur = 0.07f, Gain = 0.08f });
        Tone(new ToneOptions { Type = "sine", Freq = 1250, Freq2 = 900, Dur = 0.05f, Gain = 0.03f });
    }

    public static void Kill()
    {
        Tone(new ToneOptions { Type = "sawtooth", Freq = 320, Freq2 = 60, Dur = 0.42f, Gain = 0.08f, Filter = 1100 });
        Noise(new NoiseOptions { Freq = 1800, Freq2 = 300, Dur = 0.35f, Gain = 0.09f });
        Tone(new ToneOptions { Type = "sine", Freq = 70, Freq2 = 38, Dur = 0.35f, Gain = 0.12f });
    }

    public static void Hurt()
    {
        Tone(new ToneOptions { Type = "sawtooth", Freq = 240, Freq2 = 70, Dur = 0.28f, Gain = 0.14f, Filter = 800 });
        Tone(new ToneOptions { Type = "square", Freq = 120, Freq2 = 50, Dur = 0.18f, Gain = 0.07f });
        Noise(new NoiseOptions { Freq = 900, Freq2 = 200, Dur = 0.22f, Gain = 0.10f });
    }

    public static void Heal()
    {
        float[] notes = { 523.25f, 659.25f, 783.99f };
        for (int i = 0; i < notes.Length; i++)
            Tone(new ToneOptions { Type = "sine", Freq = notes[i], Dur = 0.5f, Gain = 0.055f, Delay = i * 0.1f, Attack = 0.02f });
        Noise(new NoiseOptions { Freq = 3000, Dur = 0.4f, Gain = 0.02f, Type = "highpass" });
    }

    public static void HealLoop() =>
        Tone(new ToneOptions { Type = "sine", Freq = 392, Freq2 = 523, Dur = 0.3f, Gain = 0.02f });

    public static void Death()
    {
        Tone(new ToneOptions { Type = "sawtooth", Freq = 200, Freq2 = 30, Dur = 1.1f, Gain = 0.13f, Filter = 600 });
        Tone(new ToneOptions { Type = "sine", Freq = 90, Freq2 = 28, Dur = 1.3f, Gain = 0.12f });
        Noise(new NoiseOptions { Freq = 1200, Freq2 = 90, Dur = 1.0f, Gain = 0.08f, Type = "lowpass" });
    }

    public static void Deflect()
    {
        Tone(new ToneOptions { Type = "triangle", Freq = 1400, Freq2 = 2100, Dur = 0.09f, Gain = 0.07f });
        Noise(new NoiseOptions { Freq = 3200, Dur = 0.06f, Gain = 0.05f, Type = "highpass" });
    }

    public static void Spawn()
    {
        Noise(new NoiseOptions { Freq = 200, Freq2 = 1400, Dur = 0.3f, Gain = 0.05f, Q = 0.7f });
        Tone(new ToneOptions { Type = "sine", Freq = 120, Freq2 = 300, Dur = 0.3f, Gain = 0.04f });
    }

    public static void Ui() =>
        Tone(new ToneOptions { Type = "triangle", Freq = 900, Freq2 = 700, Dur = 0.045f, Gain = 0.04f });

    public static void UiConfirm() =>
        Tone(new ToneOptions { Type = "triangle", Freq = 520, Freq2 = 840, Dur = 0.12f, Gain = 0.06f });

    /* ---------- синтез ---------- */

    abstract class Voice
    {
        public long DelaySamples;
        public abstract bool Finished { get; }
        public abstract float Next(int sampleRate);
        protected static float Envelope(float t, float dur, float peak, float attack)
        {
            if (t < 0) return 0;
            if (t < attack) return peak * (t / MathF.Max(0.0001f, attack));
            float rest = MathF.Max(0.001f, dur - attack);
            float k = 9.21034f / rest;
            return peak * MathF.Exp(-k * (t - attack));
        }
    }

    sealed class ToneVoice : Voice
    {
        readonly string _type;
        readonly float _f0, _f1, _dur, _peak, _attack, _filter;
        readonly int _sr;
        float _t, _phase, _lp;
        float _frac;

        public ToneVoice(ToneOptions o, int sr)
        {
            _type = o.Type; _f0 = MathF.Max(20, o.Freq); _f1 = MathF.Max(20, o.Freq2 ?? o.Freq);
            _dur = o.Dur; _peak = o.Gain; _attack = o.Attack; _filter = o.Filter; _sr = sr;
            DelaySamples = (long)(o.Delay * sr);
        }

        public override bool Finished => _t >= _dur;

        public override float Next(int sampleRate)
        {
            if (DelaySamples > 0) { DelaySamples--; return 0; }
            float t = _t;
            if (t >= _dur) return 0;
            float u = t / _dur;
            float f = _f0 * MathF.Pow(_f1 / _f0, u);
            _phase += f / _sr;
            if (_phase >= 1f) _phase -= MathF.Floor(_phase);
            float s = _type switch
            {
                "triangle" => 1f - 4f * MathF.Abs(_phase - 0.5f),
                "sawtooth" => _phase * 2f - 1f,
                "square" => _phase < 0.5f ? 1f : -1f,
                _ => MathF.Sin(_phase * U.TAU)
            };
            if (_filter > 0)
            {
                float a = 1f - MathF.Exp(-U.TAU * _filter / _sr);
                _lp += (s - _lp) * a;
                s = _lp;
            }
            _t += 1f / _sr;
            _frac = Envelope(t, _dur, _peak, _attack);
            return s * _frac;
        }
    }

    sealed class NoiseVoice : Voice
    {
        readonly float _f0, _f1, _dur, _peak, _attack, _rate;
        readonly string _type;
        readonly int _sr;
        float _t, _lp, _lp2;
        uint _seed;

        public NoiseVoice(NoiseOptions o, int sr)
        {
            _f0 = o.Freq; _f1 = o.Freq2 ?? o.Freq; _dur = o.Dur; _peak = o.Gain;
            _attack = o.Attack; _rate = o.Rate; _type = o.Type; _sr = sr;
            DelaySamples = (long)(o.Delay * sr);
            _seed = (uint)Random.Shared.Next(1, int.MaxValue);
        }

        public override bool Finished => _t >= _dur;

        public override float Next(int sampleRate)
        {
            if (DelaySamples > 0) { DelaySamples--; return 0; }
            float t = _t;
            if (t >= _dur) return 0;
            float u = t / _dur;
            float f = _f0 * MathF.Pow(MathF.Max(40, _f1) / MathF.Max(40, _f0), u);
            _seed ^= _seed << 13; _seed ^= _seed >> 17; _seed ^= _seed << 5;
            float n = (_seed / 4294967296f) * 2f - 1f;
            float a = 1f - MathF.Exp(-U.TAU * Math.Clamp(f, 20, _sr * 0.45f) / _sr);
            _lp += (n - _lp) * a;
            _lp2 += (_lp - _lp2) * a;
            float s = _type switch
            {
                "lowpass" => _lp,
                "highpass" => n - _lp,
                _ => _lp - _lp2
            };
            _t += (1f / _sr) * MathF.Max(0.1f, _rate);
            return s * Envelope(t, _dur, _peak, _attack);
        }
    }

    sealed class Mixer : ISampleProvider
    {
        readonly object _lock = new();
        readonly List<Voice> _voices = new();
        readonly int _sr;
        float _ambientT;
        float _click;
        float _windLp;
        uint _seed = 1234567;

        public bool AmbientOn;
        public float TargetMaster = 0.72f;

        public Mixer(int sr) { _sr = sr; WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(sr, 2); }
        public WaveFormat WaveFormat { get; }

        public void Add(Voice v) { lock (_lock) _voices.Add(v); }

        public int Read(float[] buffer, int offset, int count)
        {
            int frames = count / 2;
            float dt = 1f / _sr;
            lock (_lock)
            {
                for (int i = 0; i < frames; i++)
                {
                    float mix = 0f;
                    for (int v = _voices.Count - 1; v >= 0; v--)
                    {
                        var voice = _voices[v];
                        mix += voice.Next(_sr);
                        if (voice.Finished) _voices.RemoveAt(v);
                    }

                    if (AmbientOn)
                    {
                        _ambientT += dt;
                        float drone = MathF.Sin(_ambientT * U.TAU * 55f) * 0.5f
                                    + MathF.Sin(_ambientT * U.TAU * 82.5f) * 0.24f
                                    + MathF.Sin(_ambientT * U.TAU * 110.2f) * 0.08f;
                        float lfo = 0.05f + MathF.Sin(_ambientT * U.TAU * 0.07f) * 0.02f;
                        mix += drone * lfo * 0.55f;

                        _seed ^= _seed << 13; _seed ^= _seed >> 17; _seed ^= _seed << 5;
                        float n = (_seed / 4294967296f) * 2f - 1f;
                        float a = 1f - MathF.Exp(-U.TAU * 420f / _sr);
                        _windLp += (n - _windLp) * a;
                        float wlfo = 0.018f + MathF.Sin(_ambientT * U.TAU * 0.045f) * 0.008f;
                        mix += _windLp * wlfo * 0.55f;
                    }

                    _click += (TargetMaster - _click) * 0.002f;
                    float outv = MathF.Tanh(mix * 1.1f) * _click;
                    buffer[offset + i * 2] = outv;
                    buffer[offset + i * 2 + 1] = outv;
                }
            }
            return count;
        }
    }
}
