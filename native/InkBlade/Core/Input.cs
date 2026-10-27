using System.Runtime.InteropServices;

namespace InkBlade;

public enum InputAction
{
    Left, Right, Up, Down, Jump, Attack, Dash, Heal,
    Pause, Restart, Help, Hitboxes, Mute, Fullscreen, Screenshot
}

public sealed class PadSnapshot
{
    public bool Connected;
    public string Id = "";
    public bool[] Buttons = Array.Empty<bool>();
    public float[] Axes = new float[2];
}

public static class Input
{
    static readonly HashSet<Keys> KeysDown = new();

    static readonly Dictionary<InputAction, Keys[]> Keyboard = new()
    {
        [InputAction.Left] = new[] { Keys.A, Keys.Left },
        [InputAction.Right] = new[] { Keys.D, Keys.Right },
        [InputAction.Up] = new[] { Keys.W, Keys.Up },
        [InputAction.Down] = new[] { Keys.S, Keys.Down },
        [InputAction.Jump] = new[] { Keys.Space, Keys.Z },
        [InputAction.Attack] = new[] { Keys.J, Keys.X },
        [InputAction.Dash] = new[] { Keys.K, Keys.C, Keys.LShiftKey, Keys.RShiftKey },
        [InputAction.Heal] = new[] { Keys.L, Keys.V },
        [InputAction.Pause] = new[] { Keys.Escape },
        [InputAction.Restart] = new[] { Keys.R },
        [InputAction.Help] = new[] { Keys.F1 },
        [InputAction.Hitboxes] = new[] { Keys.F2, Keys.F },
        [InputAction.Mute] = new[] { Keys.M },
        [InputAction.Fullscreen] = new[] { Keys.F11 },
        [InputAction.Screenshot] = new[] { Keys.F12 }
    };

    static readonly Dictionary<InputAction, int[]> Pad = new()
    {
        [InputAction.Jump] = new[] { 0 },
        [InputAction.Attack] = new[] { 2, 5 },
        [InputAction.Dash] = new[] { 1, 4 },
        [InputAction.Heal] = new[] { 3 },
        [InputAction.Pause] = new[] { 9 },
        [InputAction.Restart] = new[] { 8 }
    };

    static readonly InputAction[] All = Enum.GetValues<InputAction>();
    static readonly bool[] State = new bool[All.Length];
    static readonly bool[] Prev = new bool[All.Length];
    static readonly bool[] Edge = new bool[All.Length];
    static readonly float[] Repeat = new float[All.Length];

    public static string Device = "keyboard";
    public static bool Disabled;
    public static bool PadConnected;
    public static string PadId = "";
    public static bool[] PadButtons = new bool[16];
    public static float[] PadAxes = new float[2];
    public static float MoveX, MoveY;

    const float Deadzone = 0.32f;
    static float _rumbleTime;
    static float _rumbleStrong, _rumbleWeak;
    static bool _xinputBroken;
    static bool _prevEnter, _edgeEnter;

    public static void Clear()
    {
        KeysDown.Clear();
    }

    public static void OnKeyDown(Keys key)
    {
        KeysDown.Add(key);
        Device = "keyboard";
        Audio.Unlock();
    }

    public static void OnKeyUp(Keys key)
    {
        KeysDown.Remove(key);
    }

    public static bool IsBound(Keys key)
    {
        foreach (var list in Keyboard.Values)
            if (Array.IndexOf(list, key) >= 0) return true;
        return false;
    }

    public static void Update(float dt)
    {
        bool enterDown = KeysDown.Contains(Keys.Enter);
        _edgeEnter = enterDown && !_prevEnter;
        _prevEnter = enterDown;

        float[]? padAxes = null;
        bool[]? padButtons = null;
        bool padUsed = false;

        if (TryGetPad(out var pad))
        {
            PadConnected = true;
            PadId = "Xbox Controller (XInput)";
            padButtons = new bool[16];
            void Set(int i, bool v) { padButtons[i] = v; }
            ushort b = pad.wButtons;
            Set(0, (b & 0x1000) != 0);
            Set(1, (b & 0x2000) != 0);
            Set(2, (b & 0x4000) != 0);
            Set(3, (b & 0x8000) != 0);
            Set(4, (b & 0x0100) != 0);
            Set(5, (b & 0x0200) != 0);
            Set(6, pad.bLeftTrigger > 40);
            Set(7, pad.bRightTrigger > 40);
            Set(8, (b & 0x0020) != 0);
            Set(9, (b & 0x0010) != 0);
            Set(10, (b & 0x0040) != 0);
            Set(11, (b & 0x0080) != 0);
            Set(12, (b & 0x0001) != 0);
            Set(13, (b & 0x0002) != 0);
            Set(14, (b & 0x0004) != 0);
            Set(15, (b & 0x0008) != 0);
            padAxes = new[] { pad.sThumbLX / 32767f, -pad.sThumbLY / 32767f };
            for (int i = 0; i < 16; i++) if (padButtons[i]) padUsed = true;
            if (MathF.Abs(padAxes[0]) > 0.45f || MathF.Abs(padAxes[1]) > 0.45f) padUsed = true;
        }
        else
        {
            if (PadConnected)
            {
                PadConnected = false;
                PadId = "";
            }
            padButtons = new bool[16];
            padAxes = new float[2];
        }

        PadButtons = padButtons;
        PadAxes = padAxes;
        if (padUsed) Device = "gamepad";

        if (Disabled)
        {
            Array.Clear(State);
            Array.Clear(Prev);
            Array.Clear(Edge);
            MoveX = MoveY = 0;
            _rumbleTime = 0;
            return;
        }

        float kx = (KeysDown.Contains(Keys.D) || KeysDown.Contains(Keys.Right) ? 1 : 0)
                 - (KeysDown.Contains(Keys.A) || KeysDown.Contains(Keys.Left) ? 1 : 0);
        float ky = (KeysDown.Contains(Keys.S) || KeysDown.Contains(Keys.Down) ? 1 : 0)
                 - (KeysDown.Contains(Keys.W) || KeysDown.Contains(Keys.Up) ? 1 : 0);

        float sx = padAxes[0], sy = padAxes[1];
        sx = MathF.Abs(sx) < Deadzone ? 0 : MathF.Sign(sx) * ((MathF.Abs(sx) - Deadzone) / (1 - Deadzone));
        sy = MathF.Abs(sy) < Deadzone ? 0 : MathF.Sign(sy) * ((MathF.Abs(sy) - Deadzone) / (1 - Deadzone));

        float dpadX = (padButtons[15] ? 1 : 0) - (padButtons[14] ? 1 : 0);
        float dpadY = (padButtons[13] ? 1 : 0) - (padButtons[12] ? 1 : 0);

        float moveX = kx;
        if (MathF.Abs(sx) > MathF.Abs(moveX)) moveX = sx;
        if (dpadX != 0) moveX = dpadX;
        MoveX = Math.Clamp(moveX, -1f, 1f);
        MoveY = ky != 0 ? ky : dpadY != 0 ? dpadY : (MathF.Abs(sy) > 0.55f ? MathF.Sign(sy) : 0f);

        for (int i = 0; i < All.Length; i++)
        {
            var a = All[i];
            bool down = false;
            if (Keyboard.TryGetValue(a, out var keys))
                foreach (var k in keys)
                    if (KeysDown.Contains(k)) { down = true; break; }
            if (Pad.TryGetValue(a, out var btns))
                foreach (var bi in btns)
                    if (padButtons[bi]) { down = true; break; }

            if (a == InputAction.Left) down |= dpadX < 0 || sx < -0.5f;
            if (a == InputAction.Right) down |= dpadX > 0 || sx > 0.5f;
            if (a == InputAction.Up) down |= dpadY < 0 || sy < -0.55f;
            if (a == InputAction.Down) down |= dpadY > 0 || sy > 0.55f;

            Prev[i] = State[i];
            State[i] = down;
            Edge[i] = down && !Prev[i];
        }

        foreach (var a in new[] { InputAction.Up, InputAction.Down })
        {
            int i = (int)a;
            if (Edge[i]) Repeat[i] = -0.38f;
            else if (State[i])
            {
                Repeat[i] += dt;
                if (Repeat[i] >= 0.11f) { Repeat[i] = 0; Edge[i] = true; }
            }
            else Repeat[i] = -1;
        }

        _rumbleTime = MathF.Max(0, _rumbleTime - dt);
        if (_xinputBroken) return;
        var vibration = new XInputVibration
        {
            wLeftMotorSpeed = _rumbleTime > 0 ? (ushort)(_rumbleStrong * 65535) : (ushort)0,
            wRightMotorSpeed = _rumbleTime > 0 ? (ushort)(_rumbleWeak * 65535) : (ushort)0
        };
        try
        {
            XInputSetState(0, ref vibration);
        }
        catch (DllNotFoundException) { _xinputBroken = true; }
        catch (EntryPointNotFoundException) { _xinputBroken = true; }
    }

    public static bool Down(InputAction a) => State[(int)a];
    public static bool Pressed(InputAction a) => Edge[(int)a];
    public static float AxisX() => MoveX;
    public static float AxisY() => MoveY;
    public static bool Confirm() => Edge[(int)InputAction.Jump] || Edge[(int)InputAction.Attack] || _edgeEnter;

    public static string Label(InputAction a)
    {
        string[] kb =
        {
            "A / ←", "D / →", "W / ↑", "S / ↓", "ПРОБЕЛ", "J", "K", "L",
            "ESC", "R", "F1", "F2", "M", "F11", "F12"
        };
        string[] gp =
        {
            "СТИК", "СТИК", "СТИК", "СТИК", "A", "X", "B", "Y",
            "START", "BACK", "—", "—", "—", "—", "—"
        };
        return Device == "gamepad" ? gp[(int)a] : kb[(int)a];
    }

    public static void Rumble(float strong, float weak, int ms)
    {
        _rumbleStrong = Math.Clamp(strong, 0f, 1f);
        _rumbleWeak = Math.Clamp(weak, 0f, 1f);
        _rumbleTime = ms / 1000f;
    }

    public static PadSnapshot Snapshot() => new()
    {
        Connected = PadConnected,
        Id = PadId,
        Buttons = (bool[])PadButtons.Clone(),
        Axes = (float[])PadAxes.Clone()
    };

    /* ---------- XInput ---------- */

    [StructLayout(LayoutKind.Sequential)]
    struct XInputGamepad
    {
        public ushort wButtons;
        public byte bLeftTrigger;
        public byte bRightTrigger;
        public short sThumbLX;
        public short sThumbLY;
        public short sThumbRX;
        public short sThumbRY;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct XInputState
    {
        public uint dwPacketNumber;
        public XInputGamepad Gamepad;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct XInputVibration
    {
        public ushort wLeftMotorSpeed;
        public ushort wRightMotorSpeed;
    }

    [DllImport("xinput1_4.dll", EntryPoint = "XInputGetState")]
    static extern int XInputGetState(int index, out XInputState state);

    [DllImport("xinput1_4.dll", EntryPoint = "XInputSetState")]
    static extern int XInputSetState(int index, ref XInputVibration vibration);

    static bool TryGetPad(out XInputGamepad pad)
    {
        pad = default;
        if (_xinputBroken) return false;
        try
        {
            if (XInputGetState(0, out var state) == 0)
            {
                pad = state.Gamepad;
                return true;
            }
        }
        catch (DllNotFoundException) { _xinputBroken = true; }
        catch (EntryPointNotFoundException) { _xinputBroken = true; }
        return false;
    }
}
