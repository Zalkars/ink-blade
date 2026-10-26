using SkiaSharp;

namespace InkBlade;

public sealed class BannerState
{
    public string Title = "";
    public string Sub = "";
    public float T;
    public float Max = 1;
}

public sealed class GameSettings
{
    public bool Shake = true;
    public bool Sound = true;
}

public sealed class Game
{
    public string State = "title";
    public float Clock, TitleT, TimeScale = 1, Hitstop;
    public Player Player = null!;
    public readonly List<EnemyBase> Enemies = new();
    public readonly List<InkBolt> Projectiles = new();

    public int Combo, MaxCombo, Kills, Hits, Deaths;
    public float ComboT, ComboPop, RunTime;
    public BannerState Banner = new();
    public float HintTimer, HintAlpha;
    public float DeathDelay, DeadT;
    public int MenuIndex;
    public string? Submenu;
    public readonly GameSettings Settings = new();
    public bool DebugHitboxes;
    public int Fps = 60;
    float _fpsAcc;
    int _fpsN;
    public bool TitleControls;
    public bool PausedFromTitle => State == "paused" && Player is null;

    SKBitmap? _titleBitmap;
    SKImage? _title;

    readonly string[] _menuItems = { "resume", "restart", "controls", "shake", "sound", "title" };

    public void Init()
    {
        World.Init();
        World.Bake();
        BakeTitle();
        Fx.Reset();
        NewRun();
        State = "title";
        TitleT = 0;
        Audio.Init();
    }

    public void NewRun()
    {
        Fx.Reset();
        Player = new Player(this, World.Spawn.X, World.Spawn.Y);
        Enemies.Clear();
        Enemies.Add(new Dummy(this, 610, 560));
        Enemies.Add(new Grunt(this, 1020, 584, -1, 860, 1200));
        Enemies.Add(new Grunt(this, 238, 432, 1, 160, 360));
        Enemies.Add(new Sentry(this, 760, 222));
        Projectiles.Clear();
        Combo = 0;
        ComboT = 0;
        ComboPop = 0;
        MaxCombo = 0;
        Kills = 0;
        Hits = 0;
        RunTime = 0;
        DeathDelay = 0;
        DeadT = 0;
        Hitstop = 0;
        TimeScale = 1;
        HintTimer = 0;
        HintAlpha = 0;
        Banner = new BannerState();
    }

    public void StartRun()
    {
        NewRun();
        State = "play";
        TitleControls = false;
        Banner = new BannerState
        {
            Title = "ЗАЛ ПЕРВОГО ВЗМАХА",
            Sub = "освой движение и клинок",
            T = 4.2f,
            Max = 4.2f
        };
        HintTimer = 18;
        HintAlpha = 1;
        Fx.FlashScreen(0.7f, C.Cream);
        Audio.Unlock();
        Audio.UiConfirm();
    }

    public void Freeze(float seconds) => Hitstop = MathF.Max(Hitstop, seconds);

    public void AddCombo()
    {
        Combo++;
        ComboT = 1.7f;
        ComboPop = 1;
        MaxCombo = Math.Max(MaxCombo, Combo);
    }

    public void OnEnemyKilled(EnemyBase e)
    {
        Kills++;
        Player.GainSoul(15);
        Fx.AddShake(2);
    }

    public void HazardTeleport()
    {
        var p = Player;
        if (p is null || p.Dead) return;
        bool damaged = p.Hurt(1, p.Cx + 1);
        p.X = World.Spawn.X;
        p.Y = World.Spawn.Y;
        p.Vx = 0;
        p.Vy = 0;
        p.Facing = 1;
        p.ResetScarf();
        Fx.InkBurst(p.Cx, p.Cy, 18, 280f, new[] { C.Ink, C.RedDark, C.InkSoft }, 6f, true);
        Fx.Ring(p.Cx, p.Cy, 6, 100, C.Ink, 0.5f, 3);
        if (damaged) Fx.DamageScreen(0.8f);
    }

    /* ---------- цикл ---------- */

    public void Frame(float dtReal)
    {
        float dt = MathF.Min(dtReal, 0.05f);
        Clock += dt;
        Ink.BeginFrame(Clock);

        _fpsAcc += dt;
        _fpsN++;
        if (_fpsAcc > 0.5f)
        {
            Fps = (int)MathF.Round(_fpsN / _fpsAcc);
            _fpsAcc = 0;
            _fpsN = 0;
        }

        HandleGlobal();

        if (State == "play")
        {
            float scale = TimeScale;
            if (Hitstop > 0)
            {
                Hitstop = MathF.Max(0, Hitstop - dt);
                scale *= 0.06f;
            }
            float sim = dt * scale;
            int guard = 0;
            while (sim > 0.0001f && guard < 10)
            {
                float stepDt = MathF.Min(sim, 1f / 120f);
                Step(stepDt);
                sim -= stepDt;
                guard++;
                if (State != "play") break;
            }
        }
        else if (State == "title")
        {
            UpdateTitle(dt);
        }
        else if (State == "paused")
        {
            UpdatePause(dt);
            Fx.Update(dt * 0.25f);
        }
        else if (State == "dead")
        {
            UpdateDead(dt);
            Fx.Update(dt * 0.5f);
        }
    }

    void HandleGlobal()
    {
        if (Input.Pressed(InputAction.Mute))
        {
            Settings.Sound = !Settings.Sound;
            Audio.SetMuted(!Settings.Sound);
            Audio.Ui();
        }
        if (Input.Pressed(InputAction.Hitboxes))
        {
            DebugHitboxes = !DebugHitboxes;
            Audio.Ui();
        }
        if (Input.Pressed(InputAction.Help))
        {
            if (State == "play")
            {
                OpenPause("controls");
            }
            else if (State == "paused")
            {
                Submenu = Submenu == "controls" ? null : "controls";
                MenuIndex = 0;
                Audio.Ui();
            }
            else if (State == "title")
            {
                TitleControls = !TitleControls;
                Audio.Ui();
            }
        }

        if (State == "play" && Input.Pressed(InputAction.Pause)) OpenPause(null);
        else if (State == "play" && Input.Pressed(InputAction.Restart)) StartRun();
    }

    void Step(float dt)
    {
        RunTime += dt;
        Player.Update(dt);
        foreach (var e in Enemies) e.Update(dt);
        foreach (var pr in Projectiles) pr.Update(dt);
        Projectiles.RemoveAll(p => p.Dead);

        Combat();

        Fx.Update(dt);

        if (ComboT > 0)
        {
            ComboT -= dt;
            if (ComboT <= 0) Combo = 0;
        }
        ComboPop = MathF.Max(0, ComboPop - dt * 5);
        if (Banner.T > 0) Banner.T = MathF.Max(0, Banner.T - dt);
        if (HintTimer > 0) HintTimer = MathF.Max(0, HintTimer - dt);
        HintAlpha = U.Clamp01(HintTimer / 2.4f);

        if (!Player.Dead && World.InHazard(Player)) HazardTeleport();

        if (Player.Dead)
        {
            DeathDelay += dt;
            if (DeathDelay > 1.1f)
            {
                State = "dead";
                Deaths++;
            }
        }
    }

    void Combat()
    {
        var p = Player;
        if (p is null || p.Dead) return;

        var atk = p.Attack;
        if (atk is not null && p.AttackActive())
        {
            var hb = p.AttackHitbox();
            if (hb is { } box)
            {
                foreach (var e in Enemies)
                {
                    if (e.Dead || atk.Hit.Contains(e.Id)) continue;
                    if (!U.Overlap(box, e.Hitbox())) continue;
                    atk.Hit.Add(e.Id);
                    int dir = U.Sign(e.Cx - p.Cx);
                    if (dir == 0) dir = p.Facing;
                    e.Hurt(atk.Dmg, dir, atk.Step == 3);
                    p.GainSoul(12);
                    Hits++;
                    float hx = U.Clamp(e.Cx, box.X + 4, box.X + box.W - 4);
                    float hy = U.Clamp(e.Cy, box.Y + 4, box.Y + box.H - 4);
                    Fx.Sparks(hx, hy, p.Facing > 0 ? -0.5f : MathF.PI + 0.5f, 5, C.Cream);
                    if (atk.Dir == "down") p.Pogo();
                }
                foreach (var pr in Projectiles)
                {
                    if (pr.Dead || atk.Hit.Contains(pr.Id)) continue;
                    if (!U.Overlap(box, pr.Hitbox())) continue;
                    atk.Hit.Add(pr.Id);
                    pr.Deflect();
                    p.GainSoul(8);
                    AddCombo();
                }
            }
        }

        if (p.IsInvuln()) return;

        var phb = p.Hitbox();
        foreach (var e in Enemies)
        {
            if (e.Dead || !e.Contact) continue;
            if (!U.Overlap(phb, e.Hitbox())) continue;
            if (p.Hurt(1, e.Cx))
                Fx.Sparks(p.Cx, p.Cy, p.Facing > 0 ? 0 : MathF.PI, 6, C.RedBright);
            break;
        }

        if (p.IsInvuln()) return;
        foreach (var pr in Projectiles)
        {
            if (pr.Dead) continue;
            if (!U.Overlap(phb, pr.Hitbox())) continue;
            p.Hurt(1, pr.X);
            pr.Kill(true);
            break;
        }
    }

    /* ---------- пауза ---------- */

    void OpenPause(string? sub)
    {
        if (State != "play") return;
        State = "paused";
        Submenu = sub;
        MenuIndex = 0;
        Audio.Ui();
    }

    void ClosePause()
    {
        State = "play";
        Submenu = null;
        HintTimer = MathF.Max(HintTimer, 3);
        Audio.UiConfirm();
    }

    void UpdatePause(float dt)
    {
        if (Submenu == "controls")
        {
            if (Input.Pressed(InputAction.Pause) || Input.Pressed(InputAction.Help))
            {
                Submenu = null;
                MenuIndex = 0;
                Audio.Ui();
            }
            return;
        }

        if (Input.Pressed(InputAction.Pause))
        {
            ClosePause();
            return;
        }
        int n = _menuItems.Length;
        if (Input.Pressed(InputAction.Up))
        {
            MenuIndex = (MenuIndex - 1 + n) % n;
            Audio.Ui();
        }
        if (Input.Pressed(InputAction.Down))
        {
            MenuIndex = (MenuIndex + 1) % n;
            Audio.Ui();
        }
        if (Input.Confirm()) ActivateMenu();
    }

    void ActivateMenu()
    {
        string item = _menuItems[MenuIndex];
        Audio.UiConfirm();
        if (item == "resume")
        {
            ClosePause();
        }
        else if (item == "restart")
        {
            StartRun();
        }
        else if (item == "controls")
        {
            Submenu = "controls";
        }
        else if (item == "shake")
        {
            Settings.Shake = !Settings.Shake;
        }
        else if (item == "sound")
        {
            Settings.Sound = !Settings.Sound;
            Audio.SetMuted(!Settings.Sound);
        }
        else if (item == "title")
        {
            State = "title";
            TitleT = 0;
            Submenu = null;
            Fx.Reset();
            NewRun();
        }
    }

    void UpdateTitle(float dt)
    {
        TitleT += dt;
        if (TitleControls)
        {
            if (Input.Pressed(InputAction.Pause) || Input.Pressed(InputAction.Help))
            {
                TitleControls = false;
                Audio.Ui();
            }
            return;
        }
        if (TitleT < 0.65f) return;
        if (Input.Confirm() || Input.Pressed(InputAction.Pause)
            || Input.Pressed(InputAction.Restart) || Input.Pressed(InputAction.Jump))
            StartRun();
    }

    void UpdateDead(float dt)
    {
        DeadT += dt;
        if (DeadT < 0.55f) return;
        if (Input.Confirm() || Input.Pressed(InputAction.Restart) || Input.Pressed(InputAction.Pause))
        {
            if (Input.Pressed(InputAction.Pause))
            {
                State = "title";
                TitleT = 0;
                NewRun();
                return;
            }
            StartRun();
        }
    }

    /* ---------- отрисовка ---------- */

    public void Render()
    {
        if (State == "title")
        {
            RenderTitle();
            if (TitleControls) RenderTitleControlsOverlay();
        }
        else if (State == "paused")
        {
            RenderWorld();
            RenderPause();
        }
        else if (State == "dead")
        {
            RenderWorld();
            RenderDeath();
        }
        else
        {
            RenderWorld();
            Hud.Draw(this);
            if (DeathDelay > 0 && Player.Dead) RenderDeathFade();
            if (DebugHitboxes) RenderDebug();
        }

        if (DebugHitboxes)
            Ink.Text($"{Fps} FPS · {State} · {Input.Device}", 1240, 700, new TextOpt
            {
                Size = 10, Font = FontKind.Body, Align = InkAlign.Right, Color = C.Ink, Alpha = 0.5f
            });
    }

    void RenderWorld()
    {
        var shake = Settings.Shake ? Fx.ShakeOffset() : (x: 0f, y: 0f, rot: 0f);
        Ink.Save();
        Ink.Translate(640 + shake.x, 360 + shake.y);
        if (shake.rot != 0) Ink.Rotate(shake.rot * 180f / MathF.PI);
        Ink.Scale(1.015f, 1.015f);
        Ink.Translate(-640, -360);

        World.DrawStage();
        Fx.DrawBehind();
        foreach (var e in Enemies) e.Draw();
        foreach (var p in Projectiles) p.Draw();
        Player.Draw();
        Fx.DrawFront();
        Ink.Restore();
        Fx.DrawScreen(1280, 720);
    }

    /* ---------- титульный экран ---------- */

    void BakeTitle()
    {
        _titleBitmap = new SKBitmap(new SKImageInfo(1280, 720, SKColorType.Bgra8888, SKAlphaType.Opaque));
        using (var c = new SKCanvas(_titleBitmap))
        {
            c.Clear(C.Paper);
            Ink.DrawPaper(c, new SKRect(0, 0, 1280, 720));
            Ink.SetCanvas(c);
            RenderTitleScene(0);
            Ink.Vignette();
        }
        _title = SKImage.FromBitmap(_titleBitmap);
    }

    void RenderTitle()
    {
        if (_title is null)
        {
            Ink.Paper();
            RenderTitleScene(TitleT);
            TitleBirds(TitleT);
            DrawTitlePrompt(TitleT);
            Ink.Vignette();
            return;
        }

        using (var paint = new SKPaint { IsAntialias = false })
            Ink.Cv?.DrawImage(_title, new SKRect(0, 0, 1280, 720), paint);
        TitleBirds(TitleT);
        DrawTitlePrompt(TitleT);
    }

    void RenderTitleScene(float t)
    {
        /* солнце */
        const float sx = 946, sy = 236, sr = 124;
        var sunPts = new List<SKPoint>();
        for (int i = 0; i < 30; i++)
        {
            float a = (float)i / 30 * U.TAU;
            sunPts.Add(new SKPoint(sx + MathF.Cos(a) * sr, sy + MathF.Sin(a) * sr));
        }
        Ink.Srand(501);
        Ink.FillPoly(sunPts, C.Rgba(156, 33, 41, 230), 1f, 2.2f);
        Ink.Hatch(sunPts, 11, 0.12f, C.Ink);
        Ink.Circle(sx, sy, sr, null, C.Rgba(23, 19, 15, 140), 2f, 1f, 2f, 30);

        TitleMountains();
        TitleFigure(950, 622, t);

        Ink.Srand(503);
        Ink.Blob(1130, 640, 34, C.Rgba(23, 19, 15, 41), outline: false, jitter: 2f);
        Ink.Blob(1164, 662, 12, C.Rgba(23, 19, 15, 46), outline: false, jitter: 1f);
        Ink.Blob(1084, 670, 7, C.Rgba(23, 19, 15, 36), outline: false, jitter: 1f);

        Ink.Srand(502);
        Ink.Text("ЧЕРНИЛЬНЫЙ", 96, 238, new TextOpt
        {
            Size = 62, Font = FontKind.Title, Color = C.Ink, Ghost = 2, Spacing = 2
        });
        Ink.Text("КЛИНОК", 92, 344, new TextOpt
        {
            Size = 108, Font = FontKind.Title, Color = C.Ink, Ghost = 3, Spacing = 4
        });
        Ink.Line(100, 364, 610, 364, C.Red, 5f, 1f, 2.2f);
        Ink.Line(104, 370, 560, 370, C.Rgba(23, 19, 15, 77), 1.5f, 1f, 1.4f);
        Ink.Text("ТРЕНИРОВОЧНАЯ ЗАЛА · ПРОТОТИП", 102, 400, new TextOpt
        {
            Size = 14, Font = FontKind.Display, Color = C.Ink, Alpha = 0.6f, Spacing = 4
        });
        Ink.Text("F1 — управление   ·   M — звук", 102, 452, new TextOpt
        {
            Size = 15, Font = FontKind.Hand, Color = C.Ink, Alpha = 0.55f
        });

        Ink.Text("v 0.1 · прототип", 1240, 700, new TextOpt
        {
            Size = 11, Font = FontKind.Hand, Align = InkAlign.Right, Color = C.Cream, Alpha = 0.55f
        });
    }

    void DrawTitlePrompt(float t)
    {
        float pulse = 0.62f + MathF.Sin(t * 3.1f) * 0.28f;
        const float bx = 420, by = 636;
        Ink.Rect(bx, by, 440, 48, C.Rgba(246, 237, 218, 235), C.Rgba(23, 19, 15, 166), 1.6f, 1f, 1f);
        Ink.Rect(bx + 5, by + 5, 430, 38, null, C.Rgba(23, 19, 15, 31), 1f, 1f, 0.6f);
        Ink.Line(bx + 18, by + 11, bx + 18, by + 37, C.Red, 3f, 0.9f, 0.8f);
        Ink.Text("НАЖМИ ПРОБЕЛ ИЛИ  A", 640, by + 31, new TextOpt
        {
            Size = 19, Font = FontKind.Display, Align = InkAlign.Center,
            Color = C.Ink, Alpha = pulse, Spacing = 3
        });
    }

    void TitleBirds(float t)
    {
        var birds = new[] { (742f, 142f, 0.9f, 0f), (806f, 108f, 0.7f, 1.4f), (862f, 168f, 0.55f, 2.6f) };
        Ink.Srand(520);
        foreach (var b in birds)
        {
            float flap = MathF.Sin(t * 2.2f + b.Item4) * 5;
            Ink.Poly(new[]
            {
                new SKPoint(b.Item1 - 12, b.Item2 + flap), new SKPoint(b.Item1, b.Item2),
                new SKPoint(b.Item1 + 12, b.Item2 + flap)
            }, 1.8f * b.Item3, C.Rgba(23, 19, 15, 140), 1f, 0.6f);
        }
    }

    void TitleMountains()
    {
        Ink.Srand(530);

        var far = Pts(
            (0, 600), (120, 538), (210, 572), (318, 498), (420, 556), (512, 514),
            (620, 574), (742, 522), (860, 566), (980, 508), (1104, 560), (1190, 522),
            (1280, 580), (1280, 720), (0, 720));
        Ink.FillPoly(far, C.Rgba(23, 19, 15, 41), 1f, 2f);
        Ink.Poly(far, 1.2f, C.Rgba(23, 19, 15, 46), 1f, 1.15f, true);

        var mid = Pts(
            (0, 652), (110, 606), (224, 638), (330, 590), (452, 646), (560, 602),
            (690, 650), (804, 604), (930, 648), (1040, 608), (1160, 652), (1280, 616),
            (1280, 720), (0, 720));
        Ink.FillPoly(mid, C.Rgba(23, 19, 15, 107), 1f, 2f);
        Ink.Hatch(mid, 15, 0.1f, C.Cream);

        var near = Pts(
            (0, 690), (140, 656), (250, 682), (360, 640), (480, 686), (600, 654),
            (738, 692), (862, 650), (986, 686), (1102, 646), (1210, 682), (1280, 660),
            (1280, 720), (0, 720));
        Ink.FillPoly(near, C.Rgba(23, 19, 15, 224), 1f, 2f);
        Ink.Hatch(near, 13, 0.09f, C.Cream, 1f, true);

        for (int i = 0; i < 9; i++)
        {
            float x = 60 + i * 146 + (i % 3) * 20;
            float y = 640 + (i % 2) * 18;
            Ink.Poly(new[]
            {
                new SKPoint(x, y - 46), new SKPoint(x - 11, y), new SKPoint(x + 11, y)
            }, 1.4f, C.Rgba(23, 19, 15, 191));
            Ink.Line(x, y, x, y + 8, 2f, C.Rgba(23, 19, 15, 179));
        }

        float blink = 0.5f + MathF.Sin(TitleT * 1.7f) * 0.3f;
        Ink.Save();
        Ink.Alpha = 0.55f * blink;
        Ink.Circle(312, 668, 2.6f, C.RedBright, outline: false, jitter: 0.3f);
        Ink.Circle(324, 668, 2.6f, C.RedBright, outline: false, jitter: 0.3f);
        Ink.Restore();
    }

    static List<SKPoint> Pts(params (float x, float y)[] pts)
    {
        var list = new List<SKPoint>(pts.Length);
        foreach (var p in pts) list.Add(new SKPoint(p.x, p.y));
        return list;
    }

    void TitleFigure(float x, float groundY, float t)
    {
        Ink.Save();
        Ink.Translate(x, groundY);
        Ink.Scale(1.9f, 1.9f);

        Ink.Srand(540);
        Ink.FillPoly(Pts((-46, 0), (-34, -10), (-12, -13), (12, -8), (34, -12), (48, 0)),
            C.Rgba(23, 19, 15, 230), 1f, 1.5f);

        float wave = MathF.Sin(t * 2.2f) * 4;
        Ink.Poly(Pts((-4, -31), (-24, -35 + wave), (-42, -27 + wave * 1.4f), (-56, -32 + wave)),
            3.2f, C.Red, 1f, 0.8f);
        Ink.Poly(Pts((-6, -28), (-26, -25 + wave * 0.6f), (-40, -18 + wave)),
            1.8f, C.RedDark, 1f, 0.8f);

        var cloak = Pts((-12, -32), (9, -33), (13, -24), (15, -8), (11, -1),
            (4, -5), (-2, -2), (-8, -6), (-14, -11));
        Ink.Srand(541);
        Ink.FillPoly(cloak, C.Rgba(20, 17, 14, 247), 1f, 1.2f);
        Ink.Poly(cloak, 1f, C.Rgba(246, 237, 218, 56), 1f, 1f, true);

        var head = Pts((-9, -35), (-8, -44), (-1, -49), (6, -48), (12, -43),
            (12, -34), (6, -30), (-3, -31));
        Ink.FillPoly(head, C.Rgba(20, 17, 14, 250), 1f, 0.9f);
        Ink.Poly(head, 1f, C.Rgba(246, 237, 218, 56), 1f, 0.8f, true);
        Ink.Poly(Pts((-2, -47), (-6, -56), (-9, -62)), 2.4f, C.Rgba(20, 17, 14, 250), 1f, 0.4f);
        Ink.Poly(Pts((8, -47), (11, -55), (14, -60)), 2.4f, C.Rgba(20, 17, 14, 250), 1f, 0.4f);
        Ink.Blob(6, -39, 1.9f, C.RedBright, outline: false, jitter: 0.2f);

        Ink.Line(10, -25, 23, -9, 3f, C.Rgba(20, 17, 14, 250));
        Ink.Line(22, -10, 31, 1, 4.6f, C.Rgba(20, 17, 14, 250));
        Ink.Line(19, -13, 24, -8, 1.4f, C.Red);

        Ink.Alpha = 0.25f;
        Ink.Poly(Pts((-12, -32), (-14, -11), (-8, -6)), 1.4f, C.Cream);
        Ink.Alpha = 1f;
        Ink.EllipseShadow(0, 2, 34, 6, 0.22f);
        Ink.Restore();
    }

    void RenderTitleControlsOverlay()
    {
        Ink.FillRectColor(0, 0, 1280, 720, C.Paper, 0.82f);
        RenderControls();
    }

    /* ---------- пауза ---------- */

    void RenderPause()
    {
        Ink.Save();
        Ink.Alpha = 0.72f;
        Ink.FillRectColor(0, 0, 1280, 720, C.Paper);
        Ink.Restore();

        Ink.RadialRect(0, 0, 1280, 720, 640, 340, 760, new[]
        {
            (0f, C.Rgba(60, 10, 14, 0)),
            (1f, C.Rgba(39, 8, 11, 87))
        });

        if (Submenu == "controls")
        {
            RenderControls();
            return;
        }

        const float x = 400, y = 108, w = 480, h = 474;
        Hud.Panel(x, y, w, h, "ПАУЗА", 30);

        Ink.Text($"ВРЕМЯ {U.FmtTime(RunTime)}   ·   УБИЙСТВ {Kills}   ·   СЕРИЯ {MaxCombo}",
            x + w / 2, y + 82, new TextOpt
            {
                Size = 11, Font = FontKind.Display, Align = InkAlign.Center,
                Color = C.Ink, Alpha = 0.42f, Spacing = 1
            });

        string[] labels =
        {
            "ПРОДОЛЖИТЬ",
            "НАЧАТЬ ЗАНОВО",
            "УПРАВЛЕНИЕ",
            $"ТРЯСКА ЭКРАНА: {(Settings.Shake ? "ВКЛ" : "ВЫКЛ")}",
            $"ЗВУК: {(Settings.Sound ? "ВКЛ" : "ВЫКЛ")}",
            "ВЫЙТИ В МЕНЮ"
        };

        float iy = y + 132;
        for (int i = 0; i < _menuItems.Length; i++)
        {
            string id = _menuItems[i];
            bool sel = i == MenuIndex;
            if (sel)
            {
                Ink.Srand(600 + i);
                Ink.FillPoly(Pts((x + 34, iy - 14), (x + 40, iy + 14), (x + w - 34, iy + 11),
                    (x + w - 40, iy - 12)), C.Rgba(156, 33, 41, 31), 1f, 0.8f);
                Ink.FillPoly(Pts((x + 44, iy - 7), (x + 56, iy), (x + 44, iy + 7), (x + 49, iy)),
                    C.Red, 1f, 0.5f);
            }
            Ink.Text(labels[i], x + 62, iy + 7, new TextOpt
            {
                Size = sel ? 21 : 20, Font = FontKind.Body,
                Color = sel ? C.Red : C.Ink, Alpha = sel ? 1f : 0.72f
            });
            if (id == "controls")
                Ink.Text("›", x + w - 56, iy + 6, new TextOpt
                {
                    Size = 24, Font = FontKind.Body, Color = C.Ink, Alpha = sel ? 0.7f : 0.3f
                });
            if (id == "shake" || id == "sound")
            {
                bool on = id == "shake" ? Settings.Shake : Settings.Sound;
                Ink.Line(x + w - 52, iy + 2, x + w - 34, iy + 2, 1.5f, C.Rgba(23, 19, 15, 64));
                Ink.Circle(x + w - 34, iy + 2, on ? 3.4f : 2.2f,
                    on ? C.Red : null, C.Red, 1.2f, 1f, 0.3f);
            }
            iy += 44;
        }

        Ink.Line(x + 30, y + h - 58, x + w - 30, y + h - 58, C.Rgba(23, 19, 15, 46), 1f, 1f, 0.8f);
        string hint = Input.Device == "gamepad"
            ? "СТИК — выбор      A — выбрать      START — назад"
            : "↑ ↓ — выбор      ПРОБЕЛ — выбрать      ESC — назад";
        Ink.Text(hint, x + w / 2, y + h - 32, new TextOpt
        {
            Size = 12, Font = FontKind.Hand, Align = InkAlign.Center, Color = C.Ink, Alpha = 0.62f
        });
    }

    void RenderControls()
    {
        const float x = 170, y = 40, w = 940, h = 636;
        Hud.Panel(x, y, w, h, "УПРАВЛЕНИЕ", 28);

        /* заголовки колонок */
        Ink.Text("ДЕЙСТВИЕ", x + 52, y + 96, new TextOpt
        {
            Size = 10, Font = FontKind.Display, Color = C.Ink, Alpha = 0.55f, Spacing = 3
        });
        Ink.Text("КЛАВИАТУРА", x + 420, y + 96, new TextOpt
        {
            Size = 10, Font = FontKind.Display, Color = C.Ink, Alpha = 0.55f, Spacing = 3
        });
        Ink.Text("ГЕЙМПАД", x + 590, y + 96, new TextOpt
        {
            Size = 10, Font = FontKind.Display, Color = C.Ink, Alpha = 0.55f, Spacing = 3
        });

        var rows = new (string action, string kb, string pad)[]
        {
            ("ДВИЖЕНИЕ", "A / D", "СТИК"),
            ("ПРЫЖОК", "ПРОБЕЛ / Z", "A"),
            ("АТАКА", "J / X", "X / RB"),
            ("РЫВОК", "K / SHIFT", "B / LB"),
            ("ЛЕЧЕНИЕ (ДЕРЖАТЬ)", "L / V", "Y"),
            ("ПАУЗА", "ESC / ENTER", "START"),
            ("ЗАНОВО", "R", "BACK"),
            ("ХИТБОКСЫ", "F2", "—")
        };

        float ry = y + 126;
        for (int i = 0; i < rows.Length; i++)
        {
            var r = rows[i];
            if (i % 2 == 0)
                Ink.Rect(x + 28, ry - 14, w - 56, 32, C.Rgba(23, 19, 15, 9),
                    C.Rgba(23, 19, 15, 13), 0.5f, 1f, 0.5f);
            Ink.Text(r.action, x + 52, ry + 6, new TextOpt
            {
                Size = 15, Font = FontKind.Body, Color = C.Ink, Alpha = 0.85f
            });
            if (r.kb != "—")
                Hud.Glyph(x + 420, ry, r.kb, false, 22, 10, 7);
            else
                Ink.Text("—", x + 420, ry + 6, new TextOpt
                {
                    Size = 14, Font = FontKind.Body, Color = C.Ink, Alpha = 0.3f
                });
            if (r.pad != "—")
                Hud.Glyph(x + 590, ry, r.pad, false, 22, 10, 7);
            else
                Ink.Text("—", x + 590, ry + 6, new TextOpt
                {
                    Size = 14, Font = FontKind.Body, Color = C.Ink, Alpha = 0.3f
                });
            ry += 33;
        }

        /* правая колонка: проверка ввода */
        Ink.Line(x + 690, y + 88, x + 690, y + 424, C.Rgba(23, 19, 15, 31), 1f, 1f, 0.8f);
        Ink.Text("ПРОВЕРКА ВВОДА", x + 720, y + 118, new TextOpt
        {
            Size = 10, Font = FontKind.Display, Color = C.Ink, Alpha = 0.55f, Spacing = 3
        });

        var snap = Input.Snapshot();
        string[] btnLabels = { "A", "B", "X", "Y", "LB", "RB", "LT", "RT", "⌗", "▶" };
        for (int i = 0; i < btnLabels.Length; i++)
        {
            int col = i % 5;
            int row = i / 5;
            float bx = x + 748 + col * 42;
            float by = y + 156 + row * 40;
            bool on = i < snap.Buttons.Length && snap.Buttons[i];
            Ink.Srand(700 + i);
            Ink.Circle(bx, by, 12, on ? C.Red : C.Rgba(246, 237, 218, 153),
                on ? C.RedDark : C.Rgba(23, 19, 15, 89), 1.4f, 1f, 0.6f, 10);
            Ink.Text(btnLabels[i], bx, by + 1, new TextOpt
            {
                Size = 9, Font = FontKind.Bold, Align = InkAlign.Center,
                Baseline = InkBaseline.Middle,
                Color = on ? C.Cream : C.Rgba(23, 19, 15, 140)
            });
        }

        const float sx = 960, sy = 282;
        Ink.Rect(sx - 34, sy - 26, 68, 52, C.Rgba(23, 19, 15, 8),
            C.Rgba(23, 19, 15, 56), 1.1f, 1f, 0.6f);
        Ink.Line(sx - 28, sy, sx + 28, sy, 1f, C.Rgba(23, 19, 15, 46));
        Ink.Line(sx, sy - 20, sx, sy + 20, 1f, C.Rgba(23, 19, 15, 46));
        float ax = snap.Axes.Length > 0 ? snap.Axes[0] : 0;
        float ay = snap.Axes.Length > 1 ? snap.Axes[1] : 0;
        Ink.Circle(sx + ax * 26, sy + ay * 18, 4.4f, C.Red, C.RedDark, 1f, 1f, 0.4f, 8);
        Ink.Text("СТИК", sx, sy + 40, new TextOpt
        {
            Size = 9, Font = FontKind.Display, Align = InkAlign.Center, Color = C.Ink, Alpha = 0.45f
        });

        Ink.Text(snap.Connected ? "ГЕЙМПАД ПОДКЛЮЧЁН" : "ГЕЙМПАД НЕ НАЙДЕН", x + 720, y + 362,
            new TextOpt
            {
                Size = 11, Font = FontKind.Display, Color = snap.Connected ? C.Ink : C.Red,
                Alpha = 0.7f, Spacing = 1
            });
        Ink.Text(snap.Connected ? snap.Id : "нажмите любую кнопку на геймпаде", x + 720, y + 378,
            new TextOpt
            {
                Size = 10, Font = FontKind.Body, Color = C.Ink, Alpha = 0.45f
            });
        Ink.Text("v 0.1 · тестовая раскладка",
            x + 720, y + 398, new TextOpt
            {
                Size = 10, Font = FontKind.Hand, Color = C.Ink, Alpha = 0.5f
            });

        Ink.Line(x + 34, y + 430, x + w - 34, y + 430, C.Rgba(23, 19, 15, 51), 1f, 1f, 0.8f);

        string[] notes =
        {
            "↑ + удар — слэш вверх      ↓ + удар в воздухе — отскок от врага",
            "вниз + прыжок на платформе — спрыгнуть      рывок даёт краткую неуязвимость",
            "удары копят душу, удерживай лечение, чтобы вернуть маску"
        };
        for (int i = 0; i < notes.Length; i++)
            Ink.Text(notes[i], x + w / 2, y + 456 + i * 24, new TextOpt
            {
                Size = 13, Font = FontKind.Hand, Align = InkAlign.Center,
                Color = C.Ink, Alpha = 0.72f
            });

        Ink.Line(x + 34, y + 526, x + w - 34, y + 526, C.Rgba(156, 33, 41, 89),
            1.2f, 1f, 0.8f, new[] { 6f, 6f });
        Ink.Text("ESC / START — НАЗАД", x + 52, y + h - 26, new TextOpt
        {
            Size = 11, Font = FontKind.Display, Color = C.Ink, Alpha = 0.55f, Spacing = 2
        });
        Ink.Text("F1 — ЗАКРЫТЬ", x + w - 52, y + h - 26, new TextOpt
        {
            Size = 11, Font = FontKind.Display, Align = InkAlign.Right,
            Color = C.Ink, Alpha = 0.45f, Spacing = 1
        });
    }

    /* ---------- смерть и отладка ---------- */

    void RenderDeath()
    {
        Ink.Save();
        Ink.Alpha = 0.75f;
        Ink.FillRectColor(0, 0, 1280, 720, C.Rgba(17, 12, 9, 255));
        Ink.Restore();

        Ink.RadialRect(0, 0, 1280, 720, 640, 320, 560, new[]
        {
            (0f, C.Rgba(120, 20, 28, 84)),
            (1f, C.Rgba(120, 20, 28, 0))
        });

        Ink.RadialRect(0, 500, 1280, 220, 640, 575, 520, new[]
        {
            (0f, C.Rgba(17, 12, 9, 175)),
            (0.6f, C.Rgba(17, 12, 9, 80)),
            (1f, C.Rgba(17, 12, 9, 0))
        });

        Ink.Srand(801);
        Ink.Blob(470, 300, 120, C.Rgba(120, 25, 30, 64), outline: false, jitter: 4f);
        Ink.Blob(840, 280, 90, C.Rgba(120, 25, 30, 51), outline: false, jitter: 4f);
        Ink.Blob(640, 330, 210, C.Rgba(20, 15, 11, 205), outline: false, jitter: 3f);

        Ink.Text("ТЫ РАСТВОРИЛСЯ В ЧЕРНИЛАХ", 640, 300, new TextOpt
        {
            Size = 44, Font = FontKind.Title, Align = InkAlign.Center, Color = C.Cream, Ghost = 2
        });
        Ink.Line(400, 322, 880, 322, C.Red, 3f, 1f, 1.8f);
        Ink.Text("но бумага запомнила форму", 640, 352, new TextOpt
        {
            Size = 17, Font = FontKind.Hand, Align = InkAlign.Center, Color = C.Cream, Alpha = 0.55f
        });
        Ink.Text($"время {U.FmtTime(RunTime)}     ·     убийств {Kills}     ·     серия {MaxCombo}",
            640, 404, new TextOpt
            {
                Size = 13, Font = FontKind.Display, Align = InkAlign.Center,
                Color = C.Cream, Alpha = 0.6f, Spacing = 1
            });

        float pulse = 0.55f + MathF.Sin(Clock * 3.4f) * 0.3f;
        Ink.Text("ПРОБЕЛ / A — ВОЗРОЖДЕНИЕ", 640, 560, new TextOpt
        {
            Size = 20, Font = FontKind.Display, Align = InkAlign.Center,
            Color = C.Cream, Alpha = pulse, Spacing = 2
        });
        Ink.Text("ESC / START — В МЕНЮ", 640, 590, new TextOpt
        {
            Size = 11, Font = FontKind.Display, Align = InkAlign.Center,
            Color = C.Cream, Alpha = 0.5f, Spacing = 2
        });
        Ink.Text("каждая смерть — ещё один мазок", 640, 656, new TextOpt
        {
            Size = 13, Font = FontKind.Hand, Align = InkAlign.Center, Color = C.Cream, Alpha = 0.4f
        });
    }

    void RenderDeathFade()
    {
        float a = U.Clamp01(DeathDelay / 1.1f);
        Ink.Save();
        Ink.Alpha = a * 0.6f;
        Ink.FillRectColor(0, 0, 1280, 720, C.Rgba(18, 13, 10, 255));
        Ink.Restore();
    }

    void RenderDebug()
    {
        float dashW = 1.2f;
        void Box(float x, float y, float w, float h, SKColor color)
        {
            Ink.Rect(x, y, w, h, null, color, dashW, 1f, 0f, true, new[] { 5f, 4f });
        }

        foreach (var s in World.Solids) Box(s.X, s.Y, s.W, s.H, C.Rgba(44, 111, 107, 102));
        foreach (var s in World.Oneways) Box(s.X, s.Y, s.W, s.H, C.Rgba(44, 111, 107, 64));
        var phb = Player.Hitbox();
        Box(phb.X, phb.Y, phb.W, phb.H, C.Rgba(31, 122, 58, 255));
        Box(Player.X, Player.Y, Player.W, Player.H, C.Rgba(31, 122, 58, 200));
        if (Player.Attack is not null && Player.AttackActive() && Player.AttackHitbox() is { } ahb)
            Box(ahb.X, ahb.Y, ahb.W, ahb.H, C.Rgba(184, 146, 63, 255));
        foreach (var e in Enemies)
        {
            if (e.Dead) continue;
            var hb = e.Hitbox();
            Box(hb.X, hb.Y, hb.W, hb.H, C.Rgba(156, 33, 41, 230));
        }
        foreach (var pr in Projectiles)
        {
            if (pr.Dead) continue;
            var hb = pr.Hitbox();
            Box(hb.X, hb.Y, hb.W, hb.H, C.Rgba(156, 33, 41, 230));
        }

        Ink.Text($"HITBOXES · {Fps} FPS", 44, 178, new TextOpt
        {
            Size = 10, Font = FontKind.Display, Color = C.Ink, Alpha = 0.5f, Spacing = 2
        });
    }

    /* ---------- отладочный автопрогон ---------- */

    public void DebugStartPlay() => StartRun();
    public void DebugTitle() { State = "title"; TitleT = 0; NewRun(); }

    public void DebugPlacePlayer(float x, float y, int facing = 1)
    {
        Player.X = x;
        Player.Y = y;
        Player.Vx = 0;
        Player.Vy = 0;
        Player.Facing = facing;
        Player.ResetScarf();
    }

    public void DebugAttack() => Player.DebugAttack(1);
    public void DebugAttackHeavy() => Player.DebugAttack(3);
    public void DebugHurt() { Player.IFrames = 0; Player.Hurt(1, Player.Cx + 60); }
    public void DebugKillPlayer() => Player.DebugKill();
    public void DebugPause() => OpenPause(null);
    public void DebugControls()
    {
        if (State == "paused")
        {
            Submenu = "controls";
            MenuIndex = 0;
        }
        else OpenPause("controls");
    }
    public void DebugToggleHitboxes() => DebugHitboxes = !DebugHitboxes;
}
