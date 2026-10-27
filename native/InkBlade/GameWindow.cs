using System.Diagnostics;
using SkiaSharp;
using SkiaSharp.Views.Desktop;

namespace InkBlade;

public sealed class GameWindow : Form
{
    readonly Control _canvas;
    readonly SKGLControl? _glCanvas;
    readonly System.Windows.Forms.Timer _timer;
    readonly Stopwatch _watch = Stopwatch.StartNew();
    readonly Game _game = new();
    readonly Queue<(double at, string action)> _auto = new();
    double _lastTime;
    double _startTime;
    bool _fullscreen;
    bool _autoTest;
    bool _autoDone;
    bool _noShots;
    bool _noAudio;
    string _shotDir = "";
    string? _pendingShot;
    string? _autoShotFile;
    FormBorderStyle _oldBorder;
    Rectangle _oldBounds;

    public GameWindow(string[] args)
    {
        Text = "Чернильный клинок";
        ClientSize = new Size(1280, 720);
        MinimumSize = new Size(960, 600);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.Black;
        KeyPreview = true;
        DoubleBuffered = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                 | ControlStyles.UserPaint, true);

        Control canvas;
        SKGLControl? gl = null;
        try
        {
            gl = new SKGLControl { Dock = DockStyle.Fill, BackColor = Color.Black };
            gl.PaintSurface += OnGlPaintSurface;
            canvas = gl;
            Program.Log("renderer: OpenGL");
        }
        catch (Exception ex)
        {
            Program.Log("OpenGL unavailable, CPU fallback: " + ex.Message);
            var cpu = new SKControl { Dock = DockStyle.Fill, BackColor = Color.Black };
            cpu.PaintSurface += OnPaintSurface;
            canvas = cpu;
        }
        _canvas = canvas;
        _glCanvas = gl;
        Controls.Add(canvas);

        int shotArg = Array.IndexOf(args, "--shot");
        if (shotArg >= 0 && shotArg + 1 < args.Length) _autoShotFile = args[shotArg + 1];
        int outArg = Array.IndexOf(args, "--out");
        _shotDir = outArg >= 0 && outArg + 1 < args.Length
            ? Path.GetFullPath(args[outArg + 1])
            : Path.Combine(AppContext.BaseDirectory, "snapshots");

        _autoTest = args.Contains("--autotest");
        _noShots = args.Contains("--noshots");
        _noAudio = args.Contains("--noaudio");
        Input.Disabled = _autoTest;
        BuildAutoTest();
        if (args.Contains("--autoshot"))
        {
            var t = new System.Windows.Forms.Timer { Interval = 900 };
            t.Tick += (_, _) => { t.Stop(); RequestShot(_autoShotFile ?? NextShotPath("native-shot")); };
            t.Start();
        }

        Ink.Init();
        _game.Init();
        if (!_noAudio)
        {
            Audio.Init();
            if (_autoTest) Audio.SetMuted(true);
        }
        _startTime = _watch.Elapsed.TotalSeconds;

        _canvas.KeyDown += OnKeyDown;
        _canvas.KeyUp += OnKeyUp;
        KeyDown += OnKeyDown;
        KeyUp += OnKeyUp;
        Deactivate += (_, _) => Input.Clear();
        Shown += (_, _) =>
        {
            Focus();
            Input.Clear();
            _startTime = _watch.Elapsed.TotalSeconds;
            if (_autoTest) _canvas.Invalidate();
        };
        FormClosing += (_, _) =>
        {
            _timer!.Stop();
            Audio.Shutdown();
        };

        _timer = new System.Windows.Forms.Timer { Interval = 15 };
        _timer.Tick += OnTick;
        _timer.Start();
        _lastTime = _watch.Elapsed.TotalSeconds;
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        Keys key = keyData & Keys.KeyCode;
        if (key == Keys.Escape || Input.IsBound(key))
        {
            Input.OnKeyDown(key);
            if (key == Keys.Enter && (keyData & Keys.Alt) != 0) ToggleFullscreen();
            return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    void OnTick(object? sender, EventArgs e)
    {
        try
        {
            double now = _watch.Elapsed.TotalSeconds;
            float dt = (float)Math.Clamp(now - _lastTime, 0, 0.05);
            _lastTime = now;

            Input.Update(dt);

            if (Input.Pressed(InputAction.Fullscreen)) ToggleFullscreen();
            if (Input.Pressed(InputAction.Screenshot)) RequestShot();

            if (_autoTest && !_autoDone) RunAutoTest(now - _startTime);

            _game.Frame(dt);
            _canvas.Invalidate();
        }
        catch (Exception ex)
        {
            Program.Log("OnTick: " + ex);
            _autoDone = true;
            Close();
        }
    }

    void OnKeyDown(object? sender, KeyEventArgs e)
    {
        Input.OnKeyDown(e.KeyCode);
        if (e.KeyCode == Keys.Enter && e.Alt) ToggleFullscreen();
        if (Input.IsBound(e.KeyCode)) e.SuppressKeyPress = true;
    }

    void OnKeyUp(object? sender, KeyEventArgs e)
    {
        Input.OnKeyUp(e.KeyCode);
        if (Input.IsBound(e.KeyCode)) e.SuppressKeyPress = true;
    }

    void ToggleFullscreen()
    {
        if (!_fullscreen)
        {
            _oldBorder = FormBorderStyle;
            _oldBounds = Bounds;
            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Maximized;
            _fullscreen = true;
        }
        else
        {
            WindowState = FormWindowState.Normal;
            FormBorderStyle = _oldBorder;
            Bounds = _oldBounds;
            _fullscreen = false;
        }
    }

    void DrawFrame(SKCanvas canvas, int cw, int ch)
    {
        canvas.Clear(new SKColor(0x0b, 0x09, 0x08));
        float scale = MathF.Min(cw / 1280f, ch / 720f);
        float ox = (cw - 1280f * scale) * 0.5f;
        float oy = (ch - 720f * scale) * 0.5f;
        canvas.Save();
        canvas.Translate(ox, oy);
        canvas.Scale(scale);
        canvas.ClipRect(new SKRect(0, 0, 1280, 720));
        Ink.SetCanvas(canvas);
        _game.Render();
        canvas.Restore();
    }

    void OnGlPaintSurface(object? sender, SKPaintGLSurfaceEventArgs e)
    {
        try
        {
            var canvas = e.Surface.Canvas;
            DrawFrame(canvas, e.Info.Width, e.Info.Height);
            if (_pendingShot is { } path)
            {
                _pendingShot = null;
                SaveShot(path);
                Ink.SetCanvas(canvas);
            }
        }
        catch (Exception ex)
        {
            Program.Log("OnGLPaint: " + ex);
            _autoDone = true;
            Close();
        }
    }

    void OnPaintSurface(object? sender, SKPaintSurfaceEventArgs e)
    {
        try
        {
            var canvas = e.Surface.Canvas;
            DrawFrame(canvas, e.Info.Width, e.Info.Height);
            if (_pendingShot is { } path)
            {
                _pendingShot = null;
                SaveShot(path);
                Ink.SetCanvas(canvas);
            }
        }
        catch (Exception ex)
        {
            Program.Log("OnPaint: " + ex);
            _autoDone = true;
            Close();
        }
    }

    void RequestShot(string? path = null)
    {
        _pendingShot = path ?? NextShotPath(null);
    }

    string NextShotPath(string? name)
    {
        Directory.CreateDirectory(_shotDir);
        string file = name ?? $"native-{DateTime.Now:HHmmss}.png";
        if (!file.EndsWith(".png", StringComparison.OrdinalIgnoreCase)) file += ".png";
        return Path.Combine(_shotDir, file);
    }

    void SaveShot(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? _shotDir);
        using var bmp = new SKBitmap(new SKImageInfo(1280, 720, SKColorType.Bgra8888, SKAlphaType.Premul));
        using (var canvas = new SKCanvas(bmp))
        {
            canvas.Clear(SKColors.Black);
            Ink.SetCanvas(canvas);
            _game.Render();
        }
        using var image = SKImage.FromBitmap(bmp);
        using var data = image.Encode(SKEncodedImageFormat.Png, 94);
        using var fs = File.Create(path);
        data.SaveTo(fs);
    }

    void BuildAutoTest()
    {
        if (!_autoTest) return;
        void At(double t, string action, double? shotAt = null, string? shot = null)
        {
            _auto.Enqueue((t, action));
            if (!_noShots && shotAt is { } st) _auto.Enqueue((st, "shot:" + shot));
        }

        At(0.7, "noop", 1.0, "01-title");
        At(1.4, "play", 2.1, "02-play");
        At(2.8, "arena", 3.15, "03-arena");
        At(3.3, "attack", 3.46, "04-slash");
        At(3.8, "noop", 4.05, "05-hit");
        At(4.3, "hurt", 4.5, "06-hurt");
        At(4.9, "pause", 5.2, "07-pause");
        At(5.6, "controls", 5.9, "08-controls");
        At(6.3, "play", 6.8, "09-play2");
        At(7.0, "kill", 9.2, "10-death");
        At(9.8, "exit");
    }

    void RunAutoTest(double t)
    {
        while (_auto.Count > 0 && _auto.Peek().at <= t)
        {
            var (_, action) = _auto.Dequeue();
            if (action.StartsWith("shot:"))
            {
                RequestShot(NextShotPath(action[5..]));
                continue;
            }
            switch (action)
            {
                case "noop": break;
                case "play": _game.DebugStartPlay(); break;
                case "arena":
                    _game.DebugPlacePlayer(540, 574, 1);
                    break;
                case "attack": _game.DebugAttack(); break;
                case "hurt": _game.DebugHurt(); break;
                case "pause": _game.DebugPause(); break;
                case "controls": _game.DebugControls(); break;
                case "kill": _game.DebugKillPlayer(); break;
                case "exit":
                    _autoDone = true;
                    Close();
                    break;
            }
        }
    }
}
