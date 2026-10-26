using SkiaSharp;

namespace InkBlade;

public sealed class Particle
{
    public string Type = "ink";
    public float X, Y, Vx, Vy, Life, Max, Size, Gravity = 1100f, Drag, Floor, Alpha = 1f, Rot, Vr;
    public SKColor Color;
    public bool Splat;
}

public sealed class Ghost
{
    public float X, Y, W, H, Life, Max;
    public int Facing;
    public SKColor Color;
}

public sealed class SlashFx
{
    public float X, Y, A0, A1, R, W0, W1, Life, Max;
    public SKColor Color;
}

public sealed class RingFx
{
    public float X, Y, R0, R1, Life, Max, Width;
    public SKColor Color;
}

public sealed class FloatText
{
    public float X, Y, Vy = -70f, Life, Max, Size;
    public string Str = "";
    public SKColor Color;
    public bool Hand;
}

public static class Fx
{
    public static readonly List<Particle> Parts = new();
    public static readonly List<Ghost> Ghosts = new();
    public static readonly List<SlashFx> Slashes = new();
    public static readonly List<RingFx> Rings = new();
    public static readonly List<FloatText> Texts = new();
    public static float Shake, ShakeRot, Flash, Damage, T;
    public static SKColor FlashColor = C.Cream;

    public static void Reset()
    {
        Parts.Clear(); Ghosts.Clear(); Slashes.Clear(); Rings.Clear(); Texts.Clear();
        Shake = ShakeRot = Flash = Damage = 0;
    }

    public static void Update(float dt)
    {
        T += dt;

        for (int i = Parts.Count - 1; i >= 0; i--)
        {
            var p = Parts[i];
            p.Life -= dt;
            if (p.Life <= 0)
            {
                if (p.Splat) Splat(p);
                Parts.RemoveAt(i);
                continue;
            }
            p.Vy += p.Gravity * dt;
            p.Vx *= 1f - p.Drag * dt;
            p.Vy *= 1f - p.Drag * dt * 0.4f;
            p.X += p.Vx * dt;
            p.Y += p.Vy * dt;
            p.Rot += p.Vr * dt;
            if (p.Floor != 0 && p.Y > p.Floor)
            {
                p.Y = p.Floor;
                p.Vy *= -0.22f;
                p.Vx *= 0.55f;
                p.Life = MathF.Min(p.Life, 0.25f);
                if (p.Type == "drop") p.Type = "ink";
            }
        }

        for (int i = Ghosts.Count - 1; i >= 0; i--)
            if ((Ghosts[i].Life -= dt) <= 0) Ghosts.RemoveAt(i);
        for (int i = Slashes.Count - 1; i >= 0; i--)
            if ((Slashes[i].Life -= dt) <= 0) Slashes.RemoveAt(i);
        for (int i = Rings.Count - 1; i >= 0; i--)
            if ((Rings[i].Life -= dt) <= 0) Rings.RemoveAt(i);
        for (int i = Texts.Count - 1; i >= 0; i--)
        {
            var t = Texts[i];
            t.Life -= dt;
            t.Y += t.Vy * dt;
            t.Vy *= 0.94f;
            if (t.Life <= 0) Texts.RemoveAt(i);
        }

        Shake = MathF.Max(0, Shake - dt * 58f);
        ShakeRot *= MathF.Pow(0.001f, dt);
        Flash = MathF.Max(0, Flash - dt * 3.4f);
        Damage = MathF.Max(0, Damage - dt * 1.7f);
    }

    static void Splat(Particle p)
    {
        if (Parts.Count > 420) return;
        Parts.Add(new Particle
        {
            Type = "splat", X = p.X, Y = p.Y,
            Life = U.Rnd(0.5f, 1.6f), Max = 1.6f,
            Size = p.Size * U.Rnd(1.6f, 3.2f),
            Color = p.Color, Alpha = 0.35f, Gravity = 0
        });
    }

    public static void AddShake(float a, float rot = 0)
    {
        Shake = MathF.Min(26, MathF.Max(Shake, a));
        if (rot > 0) ShakeRot = MathF.Max(ShakeRot, rot);
    }

    public static void FlashScreen(float a, SKColor? color = null)
    {
        Flash = MathF.Max(Flash, a);
        if (color is { } c) FlashColor = c;
    }

    public static void DamageScreen(float a) => Damage = MathF.Max(Damage, a);

    public static (float x, float y, float rot) ShakeOffset()
    {
        if (Shake <= 0.2f) return (0, 0, 0);
        return (U.Rnd(-Shake, Shake), U.Rnd(-Shake, Shake) * 0.7f, U.Rnd(-ShakeRot, ShakeRot));
    }

    public static void InkBurst(float x, float y, int n = 10, float power = 220f,
        SKColor[]? colors = null, float size = 5f, bool drops = false, float? angle = null,
        float vx = 0, float vy = 0, float gravity = 1300f, float floor = 618f,
        bool splat = true)
    {
        colors ??= new[] { C.Ink, C.Ink, C.Red, C.InkSoft };
        for (int i = 0; i < n; i++)
        {
            if (Parts.Count > 460) break;
            float a = angle is { } aa ? aa + U.Rnd(-0.9f, 0.9f) : U.Rnd(0, U.TAU);
            float sp = U.Rnd(0.25f, 1f) * power;
            Parts.Add(new Particle
            {
                Type = drops ? "drop" : "ink",
                X = x + U.Rnd(-4, 4), Y = y + U.Rnd(-4, 4),
                Vx = MathF.Cos(a) * sp + vx,
                Vy = MathF.Sin(a) * sp - U.Rnd(0, 60) + vy,
                Life = U.Rnd(0.35f, 0.9f), Max = 0.9f,
                Size = U.Rnd(1.8f, size),
                Color = U.Pick(colors),
                Gravity = gravity, Drag = 0.8f, Floor = floor,
                Splat = splat, Alpha = 1f
            });
        }
    }

    public static void Sparks(float x, float y, float angle, int n = 7, SKColor? color = null)
    {
        for (int i = 0; i < n; i++)
        {
            float a = angle + U.Rnd(-1.1f, 1.1f);
            float sp = U.Rnd(220, 640);
            Parts.Add(new Particle
            {
                Type = "spark", X = x, Y = y,
                Vx = MathF.Cos(a) * sp, Vy = MathF.Sin(a) * sp,
                Life = U.Rnd(0.10f, 0.26f), Max = 0.26f,
                Size = U.Rnd(1, 2.4f),
                Color = color ?? U.Pick(new[] { C.Cream, C.Gold, C.RedBright }),
                Gravity = 380, Drag = 2.5f, Alpha = 1f
            });
        }
    }

    public static void Dust(float x, float y, int n, float dirX)
    {
        for (int i = 0; i < n; i++)
        {
            Parts.Add(new Particle
            {
                Type = "dust", X = x + U.Rnd(-8, 8), Y = y + U.Rnd(-3, 3),
                Vx = dirX * U.Rnd(10, 50) + U.Rnd(-35, 35),
                Vy = U.Rnd(-90, -20),
                Life = U.Rnd(0.4f, 0.85f), Max = 0.85f,
                Size = U.Rnd(3, 8), Color = C.InkSoft,
                Gravity = -30, Drag = 1.6f, Alpha = 0.22f
            });
        }
    }

    public static void Ring(float x, float y, float r0, float r1, SKColor? color = null,
        float life = 0.3f, float width = 2f)
    {
        Rings.Add(new RingFx
        {
            X = x, Y = y, R0 = r0, R1 = r1,
            Color = color ?? C.Ink, Life = life, Max = life, Width = width
        });
    }

    public static void GhostTrail(float x, float y, float w, float h, int facing, float life = 0.22f)
    {
        if (Ghosts.Count > 30) return;
        Ghosts.Add(new Ghost { X = x, Y = y, W = w, H = h, Facing = facing, Life = life, Max = life, Color = C.Red });
    }

    public static void Slash(float x, float y, float a0, float a1, float r, float w0, float w1,
        float life, SKColor color)
    {
        Slashes.Add(new SlashFx
        {
            X = x, Y = y, A0 = a0, A1 = a1, R = r, W0 = w0, W1 = w1,
            Life = life, Max = life, Color = color
        });
    }

    public static void Text(float x, float y, string str, float size = 20f, SKColor? color = null,
        bool hand = true, float life = 0.7f, float vy = -70f)
    {
        if (Texts.Count > 30) return;
        Texts.Add(new FloatText
        {
            X = x, Y = y, Str = str, Size = size, Color = color ?? C.Ink,
            Hand = hand, Life = life, Max = life, Vy = vy
        });
    }

    /* ---------- рисование ---------- */

    public static void DrawBehind()
    {
        foreach (var g in Ghosts)
        {
            float k = g.Life / g.Max;
            Ink.Save();
            Ink.Translate(g.X + g.W / 2, g.Y + g.H);
            Ink.Scale(g.Facing, 1);
            Ink.Alpha = 0.28f * k;
            Ink.Srand((long)(g.X * 7 + g.Y * 3));
            var cloak = new[]
            {
                new SKPoint(-12, -31), new SKPoint(10, -32), new SKPoint(13, -12),
                new SKPoint(10, -2), new SKPoint(3, -6), new SKPoint(-5, -3), new SKPoint(-13, -10)
            };
            Ink.FillPoly(cloak, C.Cream, 1f, 1.1f);
            Ink.Blob(1, -38, 10, C.Cream, outline: false);
            Ink.Restore();
        }

        foreach (var p in Parts)
        {
            if (p.Type != "dust") continue;
            Ink.Save();
            float k = p.Life / p.Max;
            Ink.Alpha = k * p.Alpha;
            Ink.FillCircleColor(p.X, p.Y, p.Size * (1 + (1 - k) * 0.8f), p.Color);
            Ink.Restore();
        }

        foreach (var r in Rings)
        {
            float k = 1 - r.Life / r.Max;
            Ink.Save();
            Ink.Alpha = (1 - k) * 0.55f;
            Ink.Arc(r.X, r.Y, U.Lerp(r.R0, r.R1, U.EaseOutCubic(k)), 0, U.TAU,
                MathF.Max(0.5f, r.Width * (1 - k)), r.Color, 1f, 0.8f,
                steps: 24);
            Ink.Restore();
        }
    }

    public static void DrawFront()
    {
        foreach (var s in Parts)
        {
            if (s.Type == "dust") continue;
            float k = U.Clamp01(s.Life / s.Max);
            Ink.Save();
            Ink.Alpha = MathF.Min(1, k * 1.8f);
            if (s.Type == "spark")
            {
                float len = 10 + (1 - k) * 26;
                Ink.Line(s.X, s.Y, s.X - s.Vx * 0.02f * (len / 18), s.Y - s.Vy * 0.02f * (len / 18),
                    s.Size, s.Color, 1f, 0f);
            }
            else if (s.Type == "splat")
            {
                Ink.Srand((long)(s.X * 3 + s.Y));
                Ink.Blob(s.X, s.Y, s.Size, s.Color, outline: false, jitter: 0.8f);
            }
            else
            {
                Ink.Srand((long)(s.X * 5 + s.Y * 2));
                Ink.Blob(s.X, s.Y, s.Size, s.Color, C.Ink, 1f, 0.95f, 1f,
                    outline: s.Size > 4);
            }
            Ink.Restore();
        }

        foreach (var s in Slashes)
        {
            float k = 1 - s.Life / s.Max;
            float grow = U.EaseOutCubic(k);
            float a0 = s.A0;
            float a1 = U.Lerp(s.A0, s.A1, MathF.Min(1, grow * 1.35f));
            float alpha = (1 - k) * 0.9f;
            Ink.Srand((long)(s.X * 3 + s.Y * 7));
            Ink.TaperArc(s.X, s.Y, s.R - 4 + grow * 8, a0, a1,
                s.W0 * (1 - k * 0.5f), s.W1, C.Ink, alpha * 0.55f, 1.4f);
            Ink.TaperArc(s.X, s.Y, s.R + grow * 4, a0, a1,
                s.W0 * 0.62f, s.W1 * 0.35f, s.Color, alpha, 1f);
            Ink.TaperArc(s.X, s.Y, s.R + grow * 2, a0 + 0.05f, a1 - 0.05f,
                s.W0 * 0.2f, s.W1 * 0.18f, C.Cream, alpha * 0.85f, 0.6f);
        }

        foreach (var t in Texts)
        {
            float k = U.Clamp01(t.Life / t.Max);
            float pop = MathF.Min(1, (1 - k) * 4);
            float scale = 0.7f + U.EaseOutBack(pop) * 0.35f;
            Ink.Text(t.Str, t.X, t.Y, new TextOpt
            {
                Size = t.Size * scale,
                Font = t.Hand ? FontKind.Hand : FontKind.Bold,
                Align = InkAlign.Center,
                Color = t.Color,
                Alpha = MathF.Min(1, k * 2),
                Ghost = 1
            });
        }
    }

    public static void DrawScreen(float w, float h)
    {
        if (Damage > 0)
        {
            using var shader = SKShader.CreateRadialGradient(new SKPoint(w / 2, h / 2), h * 0.78f,
                new[] { new SKColor(140, 20, 30, 0), new SKColor(140, 20, 30, (byte)(0.5f * Damage * 255)) },
                new[] { 0f, 1f }, SKShaderTileMode.Clamp);
            using var paint = new SKPaint { IsAntialias = true, Shader = shader };
            Ink.Cv?.DrawRect(new SKRect(0, 0, w, h), paint);
        }
        if (Flash > 0)
        {
            Ink.Save();
            Ink.Alpha = MathF.Min(0.8f, Flash);
            Ink.FillRectColor(0, 0, w, h, FlashColor);
            Ink.Restore();
        }
    }
}
