using SkiaSharp;

namespace InkBlade;

public sealed class PlayerAttack
{
    public int Step;
    public string Dir = "fwd";
    public float T, Windup, Active, Recover, Reach, Dmg, Knock;
    public bool Spawned;
    public readonly HashSet<string> Hit = new();
}

public sealed class ScarfPoint
{
    public float X, Y, Px, Py;
}

public sealed class Player : Body
{
    public const float RunSpeed = 300f;
    const float Grav = 2520f, MaxFall = 1180f;
    const float AccG = 3300f, DecG = 3900f, AccA = 2200f, DecA = 1050f;
    const float JumpVel = 800f, CoyoteTime = 0.1f, JumpBuffer = 0.13f;
    const float DashSpeed = 870f, DashTime = 0.15f, DashCooldown = 0.34f;
    const float SoulMax = 99f, HealCost = 40f, HealTime = 0.8f;

    static readonly (float windup, float active, float recover, float reach, float dmg, float knock)[] Attacks =
    {
        default,
        (0.05f, 0.10f, 0.10f, 66f, 1f, 280f),
        (0.045f, 0.10f, 0.11f, 70f, 1f, 320f),
        (0.07f, 0.12f, 0.16f, 78f, 2f, 420f)
    };

    public readonly Game Game;
    public int Facing = 1;
    public float Coyote;
    public float JumpBuf;
    public float Hp = 5f, MaxHp = 5f, Soul;
    public float IFrames, HurtT;
    public bool Dead;
    public float DeathT;

    public bool DashActive;
    public float DashT, DashCd;
    public int DashDir = 1;
    public bool AirDash = true;

    public PlayerAttack? Attack;
    public float AttackCd;
    public bool AttackQueued;
    public int ComboStep;
    public float ComboTimer;

    public bool Healing;
    public float HealT, HealFxT;

    public float T, Squash = 1f, RunPhase, BlinkT = 2f, GhostT, LandedFx;

    public readonly List<ScarfPoint> Scarf = new();
    float _scarfAcc;

    public Player(Game game, float x, float y)
    {
        Game = game;
        X = x; Y = y; W = 28; H = 46;
        ResetScarf();
    }

    public Rect Hitbox() => new(X + 3, Y + 2, W - 6, H - 3);

    public bool IsInvuln() => Dead || IFrames > 0 || DashActive;

    public void GainSoul(float n) => Soul = MathF.Min(SoulMax, Soul + n);

    public void ResetScarf()
    {
        var neck = Neck();
        Scarf.Clear();
        for (int i = 0; i < 9; i++)
        {
            float x = neck.x - Facing * i * 4;
            Scarf.Add(new ScarfPoint { X = x, Y = neck.y, Px = x, Py = neck.y });
        }
    }

    public (float x, float y) Neck() => (Cx - Facing * 2, Y + 13);

    public void Update(float dt)
    {
        T += dt;
        IFrames = MathF.Max(0, IFrames - dt);
        HurtT = MathF.Max(0, HurtT - dt);
        AttackCd = MathF.Max(0, AttackCd - dt);
        DashCd = MathF.Max(0, DashCd - dt);
        DropT = MathF.Max(0, DropT - dt);
        JumpBuf = MathF.Max(0, JumpBuf - dt);
        ComboTimer = MathF.Max(0, ComboTimer - dt);
        if (ComboTimer <= 0) ComboStep = 0;
        BlinkT -= dt;
        if (BlinkT < -0.12f) BlinkT = U.Rnd(2, 5);
        Squash += (1 - Squash) * MathF.Min(1, dt * 17);
        LandedFx = MathF.Max(0, LandedFx - dt);

        if (Dead)
        {
            DeathT += dt;
            Vy = MathF.Min(Vy + Grav * dt, MaxFall);
            Y += Vy * dt;
            Vx *= 0.96f;
            X += Vx * dt;
            return;
        }

        if (Grounded) Coyote = CoyoteTime;
        else Coyote = MathF.Max(0, Coyote - dt);

        float ix = Input.AxisX();
        float iy = Input.AxisY();
        float move = MathF.Abs(ix) > 0.18f ? ix : 0f;
        bool jumpPressed = Input.Pressed(InputAction.Jump);
        bool attackPressed = Input.Pressed(InputAction.Attack);
        bool dashPressed = Input.Pressed(InputAction.Dash);
        bool healHeld = Input.Down(InputAction.Heal);

        /* --- лечение --- */
        if (Healing)
        {
            bool canHold = healHeld && Grounded && Soul >= HealCost && Hp < MaxHp;
            if (!canHold || attackPressed || dashPressed || HurtT > 0)
            {
                CancelHeal();
            }
            else
            {
                HealT += dt;
                Vx = U.Approach(Vx, 0, 3200 * dt);
                HealFxT -= dt;
                if (HealFxT <= 0)
                {
                    HealFxT = 0.13f;
                    float a = U.Rnd(0, U.TAU);
                    Fx.InkBurst(Cx + MathF.Cos(a) * 24, Cy + MathF.Sin(a) * 20, 1, 40f,
                        new[] { C.Red, C.Ink, C.Gold }, 2.6f, false, null,
                        -MathF.Cos(a) * 90, -MathF.Sin(a) * 90, -140f, 9999f);
                }
                if (HealT >= HealTime) FinishHeal();
            }
        }

        if (!Healing && healHeld && Grounded && Soul >= HealCost && Hp < MaxHp
            && Attack is null && !DashActive && HurtT <= 0)
        {
            Healing = true;
            HealT = 0;
            Vx = 0;
            Audio.HealLoop();
        }

        /* --- прыжок --- */
        if (!Healing && jumpPressed)
        {
            if (OnOneWay && iy > 0.4f)
            {
                DropT = 0.22f;
                Y += 3;
                Grounded = false;
                Coyote = 0;
                JumpBuf = 0;
                Fx.Dust(Cx, Y + H, 4, 0);
            }
            else JumpBuf = JumpBuffer;
        }

        if (JumpBuf > 0 && Coyote > 0 && !Healing)
        {
            Vy = -JumpVel;
            JumpBuf = 0;
            Coyote = 0;
            Grounded = false;
            Squash = 0.85f;
            Fx.Dust(Cx, Y + H, 5, 0);
            Audio.Jump();
        }

        /* --- рывок --- */
        if (dashPressed && DashCd <= 0 && !Healing && Attack is null && (Grounded || AirDash))
            StartDash(move);

        /* --- атака --- */
        if (attackPressed && !Healing && !DashActive)
        {
            if (Attack is null)
            {
                if (AttackCd <= 0) StartAttack(0, iy);
            }
            else if (Attack.T > Attack.Windup + Attack.Active * 0.35f) AttackQueued = true;
        }

        /* --- движение --- */
        float target = 0;
        if (!Healing && HurtT <= 0 && !DashActive)
        {
            target = move * RunSpeed;
            if (Attack is not null && Grounded) target *= 0.3f;
        }
        float accel = Grounded
            ? (MathF.Abs(target) > 1 ? AccG : DecG)
            : (MathF.Abs(target) > 1 ? AccA : DecA);
        Vx = U.Approach(Vx, target, accel * dt);

        if (move != 0 && Attack is null && !Healing && HurtT <= 0)
            Facing = U.Sign(move);

        /* --- таймеры атаки --- */
        if (Attack is not null)
        {
            Attack.T += dt;
            if (!Attack.Spawned && Attack.T >= Attack.Windup)
            {
                Attack.Spawned = true;
                SpawnSlash();
                Audio.Slash(Attack.Step);
            }
            float activeEnd = Attack.Windup + Attack.Active;
            float total = activeEnd + Attack.Recover;
            if (AttackQueued && Attack.T >= activeEnd && Attack.Step < 3)
                StartAttack(Attack.Step, iy, true);
            else if (Attack.T >= total)
            {
                Attack = null;
                AttackCd = 0.06f;
                AttackQueued = false;
            }
        }

        /* --- рывок --- */
        if (DashActive)
        {
            DashT -= dt;
            Vx = DashDir * DashSpeed;
            Vy = 0;
            GhostT -= dt;
            if (GhostT <= 0)
            {
                GhostT = 0.028f;
                Fx.GhostTrail(X, Y, W, H, Facing, 0.22f);
            }
            if (DashT <= 0)
            {
                DashActive = false;
                Vx *= 0.55f;
            }
        }

        /* --- гравитация --- */
        if (!DashActive)
        {
            float g = Grav;
            if (Vy < 0 && !Input.Down(InputAction.Jump)) g *= 2.15f;
            Vy = MathF.Min(Vy + g * dt, MaxFall);
        }

        /* --- коллизии --- */
        bool wasGrounded = Grounded;
        float fallSpeed = Vy;
        World.MoveX(this, dt);
        World.MoveY(this, dt);

        if (!wasGrounded && Grounded)
        {
            Squash = 0.82f;
            AirDash = true;
            LandedFx = 0.18f;
            if (fallSpeed > 350)
            {
                Fx.Dust(Cx, Y + H, 6, 0);
                Audio.Land(MathF.Min(1, fallSpeed / 900));
                Fx.AddShake(1.5f);
            }
        }

        if (Grounded && MathF.Abs(Vx) > 12 && Attack is null)
            RunPhase += MathF.Abs(Vx) * dt * 0.085f;

        if (Y > 780) Game.HazardTeleport();

        /* --- шарф --- */
        _scarfAcc += dt;
        while (_scarfAcc > 1f / 60f)
        {
            ScarfStep();
            _scarfAcc -= 1f / 60f;
        }
    }

    void ScarfStep()
    {
        var pts = Scarf;
        var neck = Neck();
        pts[0].X = neck.x; pts[0].Y = neck.y;
        pts[0].Px = neck.x; pts[0].Py = neck.y;

        float wind = -Facing * 26 - Vx * 0.16f + MathF.Sin(T * 2.6f) * 28;
        for (int i = 1; i < pts.Count; i++)
        {
            var p = pts[i];
            float vx = (p.X - p.Px) * 0.9f;
            float vy = (p.Y - p.Py) * 0.9f;
            p.Px = p.X; p.Py = p.Y;
            p.X += vx + wind * 0.018f;
            p.Y += vy + 0.34f;
        }
        for (int k = 0; k < 2; k++)
        {
            for (int i = 1; i < pts.Count; i++)
            {
                var a = pts[i - 1];
                var b = pts[i];
                float dx = b.X - a.X, dy = b.Y - a.Y;
                float d = MathF.Sqrt(dx * dx + dy * dy) + 0.001f;
                float diff = (d - 6.2f) / d;
                b.X -= dx * diff;
                b.Y -= dy * diff;
            }
        }
    }

    void StartDash(float move)
    {
        DashActive = true;
        DashT = DashTime;
        DashCd = DashCooldown;
        int dir = MathF.Abs(move) > 0.2f ? U.Sign(move) : Facing;
        DashDir = dir;
        Facing = dir;
        Vy = 0;
        Vx = dir * DashSpeed;
        if (!Grounded) AirDash = false;
        Attack = null;
        AttackQueued = false;
        Healing = false;
        HealT = 0;
        IFrames = MathF.Max(IFrames, 0.19f);
        GhostT = 0;
        Squash = 1.06f;
        Fx.Dust(Cx, Y + H - 2, 8, -dir);
        Fx.Ring(Cx, Cy, 6, 34, C.InkSoft, 0.28f, 2);
        Audio.Dash();
        Input.Rumble(0.15f, 0.35f, 90);
    }

    void StartAttack(int step, float iy, bool chain = false)
    {
        int nextStep;
        if (chain) nextStep = Math.Min(3, step + 1);
        else if (ComboTimer > 0 && ComboStep > 0 && ComboStep < 3) nextStep = ComboStep + 1;
        else nextStep = 1;

        var def = Attacks[nextStep];
        string dir = "fwd";
        if (iy < -0.45f) dir = "up";
        else if (!Grounded && iy > 0.45f) dir = "down";

        float ix = Input.AxisX();
        if (dir == "fwd" && MathF.Abs(ix) > 0.2f) Facing = U.Sign(ix);

        Attack = new PlayerAttack
        {
            Step = nextStep, Dir = dir, T = 0,
            Windup = def.windup, Active = def.active, Recover = def.recover,
            Reach = def.reach, Dmg = def.dmg, Knock = def.knock
        };
        AttackQueued = false;
        ComboStep = nextStep;
        ComboTimer = 0.55f;
        AttackCd = 0.04f;
        Healing = false;
        Squash = 1.03f;

        if (Grounded) Vx += Facing * 55;
        else Vx += Facing * 110;
    }

    void SpawnSlash()
    {
        var a = Attack;
        if (a is null) return;
        float cx = Cx, cy = Cy - 2;
        float a0, a1, ox = cx, oy = cy;
        float radius = 54 + a.Step * 3;
        if (a.Dir == "fwd")
        {
            if (Facing > 0) { a0 = -1.2f; a1 = 1.05f; }
            else { a0 = MathF.PI + 1.2f; a1 = MathF.PI - 1.05f; }
            ox = cx + Facing * 6;
        }
        else if (a.Dir == "up")
        {
            a0 = MathF.PI + 0.35f;
            a1 = MathF.PI * 2 - 0.35f;
            oy = cy - 18;
        }
        else
        {
            a0 = 0.35f;
            a1 = MathF.PI - 0.35f;
            oy = cy + 14;
        }

        Fx.Slash(ox, oy, a0, a1, radius, 20, 7, a.Active + 0.11f,
            a.Step == 3 ? C.RedBright : C.Red);
        Fx.Sparks(ox + MathF.Cos(a1) * radius * 0.6f, oy + MathF.Sin(a1) * radius * 0.6f,
            a1, 3, C.InkSoft);
    }

    public void DebugAttack(int step)
    {
        StartAttack(Math.Max(0, step - 1), 0, step > 1);
    }

    public void DebugKill()
    {
        Hp = 0;
        Die();
    }

    public bool AttackActive()
    {
        var a = Attack;
        return a is not null && a.T >= a.Windup && a.T <= a.Windup + a.Active;
    }

    public Rect? AttackHitbox()
    {
        var a = Attack;
        if (a is null) return null;
        if (a.Dir == "fwd")
            return new Rect(Facing > 0 ? Cx + 4 : Cx - 4 - a.Reach, Cy - 29, a.Reach, 58);
        if (a.Dir == "up")
            return new Rect(Cx - 27, Y - a.Reach + 10, 54, a.Reach);
        return new Rect(Cx - 27, Y + H - 12, 54, a.Reach);
    }

    public void Pogo()
    {
        Vy = -660;
        Grounded = false;
        Squash = 0.88f;
        AirDash = true;
        Fx.Ring(Cx, Y + H, 8, 44, C.Red, 0.3f, 2);
        Fx.Dust(Cx, Y + H, 6, 0);
    }

    void FinishHeal()
    {
        Hp = MathF.Min(MaxHp, Hp + 1);
        Soul -= HealCost;
        Healing = false;
        HealT = 0;
        Fx.Ring(Cx, Cy, 12, 60, C.Gold, 0.5f, 3);
        Fx.InkBurst(Cx, Cy, 10, 150f, new[] { C.Gold, C.Cream, C.Red }, 3.5f,
            false, null, 0, 0, -160f, 9999f);
        Fx.Text(Cx, Y - 12, "+1", 22, C.Red, false);
        Audio.Heal();
        Input.Rumble(0.3f, 0.5f, 160);
    }

    void CancelHeal()
    {
        if (!Healing) return;
        Healing = false;
        HealT = 0;
    }

    public bool Hurt(float dmg, float srcX)
    {
        if (IsInvuln()) return false;
        Hp -= dmg;
        IFrames = 1.1f;
        HurtT = 0.34f;
        Attack = null;
        AttackQueued = false;
        Healing = false;
        HealT = 0;
        DashActive = false;
        DashT = 0;

        int dir = U.Sign(Cx - srcX);
        if (MathF.Abs(Cx - srcX) < 1) dir = -Facing;
        Vx = dir * 330;
        Vy = -340;
        Grounded = false;
        Facing = -dir;

        Fx.InkBurst(Cx, Cy, 14, 300f, new[] { C.Red, C.RedDark, C.Ink }, 5f, true);
        Fx.Sparks(Cx, Cy, dir > 0 ? 0 : MathF.PI, 9, C.RedBright);
        Fx.AddShake(9);
        Fx.DamageScreen(1);
        Fx.FlashScreen(0.2f, C.Red);
        Fx.Text(Cx, Y - 10, $"-{(int)dmg}", 24, C.Red, false);
        Audio.Hurt();
        Input.Rumble(0.9f, 0.5f, 220);
        Game.Freeze(0.075f);

        if (Hp <= 0)
        {
            Hp = 0;
            Die();
        }
        return true;
    }

    void Die()
    {
        if (Dead) return;
        Dead = true;
        DeathT = 0;
        Vy = -420;
        Vx = -Facing * 90;
        Attack = null;
        Healing = false;
        DashActive = false;
        Fx.InkBurst(Cx, Cy, 34, 440f, new[] { C.Ink, C.Ink, C.Red, C.InkSoft }, 7f, true);
        Fx.Ring(Cx, Cy, 10, 140, C.Red, 0.7f, 4);
        Fx.AddShake(16, 0.02f);
        Fx.FlashScreen(0.35f, C.Red);
        Audio.Death();
        Input.Rumble(1f, 0.8f, 500);
    }

    public float ShadowY()
    {
        float best = 720;
        foreach (var s in World.Solids)
        {
            if (Cx < s.X || Cx > s.X + s.W) continue;
            if (s.Y >= Y + H - 4 && s.Y < best) best = s.Y;
        }
        foreach (var s in World.Oneways)
        {
            if (Cx < s.X || Cx > s.X + s.W) continue;
            if (s.Y >= Y + H - 4 && s.Y < best) best = s.Y;
        }
        return best;
    }

    public void Draw()
    {
        if (Dead) return;
        float gy = ShadowY();
        if (gy < 715)
        {
            float shadowAir = U.Clamp01((gy - (Y + H)) / 260f);
            Ink.EllipseShadow(Cx, gy - 2, 17 * (1 - shadowAir * 0.45f), 4.6f, 0.22f * (1 - shadowAir * 0.6f));
        }

        DrawScarf();

        bool flash = HurtT > 0 && (int)(HurtT * 34) % 2 == 0;
        var bodyFill = flash ? C.Red : C.Cream;
        float alpha = IFrames > 0 && HurtT <= 0 && !DashActive
            ? ((int)(T * 22) % 2 == 0 ? 0.55f : 1f)
            : 1f;

        Ink.Save();
        Ink.Alpha = alpha;
        Ink.Translate(Cx, Y + H);

        float sy = U.Clamp(Squash, 0.8f, 1.12f);
        float sx = 2 - sy;
        Ink.Scale(Facing * sx, sy);

        bool moving = Grounded && MathF.Abs(Vx) > 20;
        float walk = moving ? MathF.Sin(RunPhase) : 0;
        bool air = !Grounded;
        float bob = moving ? MathF.Abs(MathF.Sin(RunPhase)) * 1.2f : MathF.Sin(T * 2.2f) * 0.7f;

        /* ноги */
        const float legY = -14;
        float legSwing = walk * 4.5f;
        float footA = air ? -7 : -5 + legSwing;
        float footB = air ? 4 : 5 - legSwing;
        float kneeA = air ? -10 : -7 + legSwing * 0.5f;
        float kneeB = air ? -5 : -6 - legSwing * 0.5f;
        Ink.Poly(new[] { new SKPoint(-3, legY), new SKPoint(kneeA, -7), new SKPoint(footA, -1) },
            3.4f, C.Ink, 1f, 0.5f);
        Ink.Poly(new[] { new SKPoint(3, legY), new SKPoint(kneeB, -7), new SKPoint(footB, -1) },
            3.4f, C.Ink, 1f, 0.5f);
        Ink.Line(footA - 2, -1, footA + 3, -1, C.Ink, 2.6f, 1f, 0.3f);
        Ink.Line(footB - 2, -1, footB + 3, -1, C.Ink, 2.6f, 1f, 0.3f);

        /* плащ */
        float sway = U.Clamp(-Vx * 0.012f, -3.2f, 3.2f);
        float flap = MathF.Sin(T * 4.2f) * 1.3f;
        var cloak = new[]
        {
            new SKPoint(-11, -32 - bob), new SKPoint(8, -33 - bob), new SKPoint(12, -25),
            new SKPoint(13 + sway * 0.2f, -15 + sway * 0.4f), new SKPoint(12, -8 + flap * 0.4f),
            new SKPoint(8, -3), new SKPoint(6, -7 + flap), new SKPoint(3, -4),
            new SKPoint(-1, -8), new SKPoint(-5, -4), new SKPoint(-8, -8), new SKPoint(-12, -9),
            new SKPoint(-13, -19 + sway * 0.3f)
        };
        Ink.Srand(900);
        Ink.FillPoly(cloak, bodyFill, 1f, 0.9f);
        Ink.Poly(cloak, 2.2f, C.Ink, 1f, 0.9f, true);

        Ink.Poly(new[] { new SKPoint(-7, -29), new SKPoint(-8, -20), new SKPoint(-6, -12) },
            1.2f, C.Rgba(23, 19, 15, 89), 1f, 0.6f);
        Ink.Poly(new[] { new SKPoint(3, -30), new SKPoint(1, -20), new SKPoint(4, -12) },
            1.1f, C.Rgba(23, 19, 15, 64), 1f, 0.6f);
        Ink.Poly(new[] { new SKPoint(9, -27), new SKPoint(10, -19) },
            1f, C.Rgba(23, 19, 15, 51), 1f, 0.5f);

        /* пояс */
        Ink.Poly(new[] { new SKPoint(-10, -20), new SKPoint(11, -21) }, 3.2f, C.Red, 1f, 0.4f);
        Ink.Blob(9, -20.5f, 2.6f, C.Red, C.Ink, 1f, 1f, 0.4f);
        float sashSway = U.Clamp(-Vx * 0.02f, -5, 5);
        Ink.Poly(new[]
        {
            new SKPoint(10, -19), new SKPoint(12 + sashSway * 0.5f, -13),
            new SKPoint(10 + sashSway, -8)
        }, 2.2f, C.Red, 1f, 0.6f);

        /* рука и кисть-клинок */
        float ang = BladeAngle();
        const float hx = 8.5f;
        float hy = -24 - bob;
        float dx = MathF.Cos(ang), dy = MathF.Sin(ang);
        Ink.Poly(new[] { new SKPoint(6, -29 - bob), new SKPoint(hx - 1, hy) }, 3.6f, C.Ink, 1f, 0.5f);

        float bx = hx + dx * 13, by = hy + dy * 13;
        float ex = hx + dx * 37, ey = hy + dy * 37;
        Ink.Line(hx, hy, bx, by, C.Ink, 3.8f, 1f, 0.4f);
        Ink.Line(hx + dx * 4, hy + dy * 4, bx, by, C.Red, 1.3f, 1f, 0.3f);
        float nx = -dy, ny = dx;
        var bristle = new[]
        {
            new SKPoint(bx + nx * 5.4f, by + ny * 5.4f),
            new SKPoint(ex + nx * 1.1f, ey + ny * 1.1f),
            new SKPoint(ex - nx * 1.1f, ey - ny * 1.1f),
            new SKPoint(bx - nx * 5.4f, by - ny * 5.4f)
        };
        Ink.FillPoly(bristle, Attack is { Step: 3 } ? C.RedDark : C.Ink, 1f, 0.6f);
        Ink.Poly(bristle, 1f, C.Ink, 1f, 0.5f, true);
        Ink.Line(bx + nx * 3, by + ny * 3, bx - nx * 3, by - ny * 3, C.Red, 2.8f, 1f, 0.3f);

        /* голова */
        float hb = bob;
        var head = new[]
        {
            new SKPoint(-9, -35 - hb), new SKPoint(-8, -44 - hb), new SKPoint(-2, -49 - hb),
            new SKPoint(5, -49 - hb), new SKPoint(11, -44 - hb), new SKPoint(12, -36 - hb),
            new SKPoint(8, -31 - hb), new SKPoint(-3, -31 - hb)
        };
        Ink.Srand(901);
        Ink.FillPoly(head, bodyFill, 1f, 0.7f);
        Ink.Poly(head, 2.2f, C.Ink, 1f, 0.7f, true);

        float earW = MathF.Sin(T * 3.1f) * 1.4f;
        Ink.Poly(new[] { new SKPoint(-2, -47 - hb), new SKPoint(-5 + earW, -55 - hb), new SKPoint(-8 + earW, -61 - hb) },
            2.8f, C.Ink, 1f, 0.5f);
        Ink.Poly(new[] { new SKPoint(8, -47 - hb), new SKPoint(11 - earW, -54 - hb), new SKPoint(14 - earW, -59 - hb) },
            2.8f, C.Ink, 1f, 0.5f);
        Ink.Poly(new[] { new SKPoint(-6 + earW, -56 - hb), new SKPoint(-8 + earW, -61 - hb) }, 1.2f, C.Red, 1f, 0.4f);
        Ink.Poly(new[] { new SKPoint(12 - earW, -54 - hb), new SKPoint(14 - earW, -59 - hb) }, 1.2f, C.Red, 1f, 0.4f);

        bool blink = BlinkT < 0 || Healing;
        if (blink)
        {
            Ink.Line(2, -39 - hb, 7, -39 - hb, C.Ink, 1.6f, 1f, 0.3f);
            Ink.Line(8, -38 - hb, 11, -38 - hb, C.Ink, 1.5f, 1f, 0.3f);
        }
        else
        {
            Ink.Blob(5, -39.5f - hb, 2.4f, Healing ? C.Gold : C.RedBright, outline: false, jitter: 0.3f);
            Ink.Blob(10, -39 - hb, 1.9f, Healing ? C.Gold : C.RedBright, outline: false, jitter: 0.3f);
            Ink.Save();
            Ink.Alpha = 0.85f;
            Ink.Line(5.6f, -41.8f - hb, 5.6f, -41.8f - hb, C.Cream, 1f, 1f, 0.2f);
            Ink.Restore();
        }
        Ink.Poly(new[] { new SKPoint(-3, -32 - hb), new SKPoint(1, -30 - hb) }, 1.2f, C.Rgba(23, 19, 15, 102), 1f, 0.4f);

        Ink.Restore();

        /* аура лечения */
        if (Healing)
        {
            float k = U.Clamp01(HealT / HealTime);
            float pulse = 0.6f + MathF.Sin(T * 12) * 0.2f;
            Ink.Save();
            Ink.Alpha = 0.75f;
            Ink.Circle(Cx, Cy, 34 + MathF.Sin(T * 6) * 2, null, C.Gold, 1.4f, 1f, 0.7f, 16);
            Ink.Arc(Cx, Cy, 27, -MathF.PI / 2, -MathF.PI / 2 + U.TAU * k, 3.4f, C.Red, pulse, 0.6f);
            for (int i = 0; i < 3; i++)
            {
                float a = T * 1.8f + i / 3f * U.TAU;
                float r = 40 - (T * 20 + i * 8) % 30;
                Ink.Blob(Cx + MathF.Cos(a) * r, Cy + MathF.Sin(a) * r, 2.2f,
                    C.Ink, outline: false, jitter: 0.5f);
            }
            Ink.Restore();

            if (HealT > HealTime - 0.1f)
                Ink.FillCircleColor(Cx, Cy, 45, C.Cream, 0.25f);
        }
    }

    float BladeAngle()
    {
        float ang = 1.02f + MathF.Sin(T * 2.1f) * 0.04f;
        if (!Grounded) ang = 1.25f;
        if (DashActive) ang = 1.6f;
        if (Healing) ang = 1.85f;
        var a = Attack;
        if (a is null) return ang;
        float k;
        if (a.T < a.Windup) k = -0.18f * (a.T / MathF.Max(0.001f, a.Windup));
        else if (a.T < a.Windup + a.Active) k = U.EaseOutCubic((a.T - a.Windup) / a.Active);
        else k = 1f;
        if (a.Dir == "fwd") return U.Lerp(-1.35f, 1.35f, k);
        if (a.Dir == "up") return U.Lerp(2.1f, -2.55f, k);
        return U.Lerp(-2.0f, 2.0f, k);
    }

    void DrawScarf()
    {
        if (Scarf.Count < 3) return;
        float[] widths = { 5.4f, 5.3f, 4.8f, 4.2f, 3.6f, 3.0f, 2.4f, 1.9f, 1.4f };
        var left = new List<SKPoint>();
        var right = new List<SKPoint>();
        for (int i = 0; i < Scarf.Count; i++)
        {
            var prev = Scarf[Math.Max(0, i - 1)];
            var next = Scarf[Math.Min(Scarf.Count - 1, i + 1)];
            float dx = next.X - prev.X, dy = next.Y - prev.Y;
            float d = MathF.Sqrt(dx * dx + dy * dy) + 0.001f;
            dx /= d; dy /= d;
            float w = i < widths.Length ? widths[i] : 1.2f;
            left.Add(new SKPoint(Scarf[i].X - dy * w, Scarf[i].Y + dx * w));
            right.Add(new SKPoint(Scarf[i].X + dy * w, Scarf[i].Y - dx * w));
        }
        right.Reverse();
        left.AddRange(right);
        Ink.Srand(777);
        Ink.FillPoly(left, C.Rgba(150, 30, 37, 240), 1f, 0.7f);
        Ink.Poly(left, 1.2f, C.Rgba(23, 19, 15, 204), 1f, 0.7f, true);
        var tip = Scarf[^1];
        Ink.Blob(tip.X, tip.Y, 2.2f, C.RedDark, outline: false, jitter: 0.4f);
    }
}
