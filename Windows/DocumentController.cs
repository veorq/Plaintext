using System.Security.Cryptography;
using System.Text;

namespace Plaintext.Windows;

public sealed class DocumentController
{
    private readonly AppSettings settings;
    private string lastSnapshotText = "";

    public DocumentController(AppSettings settings)
    {
        this.settings = settings;
        RestorePreviousSession();
    }

    public string Text { get; private set; } = "";
    public string? DocumentPath { get; private set; }
    public string DisplayTitle => DocumentPath is null ? "Untitled" : Path.GetFileName(DocumentPath);

    public void SetText(string text) => Text = text;

    public void NewDocument()
    {
        DocumentPath = null;
        Text = "";
        lastSnapshotText = "";
        settings.LastDocumentPath = null;
        SettingsStore.Save(settings);
        WriteRecovery();
    }

    public bool Open(string path, out string? error)
    {
        try
        {
            Text = File.ReadAllText(path, Encoding.UTF8);
            DocumentPath = path;
            lastSnapshotText = Text;
            settings.LastDocumentPath = path;
            SettingsStore.Save(settings);
            DeleteRecovery();
            error = null;
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return false;
        }
    }

    public bool Save(string? path, out string? error)
    {
        path ??= DocumentPath;
        if (string.IsNullOrWhiteSpace(path))
        {
            error = "Choose a location before saving this document.";
            return false;
        }

        try
        {
            File.WriteAllText(path, Text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            DocumentPath = path;
            settings.LastDocumentPath = path;
            SettingsStore.Save(settings);
            WriteSnapshotIfNeeded();
            DeleteRecovery();
            error = null;
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return false;
        }
    }

    public void SaveRecoveryOrDocument()
    {
        if (DocumentPath is not null)
        {
            Save(DocumentPath, out _);
        }
        else
        {
            WriteRecovery();
        }
    }

    public IReadOnlyList<HistorySnapshot> History()
    {
        var directory = HistoryDirectory;
        if (directory is null || !Directory.Exists(directory)) return [];

        return Directory.EnumerateFiles(directory, "*.md")
            .Select(path => new HistorySnapshot(path, File.GetLastWriteTimeUtc(path)))
            .OrderByDescending(snapshot => snapshot.Date)
            .ToList();
    }

    public bool Restore(HistorySnapshot snapshot, out string? error)
    {
        try
        {
            Text = File.ReadAllText(snapshot.Path, Encoding.UTF8);
            error = null;
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return false;
        }
    }

    private void RestorePreviousSession()
    {
        if (!string.IsNullOrWhiteSpace(settings.LastDocumentPath) && File.Exists(settings.LastDocumentPath))
        {
            Open(settings.LastDocumentPath, out _);
            return;
        }

        try
        {
            if (File.Exists(RecoveryPath)) Text = File.ReadAllText(RecoveryPath, Encoding.UTF8);
        }
        catch
        {
            // An unavailable recovery file must never prevent opening the editor.
        }
    }

    private void WriteRecovery()
    {
        try { File.WriteAllText(RecoveryPath, Text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)); }
        catch { }
    }

    private void DeleteRecovery()
    {
        try { if (File.Exists(RecoveryPath)) File.Delete(RecoveryPath); }
        catch { }
    }

    private string RecoveryPath => Path.Combine(SettingsStore.SupportDirectory, "recovery.md");

    private string? HistoryDirectory
    {
        get
        {
            if (DocumentPath is null) return null;
            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(DocumentPath)))).ToLowerInvariant()[..16];
            var directory = Path.Combine(SettingsStore.SupportDirectory, "History", hash);
            Directory.CreateDirectory(directory);
            return directory;
        }
    }

    private void WriteSnapshotIfNeeded()
    {
        var directory = HistoryDirectory;
        if (directory is null || Text == lastSnapshotText) return;

        try
        {
            var fileName = DateTime.UtcNow.ToString("yyyy-MM-ddTHH-mm-ss.fffffffZ") + ".md";
            File.WriteAllText(Path.Combine(directory, fileName), Text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            lastSnapshotText = Text;

            foreach (var oldSnapshot in History().Skip(80)) File.Delete(oldSnapshot.Path);
        }
        catch
        {
            // Local history is a convenience, never a reason to block saving.
        }
    }
}
