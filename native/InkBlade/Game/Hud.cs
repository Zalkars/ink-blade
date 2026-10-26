using SkiaSharp;

namespace InkBlade;

public static class Hud
{
    public static void Panel(float x, float y, float w, float h, string? title = null, float titleSize = 26f)
    {
        Ink.Srand((long)(x * 3 + y));
        Ink.Save();
        Ink.Alpha = 0.35f;
        Ink.FillRectColor(x + 8, y + 9, w, h, C.Ink);
        Ink.Restore();

        Ink.Rect(x, y, w, h, C.Rgba(246, 237, 218, 245), C.Ink, 2.6f, 1f, 1.1f);
        Ink.Rect(x + 6, y + 6, w - 12, h - 12, null, C.Rgba(23, 19, 15, 46), 1f, 1f, 0.7f);

        const float m = 12;
        var corners = new[]
        {
            (x + m, y + m, 1f, 1f), (x + w - m, y + m, -1f, 1f),
            (x + m, y + h - m, 1f, -1f), (x + w - m, y + h - m, -1f, -1f)
        };
        foreach (var c in corners)
        {
            Ink.Line(c.Item1, c.Item2, c.Item1 + 12 * c.Item3, c.Item2, 1.4f, C.Rgba(23, 19, 15, 89));
            Ink.Line(c.Item1, c.Item2, c.Item1, c.Item2 + 12 * c.Item4, 1.4f, C.Rgba(23, 19, 15, 89));
        }

        if (title is not null)
        {
            Ink.Text(title, x + w / 2, y + 40, new TextOpt
            {
                Size = titleSize, Font = FontKind.Display, Align = InkAlign.Center,
                Color = C.Ink, Spacing = 4
            });
            Ink.Line(x + 34, y + 54, x + w - 34, y + 54, C.Rgba(156, 33, 41, 153), 2f, 1f, 1f);
        }

        Ink.Save();
        Ink.Alpha = 0.7f;
        Ink.Circle(x + w - 30, y + h - 30, 11, null, C.Red, 1.6f, 1f, 0.8f, 10);
        Ink.Text("Ч", x + w - 30, y + h - 25, new TextOpt
        {
            Size = 12, Font = FontKind.Display, Align = InkAlign.Center, Color = C.Red
        });
        Ink.Restore();
    }

    public static float Glyph(float x, float y, string label, bool active = false,
        float size = 28f, float fontSize = 13f, float pad = 9f)
    {
        float w = MathF.Max(size, Ink.MeasureText(label, fontSize, FontKind.Bold) + pad * 2);
        float h = size;
        Ink.Srand((long)(x * 7 + y));
        if (active)
        {
            Ink.Rect(x, y - h / 2, w, h, C.Red, C.RedDark, 1.6f, 1f, 0.7f);
            Ink.Text(label, x + w / 2, y + 1, new TextOpt
            {
                Size = fontSize, Font = FontKind.Bold, Align = InkAlign.Center,
                Baseline = InkBaseline.Middle, Color = C.Cream
            });
        }
        else
        {
            Ink.Rect(x, y - h / 2, w, h, C.Rgba(246, 237, 218, 191), C.Rgba(23, 19, 15, 179), 1.4f, 1f, 0.7f);
            Ink.Text(label, x + w / 2, y + 1, new TextOpt
            {
                Size = fontSize, Font = FontKind.Bold, Align = InkAlign.Center,
                Baseline = InkBaseline.Middle, Color = C.Ink
            });
        }
        return w;
    }

    public static void Draw(Game game)
    {
        DrawMasks(game.Player);
        DrawSoul(game.Player);
        DrawDash(game.Player);
        DrawCombo(game);
        DrawDevice();
        DrawHints(game);
        DrawBanner(game);
    }

    static void DrawMasks(Player p)
    {
        for (int i = 0; i < p.MaxHp; i++)
        {
            float x = 56 + i * 34;
            const float y = 44;
            bool alive = i < p.Hp;
            bool last = alive && p.Hp == 1;
            Ink.Srand(300 + i);
            if (alive)
            {
                float pulse = last ? 1 + MathF.Sin(p.T * 6) * 0.06f : 1;
                Ink.Blob(x, y, 11 * pulse, C.Red, C.Ink, 2f, 1f, 0.8f, 9, 0.1f);
                Ink.Circle(x - 6.5f, y - 4, 2.1f, C.Cream, outline: false, alpha: 0.85f, jitter: 0.2f);
                Ink.Circle(x + 4, y - 5, 2.1f, C.Cream, outline: false, alpha: 0.85f, jitter: 0.2f);
                Ink.Line(x - 4, y + 4, x + 4, y + 4, 1.6f, C.RedDark, 0.8f);
            }
            else
            {
                Ink.Blob(x, y, 11, null, C.Rgba(23, 19, 15, 89), 1.5f, 1f, 0.8f, 9, 0.1f);
                Ink.Line(x - 6, y - 6, x + 2, y + 2, 1.1f, C.Rgba(23, 19, 15, 71));
                Ink.Line(x + 4, y - 5, x + 1, y + 1, 1f, C.Rgba(23, 19, 15, 56));
            }
        }
    }

    static void DrawSoul(Player p)
    {
        const float x = 57, y = 101, r = 21;
        float k = p.Soul / 99f;
        bool ready = p.Soul >= 40;

        Ink.Srand(310);
        Ink.Save();
        using (var clip = new SKPath())
        {
            clip.AddCircle(x, y, r - 3);
            Ink.Cv?.ClipPath(clip, SKClipOperation.Intersect, true);
        }
        Ink.FillRectColor(x - r, y - r, r * 2, r * 2, C.Rgba(240, 230, 208, 230));
        float top = y + r - (r * 2) * k;
        var pts = new List<SKPoint> { new(x - r, y + r) };
        for (int i = 0; i <= 12; i++)
        {
            float xx = x - r + (i / 12f) * r * 2;
            pts.Add(new SKPoint(xx, top + MathF.Sin(i * 1.3f + p.T * 3) * 1.6f));
        }
        pts.Add(new SKPoint(x + r, y + r));
        using (var shader = SKShader.CreateLinearGradient(new SKPoint(0, top), new SKPoint(0, y + r),
            new[] { C.Rgba(23, 19, 15, 184), C.Rgba(23, 19, 15, 230) }, new[] { 0f, 1f }, SKShaderTileMode.Clamp))
        using (var paint = new SKPaint { IsAntialias = true, Shader = shader, Style = SKPaintStyle.Fill })
        using (var path = new SKPath())
        {
            path.MoveTo(pts[0]);
            for (int i = 1; i < pts.Count; i++) path.LineTo(pts[i]);
            path.Close();
            Ink.Cv?.DrawPath(path, paint);
        }
        Ink.Restore();

        Ink.Circle(x, y, r, null, ready ? C.Red : C.Rgba(23, 19, 15, 166), ready ? 2.6f : 2f, 1f, 0.9f, 14);
        Ink.Line(x - r + 4, y - 6, x - r + 4, y + 9, 1f, C.Rgba(246, 237, 218, 102));

        if (ready)
        {
            float pulse = 0.5f + MathF.Sin(p.T * 5) * 0.3f;
            Ink.Save();
            Ink.Alpha = pulse * 0.5f;
            Ink.Circle(x, y, r + 5, null, C.Red, 1.2f, 1f, 1f, 16);
            Ink.Restore();
        }

        float costY = y + r - (r * 2) * (40f / 99f);
        Ink.Line(x + r + 3, costY, x + r + 11, costY, 1.2f, C.Rgba(156, 33, 41, 128));
        Ink.Text("ДУША", x + r + 14, y + 4, new TextOpt
        {
            Size = 10, Font = FontKind.Display, Color = C.Ink, Alpha = 0.4f, Spacing = 2
        });
    }

    static void DrawDash(Player p)
    {
        const float x = 38, y = 143;
        bool ready = p.DashCd <= 0 && (p.Grounded || p.AirDash);
        Ink.Srand(320);
        for (int i = 0; i < 3; i++)
        {
            Ink.Poly(new[]
            {
                new SKPoint(x + i * 9, y - 8), new SKPoint(x + 8 + i * 9, y),
                new SKPoint(x + i * 9, y + 8)
            }, 2.6f, ready ? C.Ink : C.Rgba(23, 19, 15, 56), ready ? 0.9f : 0.5f, 0.5f);
            if (!ready)
            {
                float k = 1 - MathF.Min(1, p.DashCd / 0.34f);
                if (i / 3f < k)
                    Ink.Poly(new[]
                    {
                        new SKPoint(x + i * 9, y - 8), new SKPoint(x + 8 + i * 9, y),
                        new SKPoint(x + i * 9, y + 8)
                    }, 2.6f, C.Rgba(156, 33, 41, 140), 1f, 0.4f);
            }
        }
        Ink.Text("РЫВОК", x + 4, y + 19, new TextOpt
        {
            Size = 9, Font = FontKind.Display, Color = C.Ink, Alpha = 0.35f, Spacing = 2
        });
    }

    static void DrawCombo(Game game)
    {
        if (game.Combo < 2) return;
        float a = U.Clamp01(game.ComboT / 1.6f);
        float pop = 1 + game.ComboPop * 0.4f;
        Ink.Save();
        Ink.Alpha = MathF.Min(1, a * 2);
        Ink.Text($"×{game.Combo}", 640, 58, new TextOpt
        {
            Size = MathF.Round(34 * pop), Font = FontKind.Hand, Align = InkAlign.Center,
            Color = C.Red, Ghost = 1.2f
        });
        Ink.Text("СЕРИЯ", 640, 74, new TextOpt
        {
            Size = 9, Font = FontKind.Display, Align = InkAlign.Center,
            Color = C.Ink, Alpha = 0.4f, Spacing = 3
        });
        Ink.Restore();
    }

    static void DrawDevice()
    {
        bool gp = Input.Device == "gamepad";
        const float x = 1236;
        Ink.Save();
        Ink.Alpha = 0.45f;
        Ink.Text(gp ? "ГЕЙМПАД" : "КЛАВИАТУРА", x - 30, 34, new TextOpt
        {
            Size = 10, Font = FontKind.Display, Align = InkAlign.Right, Color = C.Ink, Spacing = 2
        });
        Ink.Text("F1 — УПРАВЛЕНИЕ", x - 30, 52, new TextOpt
        {
            Size = 10, Font = FontKind.Display, Align = InkAlign.Right, Color = C.Ink, Spacing = 1
        });
        Ink.Alpha = 0.4f;
        if (gp)
        {
            Ink.Rect(x - 22, 24, 20, 12, null, C.Ink, 1.4f, 1f, 0.5f);
            Ink.Circle(x - 17, 29, 1.6f, C.Ink, outline: false, jitter: 0.2f);
            Ink.Circle(x - 11, 31, 1.6f, C.Ink, outline: false, jitter: 0.2f);
        }
        else
        {
            Ink.Rect(x - 22, 25, 20, 11, null, C.Ink, 1.4f, 1f, 0.5f);
            Ink.Line(x - 18, 30, x - 15, 30, 1f, C.Ink);
            Ink.Line(x - 12, 30, x - 9, 30, 1f, C.Ink);
        }
        Ink.Restore();
    }

    static void DrawHints(Game game)
    {
        float a = game.HintAlpha;
        if (a <= 0.01f) return;
        var lines = new[]
        {
            new[] { (InputAction.Attack, "удар"), (InputAction.Dash, "рывок"), (InputAction.Heal, "лечение (удерж)") },
            new[] { (InputAction.Jump, "прыжок"), (InputAction.Down, "вниз + прыжок — спрыгнуть"), (InputAction.Pause, "пауза") }
        };
        Ink.Save();
        Ink.Alpha = a * 0.8f;
        const float x = 44, y = 650;
        Ink.Rect(x - 12, y - 24, 660, 62, C.Rgba(246, 237, 218, 179), C.Rgba(23, 19, 15, 77), 1.2f, 1f, 0.8f);
        for (int li = 0; li < lines.Length; li++)
        {
            float cx = x;
            float cy = y + li * 24;
            foreach (var (action, text) in lines[li])
            {
                string label = Input.Label(action);
                float w = Glyph(cx, cy - 4, label, false, 20, 11, 8);
                cx += w + 9;
                Ink.Text(text, cx, cy + 1, new TextOpt
                {
                    Size = 12, Font = FontKind.Body, Color = C.Ink, Alpha = 0.75f
                });
                cx += Ink.MeasureText(text, 12, FontKind.Body) + 17;
            }
        }
        Ink.Restore();
    }

    static void DrawBanner(Game game)
    {
        var b = game.Banner;
        if (b.T <= 0) return;
        float a = 1;
        if (b.T > b.Max - 0.5f) a = (b.Max - b.T) / 0.5f;
        else if (b.T < 1.2f) a = b.T / 1.2f;
        Ink.Save();
        Ink.Alpha = U.Clamp01(a);
        Ink.Text(b.Title, 640, 238, new TextOpt
        {
            Size = 40, Font = FontKind.Title, Align = InkAlign.Center,
            Color = C.Ink, Spacing = 3, Ghost = 2
        });
        Ink.Line(480, 254, 800, 254, C.Red, 2.5f, 1f, 1.4f);
        if (!string.IsNullOrEmpty(b.Sub))
            Ink.Text(b.Sub, 640, 280, new TextOpt
            {
                Size = 15, Font = FontKind.Hand, Align = InkAlign.Center,
                Color = C.Ink, Alpha = 0.65f
            });
        Ink.Restore();
    }
}
