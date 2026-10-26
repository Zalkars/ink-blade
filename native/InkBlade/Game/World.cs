using SkiaSharp;

namespace InkBlade;

public sealed class DecorDot
{
    public float X, Y, R, A, Sp, Ph;
}

public static class World
{
    public const float W = 1280f, H = 720f;
    public const float FloorY = 620f;
    public static readonly SKPoint Spawn = new(300, 574);

    public static readonly List<Rect> Solids = new()
    {
        new Rect(0, 0, 44, 720),
        new Rect(1236, 0, 44, 720),
        new Rect(0, 620, 722, 100),
        new Rect(840, 620, 440, 100),
        new Rect(130, 468, 272, 24),
        new Rect(900, 440, 300, 24),
        new Rect(44, 352, 118, 18)
    };

    public static readonly List<Rect> Oneways = new()
    {
        new Rect(560, 330, 175, 16),
        new Rect(690, 510, 132, 14)
    };

    public static readonly List<Rect> Hazards = new()
    {
        new Rect(714, 664, 132, 56)
    };

    public static readonly List<DecorDot> Decor = new();

    static SKBitmap? _stageBitmap;
    static SKImage? _stage;

    public static void Init()
    {
        Decor.Clear();
        int seed = 991;
        float Rnd()
        {
            seed = (int)((long)seed * 16807 % 2147483647);
            return (seed - 1) / 2147483646f;
        }
        for (int i = 0; i < 34; i++)
        {
            Decor.Add(new DecorDot
            {
                X = 60 + Rnd() * 1160,
                Y = 90 + Rnd() * 500,
                R = 1 + Rnd() * 3,
                A = 0.05f + Rnd() * 0.14f,
                Sp = 0.2f + Rnd() * 0.6f,
                Ph = Rnd() * 10
            });
        }
    }

    /* Неподвижную часть зала рисуем один раз в текстуру: это в разы дешевле,
       чем собирать сотни чернильных штрихов каждый кадр. */
    public static void Bake()
    {
        const int pad = 80;
        _stageBitmap = new SKBitmap(new SKImageInfo(1280 + pad * 2, 720 + pad * 2,
            SKColorType.Bgra8888, SKAlphaType.Opaque));
        using (var c = new SKCanvas(_stageBitmap))
        {
            c.Clear(C.Paper);
            Ink.DrawPaper(c, new SKRect(0, 0, _stageBitmap.Width, _stageBitmap.Height));
            Ink.SetCanvas(c);
            Ink.Save();
            Ink.Translate(pad, pad);
            DrawBackStatic();
            DrawDust(0);
            DrawCandle(78, 620, 0, 1);
            DrawCandle(1198, 620, 1.7f, 0.9f);
            DrawCandle(368, 468, 0.6f, 0.75f);
            DrawFrontStatic();
            DrawGrass(0);
            Ink.Restore();
            Ink.Save();
            Ink.Translate(pad, pad);
            Ink.Vignette();
            Ink.Vignette();
            Ink.Restore();
        }
        _stage = SKImage.FromBitmap(_stageBitmap);
    }

    public static void DrawStage()
    {
        if (_stage is null || Ink.Cv is null) return;
        using var paint = new SKPaint { IsAntialias = false };
        Ink.Cv.DrawImage(_stage, new SKRect(-80, -80, 1360, 800), paint);
    }

    static void DrawDust(float t)
    {
        foreach (var d in Decor)
        {
            float y = d.Y + MathF.Sin(t * d.Sp + d.Ph) * 18 - ((t * 6 * d.Sp) % 40);
            Ink.FillCircleColor(d.X + MathF.Sin(t * 0.2f + d.Ph) * 6, y, d.R, C.Ink, d.A);
        }
    }

    public static bool HasGroundAt(float px, float py)
    {
        foreach (var s in Solids)
            if (px >= s.X && px <= s.X + s.W && MathF.Abs(py - s.Y) < 12) return true;
        foreach (var s in Oneways)
            if (px >= s.X && px <= s.X + s.W && MathF.Abs(py - s.Y) < 12) return true;
        return false;
    }

    public static void MoveX(Body ent, float dt)
    {
        ent.X += ent.Vx * dt;
        ent.HitWall = false;
        foreach (var s in Solids)
        {
            if (!U.Overlap(ent, s)) continue;
            if (ent.Vx > 0) ent.X = s.X - ent.W;
            else if (ent.Vx < 0) ent.X = s.X + s.W;
            else ent.X = ent.X + ent.W * 0.5f < s.X + s.W * 0.5f ? s.X - ent.W : s.X + s.W;
            ent.Vx = 0;
            ent.HitWall = true;
        }
        if (ent.X < 44) { ent.X = 44; ent.Vx = MathF.Max(0, ent.Vx); ent.HitWall = true; }
        if (ent.X + ent.W > 1236) { ent.X = 1236 - ent.W; ent.Vx = MathF.Min(0, ent.Vx); ent.HitWall = true; }
    }

    public static void MoveY(Body ent, float dt)
    {
        float prevBottom = ent.Y + ent.H;
        ent.Y += ent.Vy * dt;
        ent.Grounded = false;
        ent.OnOneWay = false;

        foreach (var s in Solids)
        {
            if (!U.Overlap(ent, s)) continue;
            if (ent.Vy > 0)
            {
                ent.Y = s.Y - ent.H;
                ent.Vy = 0;
                ent.Grounded = true;
            }
            else if (ent.Vy < 0)
            {
                ent.Y = s.Y + s.H;
                ent.Vy = 0;
            }
        }

        if (ent.DropT <= 0)
        {
            foreach (var s in Oneways)
            {
                if (ent.Vy < 0) continue;
                if (prevBottom > s.Y + 2) continue;
                if (!U.Overlap(ent, s)) continue;
                ent.Y = s.Y - ent.H;
                ent.Vy = 0;
                ent.Grounded = true;
                ent.OnOneWay = true;
            }
        }
    }

    public static bool InHazard(Body ent)
    {
        foreach (var h in Hazards)
            if (U.Overlap(ent, h)) return true;
        return false;
    }

    /* ---------- фон ---------- */

    static void DrawBackStatic()
    {
        /* дальние каменные швы */
        Ink.Srand(31);
        for (float y = 120; y < 600; y += 118)
        {
            var pts = new List<SKPoint>();
            for (float x = 44; x <= 1236; x += 40)
                pts.Add(new SKPoint(x, y + MathF.Sin(x * 0.02f + y) * 1.5f));
            Ink.Poly(pts, 1.2f, C.Ink, 0.06f, 0f);
        }

        for (int i = 0; i < 5; i++)
        {
            float x = 170 + i * 235;
            Ink.Srand(100 + i);
            Ink.Poly(new[]
            {
                new SKPoint(x, 100), new SKPoint(x + 8, 190),
                new SKPoint(x - 4, 280), new SKPoint(x + 5, 390)
            }, 1.2f, C.Ink, 0.07f, 2.5f);
        }

        /* затмение */
        Ink.Srand(3);
        Ink.Circle(985, 196, 116, C.Ink, null, 2, 0.07f, 1.5f, 26, false);
        Ink.Circle(985, 196, 118, null, C.Rgba(156, 33, 41, 56), 2.5f, 0.8f, 1.6f, 30);
        Ink.Hatch(CirclePts(985, 196, 112, 20), 15f, 0.05f, C.Ink);

        DrawGate(0);
        DrawBanners(0);
        DrawChains(0);

        /* каллиграфия на стене */
        Ink.Save();
        Ink.Translate(104, 520);
        Ink.Rotate(-90);
        Ink.Text("ЧЕРНИЛЬНЫЙ КЛИНОК", 0, 0, new TextOpt
        {
            Size = 44, Font = FontKind.Display, Color = C.Ink, Alpha = 0.055f, Spacing = 12
        });
        Ink.Restore();

        DrawPillar(74, 108, 58, 512);
        DrawPillar(1148, 108, 58, 512);

        Ink.Text("ЧЕРНИЛА ПОМНЯТ", 640, 108, new TextOpt
        {
            Size = 20, Font = FontKind.Display, Align = InkAlign.Center,
            Color = C.Ink, Alpha = 0.16f, Spacing = 9
        });
        Ink.Line(470, 122, 810, 122, C.Ink, 0.16f, 1.5f, 1f);
    }

    static List<SKPoint> CirclePts(float cx, float cy, float r, int n)
    {
        var pts = new List<SKPoint>(n);
        for (int i = 0; i < n; i++)
        {
            float a = (float)i / n * U.TAU;
            pts.Add(new SKPoint(cx + MathF.Cos(a) * r, cy + MathF.Sin(a) * r));
        }
        return pts;
    }

    static void DrawPillar(float x, float y, float w, float h)
    {
        Ink.Srand((long)(x + y));
        Ink.Rect(x, y, w, h, C.Rgba(120, 100, 70, 13), C.Rgba(23, 19, 15, 41), 2);
        Ink.Rect(x - 8, y + h - 26, w + 16, 26, null, C.Rgba(23, 19, 15, 41), 2);
        Ink.Line(x + 10, y + 8, x + 10, y + h - 30, C.Rgba(23, 19, 15, 26), 1f, 1f, 0f);
        Ink.Line(x + w - 12, y + 8, x + w - 12, y + h - 30, C.Rgba(23, 19, 15, 26), 1f, 1f, 0f);
        Ink.Poly(new[]
        {
            new SKPoint(x + w * 0.2f, y + 40), new SKPoint(x + w * 0.5f, y + 120),
            new SKPoint(x + w * 0.35f, y + 230)
        }, 1f, C.Rgba(23, 19, 15, 31), 1f, 0f);
    }

    static void DrawGate(float t)
    {
        float cx = 640, w = 150, top = 128, bottom = 330;
        var pts = new List<SKPoint> { new(cx - w / 2, bottom) };
        for (int i = 0; i <= 14; i++)
        {
            float a = MathF.PI + (float)i / 14 * MathF.PI;
            pts.Add(new SKPoint(cx + MathF.Cos(a) * (w / 2), top + 75 + MathF.Sin(a) * 75));
        }
        pts.Add(new SKPoint(cx + w / 2, bottom));
        Ink.Srand(41);
        Ink.FillPoly(pts, C.Rgba(30, 24, 18, 77), 1f, 0.8f);
        Ink.Poly(pts, 3f, C.Rgba(23, 19, 15, 140), 1f, 1.15f, true);

        for (int i = -2; i <= 2; i++)
            Ink.Line(cx + i * 27, top + 78, cx + i * 27, bottom - 8, C.Rgba(240, 228, 204, 26), 2f, 1f, 0f);
        Ink.Arc(cx, top + 75, w / 2 - 6, MathF.PI, MathF.PI * 2, 2f, C.Rgba(240, 228, 204, 33), 1f, 0f);

        Chain(cx - 58, top + 78, bottom - 14, 2, 0.4f);
        Chain(cx + 62, top + 66, bottom - 30, -2, 0.35f);
        Ink.Line(cx - 62, 238, cx + 64, 258, C.Rgba(20, 16, 12, 128), 4f, 1f, 0f);
        Ink.Line(cx - 62, 238, cx + 64, 258, C.Rgba(240, 228, 204, 31), 1.5f, 1f, 0f);

        Ink.Srand(44);
        Ink.Rect(cx - 62, 352, 124, 42, C.Rgba(247, 239, 221, 230), C.Rgba(23, 19, 15, 153), 1.6f, 1f, 1f);
        Ink.Text("ДАЛЬШЕ —", cx - 2, 370, new TextOpt
        {
            Size = 12, Font = FontKind.Display, Align = InkAlign.Center,
            Color = C.Ink, Alpha = 0.7f, Spacing = 2
        });
        Ink.Text("В РАЗРАБОТКЕ", cx - 2, 386, new TextOpt
        {
            Size = 11, Font = FontKind.Hand, Align = InkAlign.Center,
            Color = C.Red, Alpha = 0.85f
        });
        Ink.Line(cx - 66, 344, cx - 50, 352, C.Rgba(23, 19, 15, 128), 1.5f, 1f, 0f);
        Ink.Line(cx + 50, 344, cx + 66, 352, C.Rgba(23, 19, 15, 128), 1.5f, 1f, 0f);
    }

    static void DrawBanners(float t)
    {
        float sway = MathF.Sin(t * 0.7f) * 3;
        Banner(232 + sway, 36, 62, 196, 0.16f);
        Banner(1042 - sway, 36, 56, 168, 0.14f);
        Ink.Text("I", 263 + sway, 120, new TextOpt
        {
            Size = 30, Font = FontKind.Display, Align = InkAlign.Center,
            Color = C.Rgba(240, 228, 204, 51)
        });
    }

    static void Banner(float x, float y, float w, float h, float alpha)
    {
        var pts = new[]
        {
            new SKPoint(x, y), new SKPoint(x + w, y), new SKPoint(x + w, y + h * 0.82f),
            new SKPoint(x + w * 0.82f, y + h), new SKPoint(x + w * 0.6f, y + h * 0.86f),
            new SKPoint(x + w * 0.42f, y + h), new SKPoint(x + w * 0.22f, y + h * 0.88f),
            new SKPoint(x, y + h * 0.84f)
        };
        Ink.Srand((long)x);
        Ink.FillPoly(pts, C.Rgba(156, 33, 41, (byte)(alpha * 255)), 1f, 1.2f);
        Ink.Poly(pts, 1.5f, C.Rgba(23, 19, 15, 89), 0.7f, 1.2f, true);
        Ink.Circle(x + w / 2, y + h * 0.38f, w * 0.2f, null, C.Rgba(240, 228, 204, 71), 1.5f, 1f, 0.8f);
        Ink.Line(x + w / 2, y + h * 0.2f, x + w / 2, y + h * 0.56f, C.Rgba(240, 228, 204, 51), 1f, 1f, 0f);
        Ink.Line(x + w / 2, y, x + w / 2, y - 14, C.Rgba(23, 19, 15, 102), 2f, 1f, 0f);
    }

    static void DrawChains(float t)
    {
        Chain(430, 0, 208, MathF.Sin(t * 0.55f) * 5, 0.22f);
        Chain(862, 0, 188, MathF.Sin(t * 0.48f + 2) * 4, 0.18f);
        Chain(1112, 0, 128, MathF.Sin(t * 0.62f + 1) * 3, 0.12f);
    }

    public static void Chain(float x, float y0, float y1, float sway, float alpha)
    {
        int n = (int)MathF.Floor((y1 - y0) / 11f);
        var pts = new List<SKPoint>();
        for (int i = 0; i <= n; i++)
        {
            float y = y0 + i * 11f;
            float xx = x + MathF.Sin(i * 0.35f + y0) * sway;
            pts.Add(new SKPoint(xx, y));
        }
        Ink.Poly(pts, 1.1f, C.Ink, alpha * 0.4f, 0.3f);
        for (int i = 0; i <= n; i++)
        {
            var p = pts[i];
            if (i % 2 == 0)
                Ink.Circle(p.X, p.Y, 2.8f, null, C.Ink, 1.1f, alpha, 0.3f, 7);
            else
                Ink.Line(p.X - 2.4f, p.Y - 4, p.X + 2.4f, p.Y + 4, C.Ink, 1.2f, alpha, 0.2f);
        }
    }

    static void DrawCandle(float x, float baseY, float t, float s)
    {
        float flick = MathF.Sin(t * 7.3f + x) * 2 + MathF.Sin(t * 13.1f + x * 0.4f) * 1.2f;
        Ink.RadialGlow(x, baseY - 24 * s, 52 * s, new SKColor(220, 150, 60), 0.18f,
            x - 60, baseY - 90, 120, 100);

        Ink.Srand((long)(x + 5));
        Ink.Rect(x - 5 * s, baseY - 26 * s, 10 * s, 26 * s,
            C.Rgba(246, 237, 218, 217), C.Ink, 1.4f, 1f, 0.6f);
        Ink.Line(x - 4 * s, baseY - 18 * s, x - 2 * s, baseY - 13 * s,
            C.Rgba(23, 19, 15, 77), 1.2f, 1f, 0.2f);
        Ink.Blob(x + flick * 0.3f, baseY - 34 * s, 4.4f * s, C.Gold,
            C.Rgba(23, 19, 15, 166), 1f, 1f, 0.8f, 10, 0.2f);
        Ink.Blob(x + flick * 0.4f, baseY - 33 * s, 2.1f * s, C.RedBright,
            outline: false, jitter: 0.5f, wobble: 0.25f);
        Ink.Line(x - 9 * s, baseY, x + 9 * s, baseY, C.Rgba(23, 19, 15, 128), 2f, 1f, 0f);
    }

    /* ---------- передний план ---------- */

    static void DrawFrontStatic()
    {
        Ink.FillRectGradient(44, 620, 1192, 100, 620, 720, new[]
        {
            (0f, C.Rgba(120, 98, 64, 26)),
            (1f, C.Rgba(60, 44, 28, 87))
        });

        Ink.Srand(71);
        Ink.Line(44, 620, 720, 620, C.Ink, 4.5f, 1f, 0.8f);
        Ink.Line(840, 620, 1236, 620, C.Ink, 4.5f, 1f, 0.8f);
        Ink.Line(50, 626, 716, 626, C.Ink, 1.4f, 0.25f, 0.5f);

        for (float x = 80; x < 700; x += 118)
            Ink.Line(x, 624, x - 6, 720, C.Rgba(23, 19, 15, 33), 1.3f, 1f, 0f);
        for (float x = 880; x < 1220; x += 118)
            Ink.Line(x, 624, x + 6, 720, C.Rgba(23, 19, 15, 33), 1.3f, 1f, 0f);
        Ink.Hatch(new[] { new SKPoint(46, 628), new SKPoint(718, 628), new SKPoint(718, 720), new SKPoint(46, 720) }, 17, 0.08f);
        Ink.Hatch(new[] { new SKPoint(842, 628), new SKPoint(1234, 628), new SKPoint(1234, 720), new SKPoint(842, 720) }, 17, 0.08f);

        Ink.FillRectGradient(720, 620, 120, 100, 620, 720, new[]
        {
            (0f, C.Rgba(30, 24, 18, 51)),
            (0.55f, C.Rgba(20, 16, 12, 184)),
            (1f, C.Rgba(12, 9, 7, 245))
        });

        Ink.Srand(83);
        Ink.Poly(new[]
        {
            new SKPoint(722, 620), new SKPoint(714, 650), new SKPoint(726, 672),
            new SKPoint(716, 700), new SKPoint(722, 720)
        }, 3f, C.Ink, 1f, 1.15f);
        Ink.Poly(new[]
        {
            new SKPoint(838, 620), new SKPoint(847, 648), new SKPoint(834, 674),
            new SKPoint(847, 702), new SKPoint(838, 720)
        }, 3f, C.Ink, 1f, 1.15f);

        for (int i = 0; i < 4; i++)
        {
            float sx = 736 + i * 27;
            float h = 26 + (i % 2) * 10;
            Ink.Srand(120 + i);
            Ink.FillPoly(new[]
            {
                new SKPoint(sx - 9, 700), new SKPoint(sx, 700 - h), new SKPoint(sx + 9, 700)
            }, C.Ink, 1f, 0.7f, true, C.Ink, 1.5f);
            Ink.Line(sx - 4, 696, sx, 700 - h + 4, C.Cream, 1.2f, 0.35f, 0.3f);
        }
        Ink.Line(720, 702, 840, 702, C.Rgba(23, 19, 15, 153), 2f, 1f, 0f);

        Platform(130, 468, 272, 24, false);
        Platform(900, 440, 300, 24, false);
        Platform(44, 352, 118, 18, false);
        Platform(560, 330, 175, 16, true);
        Platform(690, 510, 132, 14, true);

        Ink.Srand(301);
        Ink.Hatch(new[] { new SKPoint(0, 600), new SKPoint(110, 720), new SKPoint(0, 720) }, 12, 0.1f, C.Ink, 1f, true);
        Ink.Hatch(new[] { new SKPoint(1280, 620), new SKPoint(1280, 720), new SKPoint(1150, 720) }, 12, 0.09f, C.Ink, 1f, true);
    }

    static void DrawGrass(float t)
    {
        for (int i = 0; i < 9; i++)
        {
            float x = 100 + i * 128 + MathF.Sin(i * 3) * 30;
            if (x > 700 && x < 860) continue;
            float y = 620;
            Ink.Srand(200 + i);
            for (int j = 0; j < 3; j++)
                Ink.Poly(new[]
                {
                    new SKPoint(x + j * 4 - 4, y),
                    new SKPoint(x + j * 5 - 8 + MathF.Sin(t + i) * 2, y - 7 - j * 2)
                }, 1.4f, C.Rgba(23, 19, 15, 102), 1f, 0.6f);
        }
    }

    static void Platform(float x, float y, float w, float h, bool oneWay)
    {
        Ink.Srand((long)(x + y * 3));
        Ink.Rect(x, y, w, h,
            oneWay ? C.Rgba(238, 226, 201, 235) : C.Rgba(226, 211, 178, 230),
            C.Ink, 2.4f, 1f, 0.8f);
        Ink.Line(x + 3, y + 2, x + w - 3, y + 2, C.Rgba(250, 244, 228, 166), 1.6f, 1f, 0.8f);
        Ink.Hatch(new[]
        {
            new SKPoint(x + 2, y + h - 2), new SKPoint(x + w - 2, y + h - 2),
            new SKPoint(x + w - 2, y + h + 18), new SKPoint(x + 2, y + h + 18)
        }, 7, 0.16f);

        if (oneWay)
        {
            Ink.Line(x + 3, y + h + 4, x + w - 3, y + h + 4,
                C.Rgba(23, 19, 15, 64), 1f, 1f, 0f, new[] { 5f, 7f });
            Chain(x + 22, y - 44, y, 0, 0.25f);
            Chain(x + w - 26, y - 52, y, 0, 0.22f);
        }
        else
        {
            Ink.Line(x + 10, y + h + 7, x + 8, y + h + 20, C.Rgba(23, 19, 15, 51), 1.2f, 1f, 0.4f);
            Ink.Line(x + w - 12, y + h + 7, x + w - 10, y + h + 20, C.Rgba(23, 19, 15, 51), 1.2f, 1f, 0.4f);
            Ink.Poly(new[]
            {
                new SKPoint(x + w * 0.3f, y + h), new SKPoint(x + w * 0.4f, y + h + 12),
                new SKPoint(x + w * 0.52f, y + h)
            }, 1f, C.Rgba(23, 19, 15, 41), 1f, 0f);
        }
    }
}
