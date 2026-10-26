using SkiaSharp;

namespace InkBlade;

public class EnemyBase : Body
{
    static int _nextId = 1;

    public readonly Game Game;
    public readonly string Type;
    public readonly string Id;
    public float Hp, MaxHp;
    public readonly float SpawnX, SpawnY;
    public int Facing = -1;
    public float T, HurtT, PipT;
    public bool Dead;
    public float RespawnT;
    public bool Contact = true;
    public bool Hover;
    public string State = "idle";
    public float StateT;
    public float TouchCd;

    protected EnemyBase(Game game, string type, float x, float y, float w, float h, float hp)
    {
        Game = game;
        Type = type;
        Id = "e" + _nextId++;
        X = x; Y = y; W = w; H = h;
        Hp = MaxHp = hp;
        SpawnX = x; SpawnY = y;
    }

    public Rect Hitbox() => new(X + 3, Y + 3, W - 6, H - 5);

    public void SetState(string s, float dur)
    {
        State = s;
        StateT = dur;
    }

    public virtual void Update(float dt)
    {
        T += dt;
        HurtT = MathF.Max(0, HurtT - dt);
        PipT = MathF.Max(0, PipT - dt);
        TouchCd = MathF.Max(0, TouchCd - dt);

        if (Dead)
        {
            RespawnT -= dt;
            if (RespawnT <= 0) Respawn();
            return;
        }

        Behavior(dt);
        Physics(dt);
    }

    public virtual void Behavior(float dt) { }

    public virtual void Draw() { }

    public virtual void Physics(float dt, float gravity = 2400f)
    {
        if (!Hover)
        {
            Vy = MathF.Min(Vy + gravity * dt, 1100f);
            World.MoveX(this, dt);
            World.MoveY(this, dt);
        }
    }

    public virtual void Hurt(float dmg, float dirX, bool heavy)
    {
        if (Dead) return;
        Hp -= dmg;
        HurtT = 0.2f;
        PipT = 2.2f;
        Vx = dirX * (Hover ? 120f : 210f);
        if (!Hover) Vy = -150f;
        Fx.Text(Cx, Y - 6, ((int)dmg).ToString(), dmg > 1 ? 30 : 23,
            dmg > 1 ? C.RedBright : C.Red, false, 0.75f);
        Fx.InkBurst(Cx, Cy, 7, 230f, size: 4f, drops: true);
        Fx.Sparks(Cx, Cy, dirX > 0 ? 0 : MathF.PI, 6);
        Audio.Hit(dmg > 1);
        Fx.AddShake(dmg > 1 ? 7 : 3.5f);
        Game.Freeze(dmg > 1 ? 0.075f : 0.045f);
        Game.AddCombo();
        Input.Rumble(0.25f, 0.5f, 90);

        if (Hp <= 0) Die();
    }

    public virtual void Die()
    {
        Dead = true;
        RespawnT = 3.6f;
        Fx.InkBurst(Cx, Cy, 26, 380f, new[] { C.Ink, C.Ink, C.RedDark, C.InkSoft }, 6f, true);
        Fx.Ring(Cx, Cy, 6, 90, C.InkSoft, 0.45f, 3);
        Audio.Kill();
        Fx.AddShake(8);
        Game.Freeze(0.06f);
        Game.OnEnemyKilled(this);
    }

    public virtual void Respawn()
    {
        Dead = false;
        Hp = MaxHp;
        X = SpawnX;
        Y = SpawnY;
        Vx = 0; Vy = 0;
        Facing = -1;
        HurtT = 0;
        PipT = 0;
        State = "patrol";
        StateT = 0.6f;
        Fx.Ring(Cx, Cy, 4, 56, C.InkSoft, 0.5f, 2);
        Fx.InkBurst(Cx, Cy, 12, 120f, new[] { C.Ink, C.InkSoft }, 4f,
            false, null, 0, 0, -120f, 9999f);
        Audio.Spawn();
    }

    public void DrawPips()
    {
        if (Dead || Hp >= MaxHp || MaxHp >= 90) return;
        float alpha = MathF.Min(0.7f, PipT);
        for (int i = 0; i < MaxHp; i++)
        {
            float x = Cx + (i - (MaxHp - 1) / 2f) * 9;
            float y = Y - 10;
            if (i < Hp)
                Ink.Circle(x, y, 2.6f, C.Red, outline: false, alpha: alpha, jitter: 0.3f, n: 6);
            else
                Ink.Circle(x, y, 2.2f, color: C.Ink, width: 1f, alpha: alpha * 0.5f, jitter: 0.3f, n: 6);
        }
    }
}

/* ---------- чернильный гончий ---------- */

public sealed class Grunt : EnemyBase
{
    readonly float _minX, _maxX;
    float _glow, _legPhase;

    public Grunt(Game game, float x, float y, int facing = -1, float? minX = null, float? maxX = null)
        : base(game, "grunt", x, y, 56, 36, 3)
    {
        Facing = facing;
        _minX = minX ?? x - 110;
        _maxX = maxX ?? x + 110;
        SetState("patrol", 0.4f);
    }

    public override void Behavior(float dt)
    {
        var p = Game.Player;
        float dx = p.Cx - Cx;
        float dy = p.Cy - Cy;
        bool sees = !p.Dead && MathF.Abs(dx) < 340 && MathF.Abs(dy) < 120;

        if (HurtT > 0)
        {
            Vx *= MathF.Pow(0.02f, dt);
            return;
        }

        switch (State)
        {
            case "patrol":
                Vx = Facing * 78f;
                if (Grounded)
                {
                    float aheadX = Facing > 0 ? X + W + 10 : X - 10;
                    bool ground = World.HasGroundAt(aheadX, Y + H + 3);
                    if (!ground || X < _minX || X + W > _maxX || HitWall)
                    {
                        Facing *= -1;
                        SetState("patrol", 0.45f);
                        Vx = 0;
                    }
                }
                _legPhase += MathF.Abs(Vx) * dt * 0.09f;
                if (sees)
                {
                    Facing = U.Sign(dx);
                    SetState("windup", 0.48f);
                    Vx = 0;
                }
                break;
            case "windup":
                Vx = U.Approach(Vx, 0, 2400 * dt);
                _glow = MathF.Min(1, _glow + dt * 5);
                Facing = U.Sign(dx);
                StateT -= dt;
                if (StateT <= 0)
                {
                    SetState("lunge", 0.27f);
                    Vx = Facing * 650;
                    Vy = -60;
                    Fx.Dust(Cx, Y + H, 5, -Facing);
                    Audio.Noise(new NoiseOptions { Freq = 700, Dur = 0.12f, Gain = 0.05f, Type = "lowpass" });
                }
                break;
            case "lunge":
                Vx = Facing * 650;
                StateT -= dt;
                if (StateT <= 0)
                {
                    SetState("recover", 0.55f);
                    Vx *= 0.2f;
                }
                break;
            case "recover":
                Vx = U.Approach(Vx, 0, 2600 * dt);
                _glow = MathF.Max(0, _glow - dt * 4);
                StateT -= dt;
                if (StateT <= 0) SetState("patrol", 0.5f);
                break;
            default:
                StateT -= dt;
                if (StateT <= 0) SetState("patrol", 0.5f);
                break;
        }

        if (State != "windup") _glow = MathF.Max(0, _glow - dt * 3);
    }

    public override void Hurt(float dmg, float dirX, bool heavy)
    {
        base.Hurt(dmg, dirX, heavy);
        if (!Dead) SetState("recover", 0.32f);
    }

    public override void Draw()
    {
        if (Dead) return;
        float gy = Y + H;
        Ink.EllipseShadow(Cx, gy - 2, 26, 5, 0.2f);

        if (State == "windup")
        {
            float k = 1 - MathF.Max(0, StateT) / 0.48f;
            Ink.Save();
            Ink.Alpha = 0.2f + k * 0.55f;
            Ink.Line(Cx + Facing * 20, Cy, Game.Player.Cx, Game.Player.Cy,
                1.6f, C.Red, 1f, 0f, new[] { 7f, 8f });
            Ink.Restore();
        }

        Ink.Save();
        Ink.Translate(Cx, gy);
        float squash = State == "windup" ? 1 + _glow * 0.1f : 1;
        Ink.Scale(Facing, 2 - squash);

        bool flash = HurtT > 0 && (int)(HurtT * 50) % 2 == 0;
        var fill = flash ? C.Red : C.Cream;
        var back = flash ? C.Red : C.Rgba(23, 19, 15, 36);

        /* ноги */
        for (int i = 0; i < 3; i++)
        {
            float lx = -14 + i * 12;
            float swing = State == "patrol" ? MathF.Sin(_legPhase + i * 2.1f) * 3 : 1.5f;
            Ink.Poly(new[]
            {
                new SKPoint(lx, -12), new SKPoint(lx + 2 + swing, -5),
                new SKPoint(lx + 3 + swing, -1)
            }, 2.7f, C.Ink, 1f, 0.5f);
        }

        /* хвост */
        float tail = MathF.Sin(T * 4) * 4;
        Ink.Poly(new[]
        {
            new SKPoint(-24, -15), new SKPoint(-31, -20 + tail), new SKPoint(-34, -28 + tail)
        }, 2.4f, C.Ink, 1f, 0.7f);

        /* тело */
        var body = new[]
        {
            new SKPoint(-26, -12), new SKPoint(-23, -22), new SKPoint(-12, -27),
            new SKPoint(4, -28), new SKPoint(17, -24), new SKPoint(26, -17),
            new SKPoint(28, -9), new SKPoint(22, -4), new SKPoint(10, -3),
            new SKPoint(-4, -4), new SKPoint(-17, -3), new SKPoint(-24, -7)
        };
        Ink.Srand((long)(SpawnX + SpawnY));
        Ink.FillPoly(body, fill, 1f, 1f);
        Ink.Poly(body, 2.4f, C.Ink, 1f, 1f, true);

        /* тёмная спина */
        Ink.Save();
        Ink.Alpha = 0.55f;
        Ink.FillPoly(new[]
        {
            new SKPoint(-22, -20), new SKPoint(-12, -27), new SKPoint(4, -28),
            new SKPoint(16, -24), new SKPoint(6, -20), new SKPoint(-8, -18)
        }, back, 1f, 0.8f, false);
        Ink.Restore();

        /* шипы на спине */
        for (int i = 0; i < 3; i++)
        {
            float bx = -14 + i * 9;
            Ink.FillPoly(new[]
            {
                new SKPoint(bx - 4, -25), new SKPoint(bx, -35 - i), new SKPoint(bx + 4, -25)
            }, flash ? C.Red : C.Ink, 1f, 0.5f);
        }

        /* морда и пасть */
        Ink.Poly(new[]
        {
            new SKPoint(17, -20), new SKPoint(30, -15), new SKPoint(31, -9),
            new SKPoint(23, -6)
        }, 2f, C.Ink, 1f, 0.5f);
        Ink.FillPoly(new[]
        {
            new SKPoint(22, -12), new SKPoint(31, -9), new SKPoint(25, -6)
        }, C.Ink, 1f, 0.5f);
        Ink.Line(23, -8.5f, 29, -8.5f, C.Cream, 1.2f, 0.75f, 0.2f);
        for (int i = 0; i < 3; i++)
            Ink.Line(24 + i * 2.1f, -9, 24.6f + i * 2.1f, -6.6f, C.Cream, 0.9f, 0.7f, 0.1f);

        /* глаз */
        float eyeGlow = _glow;
        float eyeR = 6.2f + eyeGlow * 2.2f;
        Ink.Circle(19, -17, eyeR, C.Cream, C.Ink, 1.6f, 1f, 0.4f, 9);
        Ink.Blob(21, -17, 2.8f + eyeGlow * 0.8f,
            eyeGlow > 0.4f ? C.RedBright : C.Red, outline: false, jitter: 0.3f);
        Ink.Line(23.5f, -18, 23.5f, -18, 1f, C.Cream);
        Ink.Poly(new[] { new SKPoint(24, -12), new SKPoint(28, -13) }, 1.4f, C.Ink);

        if (State == "lunge" && U.Chance(0.4f))
            Fx.Dust(Cx - Facing * 18, gy, 1, -Facing);

        Ink.Restore();
        DrawPips();
    }
}

/* ---------- парящее око ---------- */

public sealed class Sentry : EnemyBase
{
    readonly float _anchorX, _anchorY;
    float _kx, _ky, _cool, _charge;
    bool _charging;

    public Sentry(Game game, float x, float y) : base(game, "sentry", x, y, 40, 40, 2)
    {
        Hover = true;
        _anchorX = x;
        _anchorY = y;
        _cool = U.Rnd(0.8f, 1.4f);
    }

    public override void Behavior(float dt)
    {
        var p = Game.Player;
        float bob = MathF.Sin(T * 1.7f) * 9;
        _kx *= MathF.Pow(0.002f, dt);
        _ky *= MathF.Pow(0.002f, dt);
        X = _anchorX + _kx;
        Y = _anchorY + bob + _ky;

        float dx = p.Cx - Cx;
        float dy = p.Cy - Cy;
        bool sees = !p.Dead && MathF.Sqrt(dx * dx + dy * dy) < 620;

        if (_charging)
        {
            _charge += dt;
            if (_charge >= 0.55f)
            {
                _charging = false;
                _charge = 0;
                _cool = 1.65f;
                Fire(dx, dy);
            }
        }
        else
        {
            _cool -= dt;
            if (_cool <= 0 && sees)
            {
                _charging = true;
                _charge = 0;
                Audio.Tone(new ToneOptions { Type = "sine", Freq = 280, Freq2 = 520, Dur = 0.5f, Gain = 0.035f });
            }
            if (_cool < -0.4f) _cool = 0.6f;
        }
    }

    void Fire(float dx, float dy)
    {
        float a = MathF.Atan2(dy, dx);
        const float speed = 345f;
        _kx -= MathF.Cos(a) * 14;
        _ky -= MathF.Sin(a) * 14;
        Game.Projectiles.Add(new InkBolt(Game, Cx + MathF.Cos(a) * 20, Cy + MathF.Sin(a) * 20,
            MathF.Cos(a) * speed, MathF.Sin(a) * speed));
        Fx.Sparks(Cx, Cy, a, 8, C.RedBright);
        Fx.Ring(Cx, Cy, 8, 36, C.Red, 0.3f, 2);
        Audio.Noise(new NoiseOptions { Freq = 1400, Freq2 = 300, Dur = 0.22f, Gain = 0.07f });
        Fx.AddShake(2);
    }

    public override void Hurt(float dmg, float dirX, bool heavy)
    {
        base.Hurt(dmg, dirX, heavy);
        if (!Dead)
        {
            _kx += dirX * 22;
            _ky -= 14;
            _charging = false;
            _charge = 0;
            _cool = MathF.Max(_cool, 0.7f);
        }
    }

    public override void Draw()
    {
        if (Dead) return;
        var p = Game.Player;
        bool flash = HurtT > 0 && (int)(HurtT * 50) % 2 == 0;
        var fill = flash ? C.Red : C.Cream;

        Ink.EllipseShadow(Cx, 618, 18, 4, 0.08f);

        for (int i = 0; i < 4; i++)
        {
            float ox = -15 + i * 10;
            float ph = T * 2.2f + i * 1.4f;
            Ink.Poly(new[]
            {
                new SKPoint(Cx + ox, Cy + 10),
                new SKPoint(Cx + ox + MathF.Sin(ph) * 8, Cy + 26),
                new SKPoint(Cx + ox + MathF.Sin(ph + 1) * 12, Cy + 40)
            }, 2f, C.Rgba(23, 19, 15, 140), 1f, 0.8f);
        }

        if (_charging)
        {
            float k = _charge / 0.55f;
            Ink.Save();
            Ink.Alpha = 0.3f + k * 0.5f;
            Ink.Arc(Cx, Cy, 26 + (1 - k) * 22, 0, U.TAU, 1.5f, C.Red, 1f, 0.6f);
            Ink.Restore();

            float ax = MathF.Atan2(p.Cy - Cy, p.Cx - Cx);
            Ink.Save();
            Ink.Alpha = 0.18f + k * 0.4f;
            Ink.Line(Cx + MathF.Cos(ax) * 22, Cy + MathF.Sin(ax) * 22, p.Cx, p.Cy,
                1.4f, C.Red, 1f, 0f, new[] { 4f, 9f });
            Ink.Restore();
        }

        Ink.Srand((long)_anchorX);
        Ink.Blob(Cx, Cy, 21, fill, C.Ink, 2.4f, 1f, 1.1f, 12, 0.1f);
        Ink.Hatch(CirclePts(Cx, Cy, 20, 14), 9, 0.09f);

        float ex = Cx + U.Clamp((p.Cx - Cx) * 0.06f, -5, 5);
        float ey = Cy + U.Clamp((p.Cy - Cy) * 0.06f, -4, 4);
        Ink.Blob(ex, ey, 10.5f, C.Cream, C.Ink, 1.8f, 1f, 0.5f, 10);
        Ink.Blob(ex, ey, 5.4f + _charge * 4, _charging ? C.RedBright : C.Red,
            outline: false, jitter: 0.3f);
        Ink.Blob(ex, ey, 2.2f, C.Ink, outline: false, jitter: 0.2f);
        Ink.Line(ex + 3, ey - 4, ex + 4, ey - 2, 1.4f, C.Cream);

        float tilt = _charging ? -3 : 0;
        Ink.Poly(new[]
        {
            new SKPoint(ex - 8, ey - 11 + tilt), new SKPoint(ex, ey - 13),
            new SKPoint(ex + 7, ey - 11 - tilt)
        }, 2f, C.Ink, 1f, 0.4f);

        if (U.Chance(0.02f))
            Fx.Sparks(Cx, Cy + 16, MathF.PI / 2, 1, C.InkSoft);

        DrawPips();
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
}

/* ---------- учебное чучело ---------- */

public sealed class Dummy : EnemyBase
{
    float _wobble, _wobbleV;
    public float Total;
    public int Hits;

    public Dummy(Game game, float x, float y) : base(game, "dummy", x, y, 44, 60, 999)
    {
        Contact = false;
    }

    public override void Behavior(float dt)
    {
        _wobbleV += -_wobble * 90 * dt;
        _wobbleV *= MathF.Pow(0.02f, dt);
        _wobble += _wobbleV * dt;
        _wobble = U.Clamp(_wobble, -0.5f, 0.5f);
    }

    public override void Hurt(float dmg, float dirX, bool heavy)
    {
        _wobbleV += dirX * 9;
        Total += dmg;
        Hits++;
        HurtT = 0.14f;
        Fx.Text(Cx + U.Rnd(-6, 6), Y - 4, ((int)dmg).ToString(), 22, C.Red, false, 0.7f);
        Fx.InkBurst(Cx + U.Rnd(-8, 8), Cy - 6, 5, 160f, size: 3f, gravity: 700f, floor: 618);
        Fx.Sparks(Cx, Cy - 8, dirX > 0 ? 0 : MathF.PI, 4, C.Gold);
        Audio.Hit(dmg > 1);
        Fx.AddShake(2);
        Game.AddCombo();
        Game.Freeze(0.035f);
    }

    public override void Draw()
    {
        Ink.EllipseShadow(Cx, 618, 24, 5, 0.18f);

        Ink.Save();
        Ink.Translate(Cx, 620);
        Ink.Rotate(_wobble * 0.12f * 180f / MathF.PI);
        bool flash = HurtT > 0;

        Ink.Rect(-20, -8, 40, 8, C.Rgba(120, 98, 64, 128), C.Ink, 1.8f, 1f, 0.7f);
        Ink.Rect(-4, -44, 8, 38, C.Rgba(190, 166, 120, 217), C.Ink, 1.6f, 1f, 0.6f);

        var body = new[]
        {
            new SKPoint(-17, -44), new SKPoint(-15, -58), new SKPoint(-5, -64),
            new SKPoint(9, -64), new SKPoint(18, -56), new SKPoint(19, -44),
            new SKPoint(12, -38), new SKPoint(-4, -38), new SKPoint(-14, -40)
        };
        Ink.Srand(515);
        Ink.FillPoly(body, flash ? C.Red : C.Bone, 1f, 1f);
        Ink.Poly(body, 2f, C.Ink, 1f, 1f, true);

        Ink.Circle(0, -51, 9, null, C.Red, 2f, 1f, 0.5f, 12);
        Ink.Circle(0, -51, 4.4f, C.Red, outline: false, jitter: 0.4f, n: 10);
        Ink.Line(-24, -51, -20, -51, 1.5f, C.Red);

        Ink.Blob(0, -71, 10, flash ? C.Red : C.Gold, C.Ink, 1.8f, 1f, 1f, 11);
        Ink.Line(-7, -78, -11, -84, 1.6f, C.Ink);
        Ink.Line(4, -81, 2, -88, 1.6f, C.Ink);
        Ink.Line(-3, -63, 3, -63, 1.4f, C.Ink, 0.5f);

        Ink.Line(-5, -74, -1, -70, 1.8f, C.Ink);
        Ink.Line(-5, -70, -1, -74, 1.8f, C.Ink);
        Ink.Line(2, -74, 6, -70, 1.8f, C.Ink);
        Ink.Line(2, -70, 6, -74, 1.8f, C.Ink);

        Ink.Restore();

        if (Hits > 0)
        {
            Ink.Text($"УРОН: {Total}", Cx, Y - 30, new TextOpt
            {
                Size = 14, Font = FontKind.Display, Align = InkAlign.Center,
                Color = C.Ink, Alpha = 0.45f, Spacing = 2
            });
        }
    }
}

/* ---------- снаряд ---------- */

public sealed class InkBolt
{
    public readonly Game Game;
    public readonly string Id;
    public float X, Y, Vx, Vy;
    public readonly float R = 11;
    public float Life = 3.6f;
    public bool Dead;
    public float T;
    readonly List<(float x, float y, float life)> _trail = new();

    public InkBolt(Game game, float x, float y, float vx, float vy)
    {
        Game = game;
        Id = "p" + (++EnemyBaseNext);
        X = x; Y = y; Vx = vx; Vy = vy;
    }

    static int EnemyBaseNext = 10000;

    public Rect Hitbox() => new(X - R, Y - R, R * 2, R * 2);

    public void Update(float dt)
    {
        T += dt;
        Life -= dt;
        _trail.Add((X, Y, 0.28f));
        if (_trail.Count > 12) _trail.RemoveAt(0);
        for (int i = 0; i < _trail.Count; i++)
            _trail[i] = (_trail[i].x, _trail[i].y, _trail[i].life - dt);

        X += Vx * dt;
        Y += Vy * dt;

        if (Life <= 0)
        {
            Kill(false);
            return;
        }
        var hb = Hitbox();
        foreach (var s in World.Solids)
        {
            if (U.Overlap(hb, s))
            {
                Kill(true);
                return;
            }
        }
        foreach (var s in World.Oneways)
        {
            if (U.Overlap(hb, s))
            {
                Kill(true);
                return;
            }
        }
        if (Y > 720 || Y < 0 || X < 0 || X > 1280) Kill(false);
    }

    public void Kill(bool splat)
    {
        if (Dead) return;
        Dead = true;
        if (splat)
        {
            Fx.InkBurst(X, Y, 7, 190f, new[] { C.Ink, C.RedDark }, 4f, floor: Y + 30);
            Audio.Noise(new NoiseOptions { Freq = 500, Dur = 0.1f, Gain = 0.04f, Type = "lowpass" });
        }
    }

    public void Deflect()
    {
        if (Dead) return;
        Fx.Sparks(X, Y, 0, 10, C.Cream);
        Fx.Ring(X, Y, 4, 30, C.Gold, 0.25f, 2);
        Fx.Text(X, Y - 10, "+", 18, C.Gold, false);
        Dead = true;
        Audio.Deflect();
    }

    public void Draw()
    {
        if (Dead) return;
        for (int i = 0; i < _trail.Count; i++)
        {
            var (x, y, life) = _trail[i];
            float k = MathF.Max(0, life / 0.28f);
            Ink.Save();
            Ink.Alpha = k * 0.5f;
            Ink.Srand(i + (long)X);
            Ink.Blob(x, y, R * k * 0.8f, C.Ink, outline: false, jitter: 0.8f);
            Ink.Restore();
        }
        Ink.Srand((long)X);
        Ink.Blob(X, Y, R, C.Ink, C.Ink, 1.5f, 1f, 1.2f, 10, 0.12f);
        Ink.Blob(X - 2, Y - 1, R * 0.45f, C.Red, outline: false, jitter: 0.5f);
        Ink.Blob(X + 3, Y - 4, 2.2f, C.Cream, outline: false, jitter: 0.2f);
    }
}
