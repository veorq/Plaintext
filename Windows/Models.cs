using System.Text.Json;
using System.Windows.Media;

namespace Plaintext.Windows;

public enum EditorTheme
{
    Paper,
    Snow,
    Linen,
    Ink,
    Graphite,
    Midnight
}

public sealed record ThemePalette(string Background, string Foreground, string Secondary, string Selection)
{
    public SolidColorBrush BackgroundBrush => Brush(Background);
    public SolidColorBrush ForegroundBrush => Brush(Foreground);
    public SolidColorBrush SecondaryBrush => Brush(Secondary);
    public SolidColorBrush SelectionBrush => Brush(Selection);

    private static SolidColorBrush Brush(string value)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(value));
        brush.Freeze();
        return brush;
    }
}

public static class ThemeCatalog
{
    public static ThemePalette Palette(EditorTheme theme) => theme switch
    {
        EditorTheme.Paper => new("#F6F3EC", "#211F1A", "#666157", "#CCC5AD"),
        EditorTheme.Snow => new("#FFFFFF", "#0D0D0D", "#575757", "#B8CFF5"),
        EditorTheme.Linen => new("#E8E0D1", "#38332C", "#70695C", "#C2B399"),
        EditorTheme.Ink => new("#0E0F11", "#F0F0EB", "#9E9F9C", "#3D5775"),
        EditorTheme.Graphite => new("#21211F", "#C2C0B8", "#85827A", "#4F4D45"),
        EditorTheme.Midnight => new("#0F161C", "#C7D4DC", "#7A8E9C", "#2C4857"),
        _ => throw new ArgumentOutOfRangeException(nameof(theme))
    };
}

public sealed record FontChoice(string Name, string Family)
{
    public static IReadOnlyList<FontChoice> All { get; } =
    [
        new("Georgia", "Georgia"),
        new("Palatino", "Palatino Linotype"),
        new("Cambria", "Cambria"),
        new("Segoe UI", "Segoe UI"),
        new("Arial", "Arial"),
        new("Verdana", "Verdana")
    ];
}

public sealed class AppSettings
{
    public EditorTheme Theme { get; set; } = EditorTheme.Paper;
    public string FontName { get; set; } = "Georgia";
    public bool KeySoundEnabled { get; set; }
    public bool ShowsWordCount { get; set; }
    public string? LastDocumentPath { get; set; }

    public FontChoice Font => FontChoice.All.FirstOrDefault(font => font.Name == FontName) ?? FontChoice.All[0];
}

public static class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static string SupportDirectory
    {
        get
        {
            var path = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Plaintext");
            Directory.CreateDirectory(path);
            return path;
        }
    }

    private static string SettingsPath => Path.Combine(SupportDirectory, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath), Options) ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static void Save(AppSettings settings)
    {
        try
        {
            File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings, Options));
        }
        catch
        {
            // Writing must stay available if settings storage cannot be updated.
        }
    }
}

public sealed record HistorySnapshot(string Path, DateTime Date)
{
    public string DisplayName => Date.ToLocalTime().ToString("d MMM yyyy, HH:mm");
}
