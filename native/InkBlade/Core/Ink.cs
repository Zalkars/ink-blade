using SkiaSharp;

namespace InkBlade;

public enum FontKind { Title, Display, Body, Bold, Italic, Hand }
public enum InkAlign { Left, Center, Right }
public enum InkBaseline { Alphabetic, Middle, Top }

public sealed class TextOpt
{
    public float Size = 22f;
    public FontKind Font = FontKind.Body;
    public InkAlign Align = InkAlign.Left;
    public InkBaseline Baseline = InkBaseline.Alphabetic;
    public SKColor Color = C.Ink;
    public float Alpha = 1f;
    public float Spacing;
    public float Ghost;
    public float Stroke;
    public SKColor? StrokeColor;
}

public static class C
{
    public static readonly SKColor Ink = new(0x17, 0x13, 0x0f);
    public static readonly SKColor InkSoft = new(0x4a, 0x3c, 0x2e);
    public static readonly SKColor Paper = new(0xef, 0xe4, 0xcc);
    public static readonly SKColor PaperLight = new(0xf7, 0xef, 0xdd);
    public static readonly SKColor PaperDark = new(0xdd, 0xce, 0xac);
    public static readonly SKColor Red = new(0x9c, 0x21, 0x29);
    public static readonly SKColor RedBright = new(0xc9, 0x35, 0x3a);
    public static readonly SKColor RedDark = new(0x65, 0x14, 0x19);
    public static readonly SKColor Teal = new(0x2c, 0x6f, 0x6b);
    public static readonly SKColor Gold = new(0xb8, 0x92, 0x3f);
    public static readonly SKColor Cream = new(0xf6, 0xed, 0xda);
    public static readonly SKColor Bone = new(0xe6, 0xd8, 0xba);

    public static SKColor Rgba(byte r, byte g, byte b, byte a) => new(r, g, b, a);
    public static SKColor Mul(SKColor c, float alpha)
    {
        var a = (byte)Math.Clamp((int)MathF.Round(c.Alpha * alpha), 0, 255);
        return new SKColor(c.Red, c.Green, c.Blue, a);
    }
}

public static class Ink
{
    public static SKCanvas? Cv;
    public static float Alpha = 1f;
    public static float W = 1280f, H = 720f;
    public static int Boil;

    static readonly Stack<float> AlphaStack = new();
    static SKBitmap? _paper;
    static SKBitmap? _vignette;
    static uint _seed = 123456789u;

    static readonly Dictionary<string, SKTypeface> Typefaces = new();
    static readonly Dictionary<(FontKind, int), SKFont> Fonts = new();

    /* ---------- базовая инициализация ---------- */

    public static void Init()
    {
        _paper = MakePaper(1600, 900);
        _vignette = MakeVignette((int)W, (int)H);
    }

    public static void BeginFrame(float realTime)
    {
        Boil = (int)(realTime * 10f);
    }

    public static void SetCanvas(SKCanvas canvas)
    {
        Cv = canvas;
        Alpha = 1f;
        AlphaStack.Clear();
    }

    public static void Save()
    {
        Cv?.Save();
        AlphaStack.Push(Alpha);
    }

    public static void Restore()
    {
        Cv?.Restore();
        if (AlphaStack.Count > 0) Alpha = AlphaStack.Pop();
    }

    public static void Translate(float x, float y) => Cv?.Translate(x, y);
    public static void Scale(float x, float y) => Cv?.Scale(x, y);
    public static void Rotate(float degrees) => Cv?.RotateDegrees(degrees);
    public static void ClipRect(float x, float y, float w, float h) => Cv?.ClipRect(new SKRect(x, y, x + w, y + h));

    /* ---------- случайность ---------- */

    public static void Srand(long n)
    {
        uint x = (uint)((uint)(int)n * 2654435761u) ^ ((uint)Boil * 0x9e3779b1u);
        _seed = x == 0 ? 123456789u : x;
    }

    public static float Rand()
    {
        uint x = _seed;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        _seed = x;
        return _seed / 4294967296f;
    }

    public static float Rnd(float a = 0f, float b = 1f) => a + (b - a) * Rand();

    /* ---------- шрифты ---------- */

    static SKTypeface GetTypeface(FontKind kind)
    {
        var key = kind.ToString();
        if (Typefaces.TryGetValue(key, out var tf)) return tf;
        tf = kind switch
        {
            FontKind.Title => SKTypeface.FromFamilyName("Georgia", new SKFontStyle(700, 5, SKFontStyleSlant.Italic)),
            FontKind.Display => SKTypeface.FromFamilyName("Palatino Linotype", SKFontStyle.Bold)
                                ?? SKTypeface.FromFamilyName("Georgia", SKFontStyle.Bold),
            FontKind.Bold => SKTypeface.FromFamilyName("Georgia", SKFontStyle.Bold),
            FontKind.Italic => SKTypeface.FromFamilyName("Georgia", new SKFontStyle(400, 5, SKFontStyleSlant.Italic)),
            FontKind.Hand => SKTypeface.FromFamilyName("Segoe Script")
                             ?? SKTypeface.FromFamilyName("Comic Sans MS"),
            _ => SKTypeface.FromFamilyName("Georgia")
        };
        if (tf is null) tf = SKTypeface.Default;
        Typefaces[key] = tf;
        return tf;
    }

    static SKFont GetFont(FontKind kind, float size)
    {
        var px = Math.Max(4, (int)MathF.Round(size));
        var key = (kind, px);
        if (Fonts.TryGetValue(key, out var f)) return f;
        f = new SKFont(GetTypeface(kind), px)
        {
            Subpixel = true,
            Hinting = SKFontHinting.Normal,
            Edging = SKFontEdging.SubpixelAntialias
        };
        Fonts[key] = f;
        return f;
    }

    static SKPaint Paint(SKColor color, float alpha, bool fill = true)
    {
        var p = new SKPaint
        {
            IsAntialias = true,
            Style = fill ? SKPaintStyle.Fill : SKPaintStyle.Stroke,
            Color = C.Mul(color, alpha),
            StrokeCap = SKStrokeCap.Round,
            StrokeJoin = SKStrokeJoin.Round
        };
        return p;
    }

    /* ---------- линии и фигуры ---------- */

    static List<SKPoint> Wobble(IReadOnlyList<SKPoint> pts, float amp, bool closed)
    {
        var outp = new List<SKPoint>(pts.Count * 4);
        int n = pts.Count;
        if (n < 2) return outp;
        int last = closed ? n : n - 1;
        for (int i = 0; i < last; i++)
        {
            var a = pts[i];
            var b = pts[(i + 1) % n];
            float dx = b.X - a.X, dy = b.Y - a.Y;
            float len = MathF.Sqrt(dx * dx + dy * dy) + 0.001f;
            int steps = Math.Max(1, (int)MathF.Ceiling(len / 9f));
            float nx = -dy / len, ny = dx / len;
            float phase = Rand() * MathF.PI * 2f;
            for (int s = 0; s < steps; s++)
            {
                float t = (float)s / steps;
                float w = MathF.Sin(t * MathF.PI * 2f + phase) * 0.55f + (Rand() * 2f - 1f) * 0.9f;
                outp.Add(new SKPoint(a.X + dx * t + nx * w * amp, a.Y + dy * t + ny * w * amp));
            }
        }
        if (!closed && n > 0) outp.Add(pts[n - 1]);
        return outp;
    }

    public static void Poly(IReadOnlyList<SKPoint> pts, float width = 2f, SKColor? color = null,
        float alpha = 1f, float jitter = 1.15f, bool closed = false, int passes = 1,
        float[]? dash = null, bool round = true)
    {
        if (Cv is null || pts.Count < 2) return;
        var col = color ?? C.Ink;
        using var paint = Paint(col, alpha, false);
        paint.StrokeWidth = width;
        paint.StrokeCap = round ? SKStrokeCap.Round : SKStrokeCap.Butt;
        paint.StrokeJoin = round ? SKStrokeJoin.Round : SKStrokeJoin.Miter;
        if (dash is { Length: 2 })
            paint.PathEffect = SKPathEffect.CreateDash(dash, 0f);

        for (int p = 0; p < Math.Max(1, passes); p++)
        {
            var d = Wobble(pts, jitter * (p == 0 ? 1f : 0.65f), closed);
            if (d.Count < 2) break;
            if (p > 0)
            {
                paint.Color = C.Mul(col, alpha * 0.4f);
                paint.StrokeWidth = width * 0.65f;
            }
            using var path = new SKPath();
            path.MoveTo(d[0]);
            for (int i = 1; i < d.Count; i++) path.LineTo(d[i]);
            if (closed) path.Close();
            Cv.DrawPath(path, paint);
        }
    }

    public static void Line(float x1, float y1, float x2, float y2, float width = 2f,
        SKColor? color = null, float alpha = 1f, float jitter = 1.15f, float[]? dash = null)
    {
        Poly(new[] { new SKPoint(x1, y1), new SKPoint(x2, y2) },
            width, color, alpha, jitter, false, 1, dash);
    }

    /* Удобная перегрузка для вызовов, где цвет идёт перед толщиной. */
    public static void Line(float x1, float y1, float x2, float y2, SKColor color,
        float width = 2f, float alpha = 1f, float jitter = 1.15f, float[]? dash = null)
    {
        Poly(new[] { new SKPoint(x1, y1), new SKPoint(x2, y2) },
            width, color, alpha, jitter, false, 1, dash);
    }

    public static void FillPoly(IReadOnlyList<SKPoint> pts, SKColor color, float alpha = 1f,
        float jitter = 0.9f, bool outline = false, SKColor? outlineColor = null,
        float outlineWidth = 2f, int passes = 1)
    {
        if (Cv is null || pts.Count < 3) return;
        var d = jitter <= 0f ? new List<SKPoint>(pts) : Wobble(pts, jitter, true);
        if (d.Count < 3) return;
        using var paint = Paint(color, Alpha * alpha, true);
        using var path = new SKPath();
        path.MoveTo(d[0]);
        for (int i = 1; i < d.Count; i++) path.LineTo(d[i]);
        path.Close();
        Cv.DrawPath(path, paint);
        if (outline)
            Poly(pts, outlineWidth, outlineColor ?? C.Ink, alpha, jitter, true, passes);
    }

    public static void Rect(float x, float y, float w, float h, SKColor? fill = null,
        SKColor? color = null, float width = 2f, float alpha = 1f, float jitter = 1.15f,
        bool outline = true, float[]? dash = null, int passes = 1)
    {
        var pts = new[]
        {
            new SKPoint(x, y), new SKPoint(x + w, y),
            new SKPoint(x + w, y + h), new SKPoint(x, y + h)
        };
        if (fill is { } f) FillPoly(pts, f, alpha, jitter);
        if (outline)
            Poly(pts, width, color ?? C.Ink, alpha, jitter, true, passes, dash);
    }

    public static List<SKPoint> Blob(float x, float y, float r, SKColor? fill = null,
        SKColor? color = null, float width = 2f, float alpha = 1f, float jitter = 0.6f,
        int n = 10, float wobble = 0.13f, bool outline = true, float phase = 0f)
    {
        var pts = new List<SKPoint>(n);
        for (int i = 0; i < n; i++)
        {
            float a = (float)i / n * U.TAU + phase;
            float rr = r * (1f - wobble + Rand() * wobble * 2f);
            pts.Add(new SKPoint(x + MathF.Cos(a) * rr, y + MathF.Sin(a) * rr));
        }
        if (fill is { } f) FillPoly(pts, f, alpha, jitter);
        if (outline)
            Poly(pts, width, color ?? C.Ink, alpha, MathF.Max(0.1f, jitter), true);
        return pts;
    }

    public static List<SKPoint> Circle(float x, float y, float r, SKColor? fill = null,
        SKColor? color = null, float width = 2f, float alpha = 1f, float jitter = 0.5f,
        int n = 13, bool outline = true)
    {
        var pts = new List<SKPoint>(n);
        for (int i = 0; i < n; i++)
        {
            float a = (float)i / n * U.TAU;
            pts.Add(new SKPoint(x + MathF.Cos(a) * r, y + MathF.Sin(a) * r));
        }
        if (fill is { } f) FillPoly(pts, f, alpha, jitter);
        if (outline)
            Poly(pts, width, color ?? C.Ink, alpha, MathF.Max(0.1f, jitter), true);
        return pts;
    }

    public static void Arc(float cx, float cy, float r, float a0, float a1,
        float width = 2f, SKColor? color = null, float alpha = 1f, float jitter = 0.6f,
        int steps = 0, float wobble = 0f)
    {
        if (steps <= 0) steps = Math.Max(6, (int)MathF.Ceiling(MathF.Abs(a1 - a0) * r / 12f));
        var pts = new List<SKPoint>(steps + 1);
        for (int i = 0; i <= steps; i++)
        {
            float a = U.Lerp(a0, a1, (float)i / steps);
            float rr = r + (wobble != 0f ? MathF.Sin(i * 1.7f) * wobble : 0f);
            pts.Add(new SKPoint(cx + MathF.Cos(a) * rr, cy + MathF.Sin(a) * rr));
        }
        Poly(pts, width, color, alpha, jitter);
    }

    public static void TaperArc(float cx, float cy, float r, float a0, float a1,
        float w0, float w1, SKColor color, float alpha = 1f, float jag = 1f)
    {
        const int steps = 16;
        var outer = new List<SKPoint>(steps + 1);
        var inner = new List<SKPoint>(steps + 1);
        for (int i = 0; i <= steps; i++)
        {
            float t = (float)i / steps;
            float a = U.Lerp(a0, a1, t);
            float bulge = MathF.Sin(t * MathF.PI);
            float w = U.Lerp(w0, w1, t) * (0.45f + 0.75f * bulge);
            float rr = r + bulge * 5f + (Rand() * 2f - 1f) * jag;
            outer.Add(new SKPoint(cx + MathF.Cos(a) * (rr + w * 0.5f), cy + MathF.Sin(a) * (rr + w * 0.5f)));
            inner.Add(new SKPoint(cx + MathF.Cos(a) * (rr - w * 0.5f), cy + MathF.Sin(a) * (rr - w * 0.5f)));
        }
        inner.Reverse();
        outer.AddRange(inner);
        FillPoly(outer, color, alpha, 0.7f);
    }

    public static void Hatch(IReadOnlyList<SKPoint> pts, float gap = 8f, float alpha = 0.25f,
        SKColor? color = null, float width = 1f, bool cross = false)
    {
        if (Cv is null || pts.Count < 3) return;
        float minX = float.MaxValue, minY = float.MaxValue, maxX = float.MinValue, maxY = float.MinValue;
        foreach (var p in pts)
        {
            minX = MathF.Min(minX, p.X); minY = MathF.Min(minY, p.Y);
            maxX = MathF.Max(maxX, p.X); maxY = MathF.Max(maxY, p.Y);
        }
        var d = Wobble(pts, 0.4f, true);
        if (d.Count < 3) return;
        using var clipPath = new SKPath();
        clipPath.MoveTo(d[0]);
        for (int i = 1; i < d.Count; i++) clipPath.LineTo(d[i]);
        clipPath.Close();

        Save();
        Cv.ClipPath(clipPath, SKClipOperation.Intersect, true);
        using var paint = Paint(color ?? C.Ink, Alpha * alpha, false);
        paint.StrokeWidth = width;
        paint.StrokeCap = SKStrokeCap.Round;
        float h = maxY - minY;
        float start = minX - h;
        float end = maxX + h;
        for (float x = start; x < end; x += gap)
            Cv.DrawLine(x, minY - 4, x + h + 8, maxY + 4, paint);
        if (cross)
        {
            paint.Color = C.Mul(color ?? C.Ink, Alpha * alpha * 0.6f);
            for (float x = start; x < end; x += gap * 1.7f)
                Cv.DrawLine(x + h, minY - 4, x, maxY + 4, paint);
        }
        Restore();
    }

    public static void EllipseShadow(float x, float y, float rx, float ry, float alpha = 0.25f)
    {
        if (Cv is null) return;
        Save();
        using var paint = Paint(C.Ink, 1f, true);
        for (int i = 3; i >= 1; i--)
        {
            paint.Color = C.Mul(C.Ink, alpha * (0.25f + 0.15f * i));
            Cv.DrawOval(new SKRect(x - rx * (0.7f + i * 0.12f), y - ry * (0.7f + i * 0.12f),
                x + rx * (0.7f + i * 0.12f), y + ry * (0.7f + i * 0.12f)), paint);
        }
        Restore();
    }

    /* ---------- текст ---------- */

    public static float MeasureText(string str, TextOpt o)
    {
        var font = GetFont(o.Font, o.Size);
        if (o.Spacing == 0f) return font.MeasureText(str);
        float w = 0;
        foreach (var ch in str)
            w += font.MeasureText(ch.ToString()) + o.Spacing;
        return MathF.Max(0, w - o.Spacing);
    }

    public static float MeasureText(string str, float size = 22f, FontKind kind = FontKind.Body, float spacing = 0f)
        => MeasureText(str, new TextOpt { Size = size, Font = kind, Spacing = spacing });

    public static void Text(string str, float x, float y, TextOpt o)
    {
        if (Cv is null) return;
        var font = GetFont(o.Font, o.Size);
        float total = MeasureText(str, o);
        float tx = o.Align switch
        {
            InkAlign.Center => x - total * 0.5f,
            InkAlign.Right => x - total,
            _ => x
        };
        float ty = y;
        if (o.Baseline != InkBaseline.Alphabetic)
        {
            var m = font.Metrics;
            ty = o.Baseline == InkBaseline.Middle ? y - (m.Ascent + m.Descent) * 0.5f : y - m.Ascent;
        }

        float em = MathF.Max(0.001f, o.Alpha);
        using var fill = Paint(o.Color, Alpha * em, true);
        if (o.Ghost > 0f)
        {
            using var gp = Paint(o.Color, Alpha * em * 0.28f, true);
            DrawStr(str, tx + o.Ghost, ty + o.Ghost, font, gp, o.Spacing);
        }
        if (o.Stroke > 0f)
        {
            using var sp = Paint(o.StrokeColor ?? C.Ink, Alpha * em, false);
            sp.StrokeWidth = o.Stroke;
            DrawStr(str, tx, ty, font, sp, o.Spacing);
        }
        DrawStr(str, tx, ty, font, fill, o.Spacing);
    }

    static void DrawStr(string str, float x, float y, SKFont font, SKPaint paint, float spacing)
    {
        if (Cv is null) return;
        if (spacing == 0f)
        {
            Cv.DrawText(str, x, y, font, paint);
            return;
        }
        float cx = x;
        foreach (var ch in str)
        {
            Cv.DrawText(ch.ToString(), cx, y, font, paint);
            cx += font.MeasureText(ch.ToString()) + spacing;
        }
    }

    /* ---------- фон ---------- */

    public static void Paper()
    {
        if (Cv is null || _paper is null) return;
        using var paint = new SKPaint { IsAntialias = false };
        Cv.DrawBitmap(_paper, new SKRect(0, 0, W, H), paint);
    }

    public static void DrawPaper(SKCanvas canvas, SKRect dest)
    {
        if (_paper is null) return;
        using var paint = new SKPaint { IsAntialias = true };
        canvas.DrawBitmap(_paper, dest, paint);
    }

    public static void Vignette()
    {
        if (Cv is null || _vignette is null) return;
        using var paint = new SKPaint { IsAntialias = false };
        Cv.DrawBitmap(_vignette, new SKRect(0, 0, W, H), paint);
    }

    public static void FillRectGradient(float x, float y, float w, float h, float topY, float bottomY,
        (float pos, SKColor col)[] stops)
    {
        if (Cv is null) return;
        var colors = stops.Select(s => s.col).ToArray();
        var pos = stops.Select(s => s.pos).ToArray();
        using var shader = SKShader.CreateLinearGradient(new SKPoint(0, topY), new SKPoint(0, bottomY),
            colors, pos, SKShaderTileMode.Clamp);
        using var paint = new SKPaint { IsAntialias = true, Shader = shader };
        Cv.DrawRect(new SKRect(x, y, x + w, y + h), paint);
    }

    public static void FillRectColor(float x, float y, float w, float h, SKColor col, float alpha = 1f)
    {
        if (Cv is null) return;
        using var paint = new SKPaint { IsAntialias = false, Color = C.Mul(col, Alpha * alpha) };
        Cv.DrawRect(new SKRect(x, y, x + w, y + h), paint);
    }

    public static void FillCircleColor(float x, float y, float r, SKColor col, float alpha = 1f)
    {
        if (Cv is null) return;
        using var paint = new SKPaint { IsAntialias = true, Color = C.Mul(col, Alpha * alpha) };
        Cv.DrawCircle(x, y, r, paint);
    }

    public static void RadialGlow(float cx, float cy, float r, SKColor col, float alpha,
        float x, float y, float w, float h)
    {
        if (Cv is null) return;
        using var shader = SKShader.CreateRadialGradient(new SKPoint(cx, cy), r,
            new[] { C.Mul(col, alpha), C.Mul(col, 0f) },
            new[] { 0f, 1f }, SKShaderTileMode.Clamp);
        using var paint = new SKPaint { IsAntialias = true, Shader = shader };
        Cv.DrawRect(new SKRect(x, y, x + w, y + h), paint);
    }

    public static void RadialRect(float x, float y, float w, float h, float cx, float cy, float r,
        (float pos, SKColor col)[] stops)
    {
        if (Cv is null) return;
        var colors = stops.Select(s => s.col).ToArray();
        var pos = stops.Select(s => s.pos).ToArray();
        using var shader = SKShader.CreateRadialGradient(new SKPoint(cx, cy), r, colors, pos, SKShaderTileMode.Clamp);
        using var paint = new SKPaint { IsAntialias = true, Shader = shader };
        Cv.DrawRect(new SKRect(x, y, x + w, y + h), paint);
    }

    /* ---------- текстуры ---------- */

    static SKBitmap MakePaper(int w, int h)
    {
        var bmp = new SKBitmap(new SKImageInfo(w, h, SKColorType.Bgra8888, SKAlphaType.Premul));
        using var canvas = new SKCanvas(bmp);
        using (var paint = new SKPaint { IsAntialias = true })
        {
            using var shader = SKShader.CreateLinearGradient(new SKPoint(0, 0), new SKPoint(w * 0.55f, h),
                new[] { new SKColor(0xf4, 0xec, 0xd9), new SKColor(0xef, 0xe4, 0xcc), new SKColor(0xe3, 0xd4, 0xb3) },
                new[] { 0f, 0.5f, 1f }, SKShaderTileMode.Clamp);
            paint.Shader = shader;
            canvas.DrawRect(0, 0, w, h, paint);
        }

        using (var paint = new SKPaint { IsAntialias = true })
        {
            for (int i = 0; i < 85; i++)
            {
                float x = U.Rnd(0, w), y = U.Rnd(0, h), r = U.Rnd(30, 250);
                bool dark = U.Chance(0.6f);
                using var shader = SKShader.CreateRadialGradient(new SKPoint(x, y), r,
                    new[] { dark ? new SKColor(120, 95, 58, 11) : new SKColor(255, 250, 235, 26),
                            new SKColor(120, 95, 58, 0) },
                    new[] { 0f, 1f }, SKShaderTileMode.Clamp);
                paint.Shader = shader;
                canvas.DrawRect(x - r, y - r, r * 2, r * 2, paint);
            }
            paint.Shader = null;

            for (int i = 0; i < 520; i++)
            {
                float x = U.Rnd(0, w), y = U.Rnd(0, h), len = U.Rnd(4, 30), a = U.Rnd(0, MathF.PI);
                paint.Style = SKPaintStyle.Stroke;
                paint.StrokeWidth = 1;
                paint.Color = new SKColor(110, 88, 55, (byte)U.Rnd(4, 15));
                canvas.DrawLine(x, y, x + MathF.Cos(a) * len, y + MathF.Sin(a) * len, paint);
            }

            paint.Style = SKPaintStyle.Fill;
            for (int i = 0; i < 2600; i++)
            {
                float x = U.Rnd(0, w), y = U.Rnd(0, h);
                float s = U.Chance(0.85f) ? 1 : 2;
                paint.Color = new SKColor(60, 46, 30, (byte)U.Rnd(5, 23));
                canvas.DrawRect(x, y, s, s, paint);
            }
        }

        using (var paint = new SKPaint { IsAntialias = true })
        {
            using var shader = SKShader.CreateRadialGradient(new SKPoint(w / 2f, h / 2f), MathF.Max(w, h) * 0.72f,
                new[] { new SKColor(70, 52, 30, 0), new SKColor(70, 52, 30, 13), new SKColor(55, 40, 24, 66) },
                new[] { 0f, 0.72f, 1f }, SKShaderTileMode.Clamp);
            paint.Shader = shader;
            canvas.DrawRect(0, 0, w, h, paint);
        }
        return bmp;
    }

    static SKBitmap MakeVignette(int w, int h)
    {
        var bmp = new SKBitmap(new SKImageInfo(w, h, SKColorType.Bgra8888, SKAlphaType.Premul));
        using var canvas = new SKCanvas(bmp);
        using var paint = new SKPaint { IsAntialias = true };
        using var shader = SKShader.CreateRadialGradient(new SKPoint(w / 2f, h / 2f), MathF.Max(w, h) * 0.78f,
            new[] { new SKColor(20, 14, 8, 0), new SKColor(20, 14, 8, 18), new SKColor(20, 14, 8, 97) },
            new[] { 0f, 0.7f, 1f }, SKShaderTileMode.Clamp);
        paint.Shader = shader;
        canvas.DrawRect(0, 0, w, h, paint);
        return bmp;
    }
}
