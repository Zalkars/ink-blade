namespace InkBlade;

public struct Rect
{
    public float X, Y, W, H;
    public Rect(float x, float y, float w, float h) { X = x; Y = y; W = w; H = h; }
    public readonly float Right => X + W;
    public readonly float Bottom => Y + H;
    public readonly float Cx => X + W * 0.5f;
    public readonly float Cy => Y + H * 0.5f;
}

public class Body
{
    public float X, Y, W, H;
    public float Vx, Vy;
    public bool Grounded, OnOneWay, HitWall;
    public float DropT;
    public float Cx => X + W * 0.5f;
    public float Cy => Y + H * 0.5f;
}

public static class U
{
    public const float TAU = MathF.PI * 2f;
    static readonly Random Rng = new();

    public static float Clamp(float v, float a, float b) => v < a ? a : v > b ? b : v;
    public static float Clamp01(float v) => v < 0 ? 0 : v > 1 ? 1 : v;
    public static float Lerp(float a, float b, float t) => a + (b - a) * t;
    public static float InvLerp(float a, float b, float v) => b == a ? 0 : (v - a) / (b - a);
    public static float Approach(float v, float target, float delta) =>
        v < target ? MathF.Min(v + delta, target) : MathF.Max(v - delta, target);
    public static float Damp(float v, float target, float lambda, float dt) =>
        Lerp(v, target, 1f - MathF.Exp(-lambda * dt));
    public static int Sign(float v) => v < 0 ? -1 : 1;
    public static float Rnd(float a = 0, float b = 1) => a + (float)Rng.NextDouble() * (b - a);
    public static int RndInt(int a, int b) => (int)MathF.Floor(Rnd(a, b + 1));
    public static bool Chance(float p) => Rng.NextDouble() < p;
    public static T Pick<T>(IReadOnlyList<T> arr) => arr[(int)(Rng.NextDouble() * arr.Count)];
    public static float Smooth(float t) => t * t * (3f - 2f * t);
    public static float EaseOutCubic(float t) => 1f - MathF.Pow(1f - t, 3f);
    public static float EaseInCubic(float t) => t * t * t;
    public static float EaseOutBack(float t)
    {
        const float c1 = 1.70158f;
        const float c3 = c1 + 1f;
        return 1f + c3 * MathF.Pow(t - 1f, 3f) + c1 * MathF.Pow(t - 1f, 2f);
    }
    public static float EaseOutElastic(float t)
    {
        if (t <= 0f || t >= 1f) return t;
        const float c4 = TAU / 3f;
        return MathF.Pow(2f, -10f * t) * MathF.Sin((t * 10f - 0.75f) * c4) + 1f;
    }

    public static bool Overlap(Rect a, Rect b) =>
        a.X < b.X + b.W && a.X + a.W > b.X && a.Y < b.Y + b.H && a.Y + a.H > b.Y;

    public static bool Overlap(Body a, Rect b) =>
        a.X < b.X + b.W && a.X + a.W > b.X && a.Y < b.Y + b.H && a.Y + a.H > b.Y;

    public static bool Overlap(Body a, Body b) =>
        a.X < b.X + b.W && a.X + a.W > b.X && a.Y < b.Y + b.H && a.Y + a.H > b.Y;

    public static bool PointIn(float px, float py, Rect r) =>
        px >= r.X && px <= r.X + r.W && py >= r.Y && py <= r.Y + r.H;

    public static float Dist(float x1, float y1, float x2, float y2) =>
        MathF.Sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));

    public static float AngleTo(float x1, float y1, float x2, float y2) =>
        MathF.Atan2(y2 - y1, x2 - x1);

    public static string FmtTime(float seconds)
    {
        var s = MathF.Max(0f, seconds);
        var m = (int)(s / 60f);
        var rest = (int)(s % 60f);
        return $"{m}:{rest:00}";
    }
}
