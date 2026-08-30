using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace Plaintext.Windows;

public partial class MainWindow : Window
{
    private readonly AppSettings settings;
    private readonly DocumentController document;
    private readonly KeySoundPlayer keySoundPlayer = new();
    private readonly DispatcherTimer autosaveTimer;
    private bool isSynchronising;
    private bool isFullscreen;
    private WindowStyle previousWindowStyle;
    private WindowState previousWindowState;
    private ResizeMode previousResizeMode;
    private bool previousTopmost;

    public MainWindow()
    {
        InitializeComponent();
        settings = SettingsStore.Load();
        document = new DocumentController(settings);
        autosaveTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        autosaveTimer.Tick += (_, _) =>
        {
            autosaveTimer.Stop();
            document.SaveRecoveryOrDocument();
            UpdateDocumentTitle();
        };

        isSynchronising = true;
        FontPicker.ItemsSource = FontChoice.All;
        FontPicker.SelectedItem = settings.Font;
        KeySoundCheck.IsChecked = settings.KeySoundEnabled;
        WordCountCheck.IsChecked = settings.ShowsWordCount;
        isSynchronising = false;
        ApplySettings();
    }

    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        SynchroniseEditorFromDocument();
        EnterFullscreen();
        Editor.Focus();
    }

    private void Window_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        autosaveTimer.Stop();
        document.SaveRecoveryOrDocument();
        SettingsStore.Save(settings);
    }

    private void Editor_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (isSynchronising) return;
        document.SetText(Editor.Text);
        autosaveTimer.Stop();
        autosaveTimer.Start();
        UpdateWordCount();
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.F11)
        {
            ToggleFullscreen();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Escape)
        {
            if (FindBar.Visibility == Visibility.Visible) CloseFind();
            else if (ModalOverlay.Visibility == Visibility.Visible) HideModal();
            else if (isFullscreen) ExitFullscreen();
            e.Handled = true;
            return;
        }

        if (!Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) return;

        switch (e.Key)
        {
            case Key.N:
                NewDocument();
                break;
            case Key.O:
                OpenDocument();
                break;
            case Key.S:
                if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) SaveAs();
                else SaveDocument();
                break;
            case Key.F:
                ShowFind();
                break;
            case Key.H when Keyboard.Modifiers.HasFlag(ModifierKeys.Shift):
                ShowHistory();
                break;
            case Key.P when Keyboard.Modifiers.HasFlag(ModifierKeys.Shift):
                ShowCommandPalette();
                break;
            case Key.OemComma:
                ShowSettings();
                break;
            case Key.Z:
                if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) Editor.Redo();
                else Editor.Undo();
                break;
            case Key.Y:
                Editor.Redo();
                break;
            default:
                return;
        }

        e.Handled = true;
    }

    private void Editor_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!settings.KeySoundEnabled) return;
        var modifiers = Keyboard.Modifiers;
        if (modifiers.HasFlag(ModifierKeys.Control) || modifiers.HasFlag(ModifierKeys.Alt) || modifiers.HasFlag(ModifierKeys.Windows)) return;

        if (IsWritingKey(e.Key)) keySoundPlayer.Play();
    }

    private static bool IsWritingKey(Key key) =>
        key is Key.Back or Key.Return or Key.Space or Key.Tab ||
        (key >= Key.A && key <= Key.Z) ||
        (key >= Key.D0 && key <= Key.D9) ||
        (key >= Key.NumPad0 && key <= Key.NumPad9) ||
        key is Key.Oem1 or Key.Oem2 or Key.Oem3 or Key.Oem4 or Key.Oem5 or Key.Oem6 or Key.Oem7 or Key.Oem8 or Key.Oem102 or Key.OemComma or Key.OemMinus or Key.OemPeriod or Key.OemPlus;

    private void NewDocument()
    {
        document.NewDocument();
        SynchroniseEditorFromDocument();
    }

    private void OpenDocument()
    {
        var dialog = new OpenFileDialog
        {
            Filter = "Plain text (*.md;*.txt)|*.md;*.txt|All files (*.*)|*.*",
            Multiselect = false,
            Title = "Open a document — it will replace the current one"
        };
        if (dialog.ShowDialog(this) != true) return;

        if (!document.Open(dialog.FileName, out var error))
        {
            ShowError("Plaintext could not open this file.", error);
            return;
        }
        SynchroniseEditorFromDocument();
    }

    private void SaveDocument()
    {
        if (document.DocumentPath is null)
        {
            SaveAs();
            return;
        }

        if (!document.Save(null, out var error)) ShowError("Plaintext could not save this document.", error);
        UpdateDocumentTitle();
    }

    private void SaveAs()
    {
        var dialog = new SaveFileDialog
        {
            Filter = "Text document (*.md)|*.md|Plain text (*.txt)|*.txt",
            DefaultExt = ".md",
            AddExtension = true,
            FileName = document.DocumentPath is null ? "Untitled.md" : Path.GetFileName(document.DocumentPath),
            Title = "Save a plain text document"
        };
        if (dialog.ShowDialog(this) != true) return;

        if (!document.Save(dialog.FileName, out var error)) ShowError("Plaintext could not save this document.", error);
        UpdateDocumentTitle();
    }

    private void ShowFind()
    {
        HideModal();
        FindBar.Visibility = Visibility.Visible;
        FindTextBox.Focus();
        FindTextBox.SelectAll();
    }

    private void CloseFind()
    {
        FindBar.Visibility = Visibility.Collapsed;
        Editor.Focus();
    }

    private void FindNext_Click(object sender, RoutedEventArgs e) => FindNext();

    private void FindTextBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        FindNext();
        e.Handled = true;
    }

    private void ReplaceTextBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        ReplaceCurrent();
        e.Handled = true;
    }

    private void FindNext()
    {
        var query = FindTextBox.Text;
        if (string.IsNullOrEmpty(query)) return;

        var start = Math.Min(Editor.SelectionStart + Editor.SelectionLength, Editor.Text.Length);
        var index = Editor.Text.IndexOf(query, start, StringComparison.OrdinalIgnoreCase);
        if (index < 0 && start > 0) index = Editor.Text.IndexOf(query, 0, StringComparison.OrdinalIgnoreCase);
        if (index < 0)
        {
            MessageBox.Show(this, $"No matches for “{query}”.", "Plaintext", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        Editor.Select(index, query.Length);
        Editor.ScrollToLine(Editor.GetLineIndexFromCharacterIndex(index));
        Editor.Focus();
    }

    private void Replace_Click(object sender, RoutedEventArgs e) => ReplaceCurrent();

    private void ReplaceCurrent()
    {
        var query = FindTextBox.Text;
        if (string.IsNullOrEmpty(query)) return;
        if (string.Equals(Editor.SelectedText, query, StringComparison.OrdinalIgnoreCase)) Editor.SelectedText = ReplaceTextBox.Text;
        FindNext();
    }

    private void ReplaceAll_Click(object sender, RoutedEventArgs e)
    {
        var query = FindTextBox.Text;
        if (string.IsNullOrEmpty(query)) return;
        var updated = Editor.Text.Replace(query, ReplaceTextBox.Text, StringComparison.OrdinalIgnoreCase);
        if (updated == Editor.Text)
        {
            MessageBox.Show(this, $"No matches for “{query}”.", "Plaintext", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        Editor.Text = updated;
    }

    private void CloseFind_Click(object sender, RoutedEventArgs e) => CloseFind();

    private void ShowSettings()
    {
        ShowModal(SettingsPanel);
    }

    private void ThemeButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string value } || !Enum.TryParse<EditorTheme>(value, out var theme)) return;
        settings.Theme = theme;
        ApplySettings();
        SettingsStore.Save(settings);
    }

    private void FontPicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isSynchronising || FontPicker.SelectedItem is not FontChoice font) return;
        settings.FontName = font.Name;
        ApplySettings();
        SettingsStore.Save(settings);
    }

    private void KeySoundCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (isSynchronising) return;
        settings.KeySoundEnabled = KeySoundCheck.IsChecked == true;
        SettingsStore.Save(settings);
    }

    private void WordCountCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (isSynchronising) return;
        settings.ShowsWordCount = WordCountCheck.IsChecked == true;
        UpdateWordCount();
        SettingsStore.Save(settings);
    }

    private void ShowHistory()
    {
        HistoryList.ItemsSource = document.History();
        ShowModal(HistoryPanel);
    }

    private void RestoreHistory_Click(object sender, RoutedEventArgs e)
    {
        if (HistoryList.SelectedItem is not HistorySnapshot snapshot) return;
        if (!document.Restore(snapshot, out var error))
        {
            ShowError("Plaintext could not restore this earlier version.", error);
            return;
        }
        SynchroniseEditorFromDocument();
        document.SaveRecoveryOrDocument();
        HideModal();
    }

    private void ShowCommandPalette()
    {
        CommandSearch.Text = "";
        RebuildCommandList();
        ShowModal(CommandPanel);
        CommandSearch.Focus();
    }

    private void CommandSearch_TextChanged(object sender, TextChangedEventArgs e) => RebuildCommandList();

    private void CommandSearch_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Enter) return;
        if (CommandList.Children.OfType<Button>().FirstOrDefault()?.Tag is PaletteAction action) RunPaletteAction(action);
        e.Handled = true;
    }

    private void RebuildCommandList()
    {
        var filter = CommandSearch.Text?.Trim() ?? "";
        CommandList.Children.Clear();
        foreach (var action in PaletteActions().Where(action => action.Title.Contains(filter, StringComparison.OrdinalIgnoreCase)))
        {
            var button = new Button
            {
                Tag = action,
                Content = string.IsNullOrEmpty(action.Shortcut) ? action.Title : $"{action.Title}                                      {action.Shortcut}",
                HorizontalContentAlignment = HorizontalAlignment.Left,
                BorderThickness = new Thickness(0)
            };
            button.Click += (_, _) => RunPaletteAction(action);
            CommandList.Children.Add(button);
        }
    }

    private IReadOnlyList<PaletteAction> PaletteActions() =>
    [
        new("Open document", "Ctrl O", OpenDocument),
        new("Save as", "Ctrl Shift S", SaveAs),
        new("Find and replace", "Ctrl F", ShowFind),
        new("Restore earlier version", "Ctrl Shift H", ShowHistory),
        new(settings.ShowsWordCount ? "Hide word count" : "Show word count", "", ToggleWordCount),
        new("Settings", "Ctrl ,", ShowSettings),
        new("Toggle fullscreen", "F11", ToggleFullscreen)
    ];

    private void RunPaletteAction(PaletteAction action)
    {
        HideModal();
        action.Run();
    }

    private void ToggleWordCount()
    {
        settings.ShowsWordCount = !settings.ShowsWordCount;
        isSynchronising = true;
        WordCountCheck.IsChecked = settings.ShowsWordCount;
        isSynchronising = false;
        UpdateWordCount();
        SettingsStore.Save(settings);
    }

    private void ShowModal(Border panel)
    {
        CloseFind();
        SettingsPanel.Visibility = Visibility.Collapsed;
        CommandPanel.Visibility = Visibility.Collapsed;
        HistoryPanel.Visibility = Visibility.Collapsed;
        panel.Visibility = Visibility.Visible;
        ModalOverlay.Visibility = Visibility.Visible;
    }

    private void HideModal()
    {
        ModalOverlay.Visibility = Visibility.Collapsed;
        SettingsPanel.Visibility = Visibility.Collapsed;
        CommandPanel.Visibility = Visibility.Collapsed;
        HistoryPanel.Visibility = Visibility.Collapsed;
        Editor.Focus();
    }

    private void CloseModal_Click(object sender, RoutedEventArgs e) => HideModal();

    private void SynchroniseEditorFromDocument()
    {
        isSynchronising = true;
        Editor.Text = document.Text;
        Editor.CaretIndex = 0;
        isSynchronising = false;
        UpdateDocumentTitle();
        UpdateWordCount();
        Editor.Focus();
    }

    private void UpdateDocumentTitle()
    {
        DocumentTitle.Text = document.DisplayTitle;
        Title = $"Plaintext — {document.DisplayTitle}";
    }

    private void UpdateWordCount()
    {
        WordCount.Visibility = settings.ShowsWordCount ? Visibility.Visible : Visibility.Collapsed;
        if (!settings.ShowsWordCount) return;
        var count = Editor.Text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
        WordCount.Text = count == 1 ? "1 word" : $"{count} words";
    }

    private void ApplySettings()
    {
        var palette = ThemeCatalog.Palette(settings.Theme);
        Background = palette.BackgroundBrush;
        Foreground = palette.ForegroundBrush;
        Editor.Foreground = palette.ForegroundBrush;
        Editor.CaretBrush = palette.ForegroundBrush;
        Editor.SelectionBrush = palette.SelectionBrush;
        Editor.FontFamily = new FontFamily(settings.Font.Family);
        DocumentTitle.Foreground = palette.SecondaryBrush;
        WordCount.Foreground = palette.SecondaryBrush;
        FindBar.Background = palette.BackgroundBrush;
        FindBar.BorderBrush = palette.SecondaryBrush;
        SettingsPanel.Background = palette.BackgroundBrush;
        SettingsPanel.BorderBrush = palette.SecondaryBrush;
        CommandPanel.Background = palette.BackgroundBrush;
        CommandPanel.BorderBrush = palette.SecondaryBrush;
        HistoryPanel.Background = palette.BackgroundBrush;
        HistoryPanel.BorderBrush = palette.SecondaryBrush;
        FindTextBox.Foreground = palette.ForegroundBrush;
        ReplaceTextBox.Foreground = palette.ForegroundBrush;
        CommandSearch.Foreground = palette.ForegroundBrush;
        FontPicker.Foreground = palette.ForegroundBrush;
        FontPicker.Background = palette.BackgroundBrush;
        HistoryList.Foreground = palette.ForegroundBrush;
        HistoryList.Background = palette.BackgroundBrush;
    }

    private void ToggleFullscreen()
    {
        if (isFullscreen) ExitFullscreen();
        else EnterFullscreen();
    }

    private void EnterFullscreen()
    {
        if (isFullscreen) return;
        previousWindowStyle = WindowStyle;
        previousWindowState = WindowState;
        previousResizeMode = ResizeMode;
        previousTopmost = Topmost;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        Topmost = true;
        WindowState = WindowState.Maximized;
        isFullscreen = true;
    }

    private void ExitFullscreen()
    {
        if (!isFullscreen) return;
        Topmost = previousTopmost;
        WindowStyle = previousWindowStyle;
        ResizeMode = previousResizeMode;
        WindowState = previousWindowState;
        isFullscreen = false;
    }

    private void ShowError(string heading, string? detail) =>
        MessageBox.Show(this, string.IsNullOrWhiteSpace(detail) ? heading : $"{heading}\n\n{detail}", "Plaintext", MessageBoxButton.OK, MessageBoxImage.Warning);

    private sealed record PaletteAction(string Title, string Shortcut, Action Run);
}
