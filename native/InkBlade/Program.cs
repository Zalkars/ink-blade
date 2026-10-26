using System.Runtime.InteropServices;

namespace InkBlade;

internal static class Program
{
    static readonly string LogFile = Path.Combine(Path.GetTempPath(), "inkblade.log");

    public static void Log(string msg)
    {
        try
        {
            File.AppendAllText(LogFile, $"[{DateTime.Now:HH:mm:ss.fff}] {msg}{Environment.NewLine}");
        }
        catch { }
    }

    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) => Log("ThreadException: " + e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log("Unhandled: " + e.ExceptionObject);
        try
        {
            Application.Run(new GameWindow(args));
        }
        catch (Exception ex)
        {
            Log("Main: " + ex);
        }
    }
}
