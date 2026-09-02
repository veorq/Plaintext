mod document;
mod fonts;
mod key_sound;
mod models;

use std::{cell::RefCell, path::PathBuf, rc::Rc, time::Duration};

use gtk::{gdk, glib, prelude::*};
use gtk4 as gtk;
use regex::RegexBuilder;

use document::{DocumentController, HistorySnapshot};
use fonts::register_bundled_fonts;
use key_sound::KeySoundPlayer;
use models::{EditorTheme, FontChoice, Settings};

const APP_ID: &str = "jp.aumasson.Plaintext";

struct AppState {
    settings: Settings,
    document: DocumentController,
    window: gtk::ApplicationWindow,
    editor: gtk::TextView,
    title: gtk::Label,
    word_count: gtk::Label,
    css_provider: gtk::CssProvider,
    key_sound: KeySoundPlayer,
    save_source: Option<glib::SourceId>,
    synchronising: bool,
    is_fullscreen: bool,
}

fn main() {
    // Register the private fonts before GTK creates its Pango font map. Registering
    // them from `build_ui` is too late on desktops where the map is populated
    // during application startup, causing every family to fall back to the
    // desktop's default font.
    register_bundled_fonts();
    let application = gtk::Application::builder().application_id(APP_ID).build();
    application.connect_activate(build_ui);
    application.run();
}

fn build_ui(application: &gtk::Application) {
    let settings = Settings::load();
    let document = DocumentController::restore_previous_session(&settings);
    let window = gtk::ApplicationWindow::builder()
        .application(application)
        .title("Plaintext")
        .default_width(1100)
        .default_height(760)
        .build();
    window.add_css_class("plaintext-window");

    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.add_css_class("plaintext-root");

    let title = gtk::Label::new(None);
    title.add_css_class("document-title");
    title.set_margin_top(17);
    title.set_margin_bottom(0);
    title.set_ellipsize(gtk::pango::EllipsizeMode::End);
    root.append(&title);

    let editor = gtk::TextView::new();
    editor.add_css_class("editor");
    editor.set_wrap_mode(gtk::WrapMode::WordChar);
    editor.set_accepts_tab(false);
    editor.set_monospace(false);
    editor.set_left_margin(22);
    editor.set_right_margin(22);
    editor.set_top_margin(72);
    editor.set_bottom_margin(72);
    editor.set_pixels_below_lines(10);
    editor.set_vexpand(true);

    let scroller = gtk::ScrolledWindow::new();
    scroller.set_child(Some(&editor));
    scroller.set_hscrollbar_policy(gtk::PolicyType::Never);
    scroller.set_vscrollbar_policy(gtk::PolicyType::Automatic);
    scroller.set_vexpand(true);

    let editor_frame = gtk::Box::new(gtk::Orientation::Vertical, 0);
    editor_frame.add_css_class("editor-frame");
    editor_frame.set_width_request(760);
    editor_frame.set_hexpand(false);
    editor_frame.set_halign(gtk::Align::Center);
    editor_frame.set_vexpand(true);
    editor_frame.set_margin_start(28);
    editor_frame.set_margin_end(28);
    editor_frame.append(&scroller);
    root.append(&editor_frame);

    let word_count = gtk::Label::new(None);
    word_count.add_css_class("word-count");
    word_count.set_halign(gtk::Align::End);
    word_count.set_margin_end(25);
    word_count.set_margin_bottom(16);
    root.append(&word_count);

    window.set_child(Some(&root));

    let css_provider = gtk::CssProvider::new();
    let display = gdk::Display::default().expect("Plaintext requires a graphical display");
    gtk::style_context_add_provider_for_display(
        &display,
        &css_provider,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );

    let state = Rc::new(RefCell::new(AppState {
        settings,
        document,
        window: window.clone(),
        editor: editor.clone(),
        title,
        word_count,
        css_provider,
        key_sound: KeySoundPlayer::new(),
        save_source: None,
        synchronising: false,
        is_fullscreen: false,
    }));

    apply_settings(&state);
    synchronise_editor_from_document(&state);

    let editor_state = state.clone();
    editor.buffer().connect_changed(move |buffer| {
        let is_synchronising = editor_state.borrow().synchronising;
        if is_synchronising {
            return;
        }
        let text = buffer_text(buffer);
        editor_state
            .borrow_mut()
            .document
            .set_text_from_editor(text);
        update_word_count(&editor_state);
        schedule_persistence(&editor_state);
    });

    install_keyboard_shortcuts(&state);

    let closing_state = state.clone();
    window.connect_close_request(move |_| {
        let mut app = closing_state.borrow_mut();
        if let Some(source) = app.save_source.take() {
            source.remove();
        }
        app.document.save_recovery_or_document();
        app.settings.last_document = app.document.path.clone();
        app.settings.save();
        glib::Propagation::Proceed
    });

    window.present();
    let fullscreen_state = state.clone();
    glib::idle_add_local_once(move || {
        let mut app = fullscreen_state.borrow_mut();
        app.window.fullscreen();
        app.is_fullscreen = true;
        app.editor.grab_focus();
    });
}

fn install_keyboard_shortcuts(state: &Rc<RefCell<AppState>>) {
    let controller = gtk::EventControllerKey::new();
    controller.set_propagation_phase(gtk::PropagationPhase::Capture);
    let key_state = state.clone();
    controller.connect_key_pressed(move |_, key, _, modifiers| {
        let control = modifiers.contains(gdk::ModifierType::CONTROL_MASK);
        let shift = modifiers.contains(gdk::ModifierType::SHIFT_MASK);
        let character = key
            .to_unicode()
            .map(|character| character.to_ascii_lowercase());

        if key == gdk::Key::F11 {
            toggle_fullscreen(&key_state);
            return glib::Propagation::Stop;
        }
        if key == gdk::Key::Escape {
            exit_fullscreen(&key_state);
            return glib::Propagation::Stop;
        }

        if control {
            match character {
                Some('n') => new_document(&key_state),
                Some('o') => show_open_dialog(&key_state),
                Some('s') if shift => show_save_dialog(&key_state),
                Some('s') => save_document(&key_state),
                Some('f') => show_find_dialog(&key_state),
                Some('h') if shift => show_history_dialog(&key_state),
                Some('p') if shift => show_command_palette(&key_state),
                Some(',') => show_settings_dialog(&key_state),
                Some('z') if shift => redo(&key_state),
                Some('z') => undo(&key_state),
                Some('y') => redo(&key_state),
                _ => return glib::Propagation::Proceed,
            }
            return glib::Propagation::Stop;
        }

        let key_sound_enabled = key_state.borrow().settings.key_sound_enabled;
        if key_sound_enabled && should_play_key_sound(key, modifiers) {
            key_state.borrow_mut().key_sound.play();
        }
        glib::Propagation::Proceed
    });
    state.borrow().window.add_controller(controller);
}

fn should_play_key_sound(key: gdk::Key, modifiers: gdk::ModifierType) -> bool {
    if modifiers.intersects(
        gdk::ModifierType::CONTROL_MASK
            | gdk::ModifierType::ALT_MASK
            | gdk::ModifierType::SUPER_MASK,
    ) {
        return false;
    }
    matches!(
        key,
        gdk::Key::BackSpace | gdk::Key::Return | gdk::Key::KP_Enter | gdk::Key::space
    ) || key.to_unicode().is_some()
}

fn apply_settings(state: &Rc<RefCell<AppState>>) {
    let (palette, font, provider) = {
        let app = state.borrow();
        (
            app.settings.theme.palette(),
            app.settings.font.name(),
            app.css_provider.clone(),
        )
    };
    let css = format!(
        r#"
        window.plaintext-window, .plaintext-root, dialog, .background {{ background-color: {background}; color: {foreground}; }}
        .document-title, .word-count {{ color: {secondary}; font-size: 11px; font-weight: 600; }}
        textview.editor, textview.editor text {{
            background-color: {background}; color: {foreground}; caret-color: {foreground};
            font-family: \"{font}\"; font-size: 19pt;
        }}
        textview.editor selection {{ background-color: {selection}; color: {foreground}; }}
        entry, combobox, listview, listbox {{ background-color: {background}; color: {foreground}; }}
        button {{ color: {foreground}; background-color: transparent; border-color: {secondary}; }}
        "#,
        background = palette.background,
        foreground = palette.foreground,
        secondary = palette.secondary,
        selection = palette.selection,
        font = font,
    );
    provider.load_from_data(&css);
    update_word_count(state);
}

fn save_settings(state: &Rc<RefCell<AppState>>) {
    let mut app = state.borrow_mut();
    app.settings.last_document = app.document.path.clone();
    app.settings.save();
}

fn synchronise_editor_from_document(state: &Rc<RefCell<AppState>>) {
    let (editor, text) = {
        let app = state.borrow();
        (app.editor.clone(), app.document.text.clone())
    };
    state.borrow_mut().synchronising = true;
    let buffer = editor.buffer();
    buffer.set_text(&text);
    let start = buffer.start_iter();
    buffer.place_cursor(&start);
    state.borrow_mut().synchronising = false;
    update_title(state);
    update_word_count(state);
    editor.grab_focus();
}

fn update_title(state: &Rc<RefCell<AppState>>) {
    let (title, display_title, window) = {
        let app = state.borrow();
        (
            app.title.clone(),
            app.document.display_title(),
            app.window.clone(),
        )
    };
    title.set_label(&display_title);
    window.set_title(Some(&format!("Plaintext — {display_title}")));
}

fn update_word_count(state: &Rc<RefCell<AppState>>) {
    let (label, visible, text) = {
        let app = state.borrow();
        (
            app.word_count.clone(),
            app.settings.shows_word_count,
            app.document.text.clone(),
        )
    };
    label.set_visible(visible);
    if visible {
        let count = text.split_whitespace().count();
        label.set_label(&format!(
            "{count} {}",
            if count == 1 { "word" } else { "words" }
        ));
    }
}

fn schedule_persistence(state: &Rc<RefCell<AppState>>) {
    if let Some(source) = state.borrow_mut().save_source.take() {
        source.remove();
    }
    let save_state = state.clone();
    let source = glib::timeout_add_local_once(Duration::from_secs(1), move || {
        let mut app = save_state.borrow_mut();
        app.save_source = None;
        app.document.save_recovery_or_document();
        app.settings.last_document = app.document.path.clone();
        app.settings.save();
        drop(app);
        update_title(&save_state);
    });
    state.borrow_mut().save_source = Some(source);
}

fn new_document(state: &Rc<RefCell<AppState>>) {
    {
        let mut app = state.borrow_mut();
        app.document.new_document();
        app.settings.last_document = None;
        app.settings.save();
        app.document.save_recovery_or_document();
    }
    synchronise_editor_from_document(state);
}

fn show_open_dialog(state: &Rc<RefCell<AppState>>) {
    let window = state.borrow().window.clone();
    let dialog = gtk::FileChooserDialog::builder()
        .title("Open a document — it will replace the current one")
        .transient_for(&window)
        .modal(true)
        .action(gtk::FileChooserAction::Open)
        .build();
    dialog.add_button("Cancel", gtk::ResponseType::Cancel);
    dialog.add_button("Open", gtk::ResponseType::Accept);
    let filter = gtk::FileFilter::new();
    filter.set_name(Some("Plain text (*.md, *.txt)"));
    filter.add_pattern("*.md");
    filter.add_pattern("*.txt");
    dialog.add_filter(&filter);

    let open_state = state.clone();
    dialog.connect_response(move |dialog, response| {
        if response == gtk::ResponseType::Accept {
            if let Some(path) = dialog.file().and_then(|file| file.path()) {
                open_document(&open_state, path);
            }
        }
        dialog.close();
    });
    dialog.present();
}

fn open_document(state: &Rc<RefCell<AppState>>, path: PathBuf) {
    let result = state.borrow_mut().document.open(&path);
    if let Err(message) = result {
        show_error(state, &message);
        return;
    }
    save_settings(state);
    synchronise_editor_from_document(state);
}

fn save_document(state: &Rc<RefCell<AppState>>) {
    if state.borrow().document.path.is_none() {
        show_save_dialog(state);
        return;
    }
    let result = state.borrow_mut().document.save(None);
    if let Err(message) = result {
        show_error(state, &message);
        return;
    }
    save_settings(state);
    update_title(state);
}

fn show_save_dialog(state: &Rc<RefCell<AppState>>) {
    let (window, filename) = {
        let app = state.borrow();
        (
            app.window.clone(),
            app.document
                .path
                .as_ref()
                .and_then(|path| path.file_name())
                .map(|name| name.to_string_lossy().into_owned())
                .unwrap_or_else(|| "Untitled.md".into()),
        )
    };
    let dialog = gtk::FileChooserDialog::builder()
        .title("Save a plain text document")
        .transient_for(&window)
        .modal(true)
        .action(gtk::FileChooserAction::Save)
        .build();
    dialog.add_button("Cancel", gtk::ResponseType::Cancel);
    dialog.add_button("Save", gtk::ResponseType::Accept);
    dialog.set_current_name(&filename);
    let filter = gtk::FileFilter::new();
    filter.set_name(Some("Markdown (*.md)"));
    filter.add_pattern("*.md");
    dialog.add_filter(&filter);

    let save_state = state.clone();
    dialog.connect_response(move |dialog, response| {
        if response == gtk::ResponseType::Accept {
            if let Some(path) = dialog.file().and_then(|file| file.path()) {
                let path = if path.extension().is_none() {
                    path.with_extension("md")
                } else {
                    path
                };
                let result = save_state.borrow_mut().document.save(Some(path));
                if let Err(message) = result {
                    show_error(&save_state, &message);
                } else {
                    save_settings(&save_state);
                    update_title(&save_state);
                }
            }
        }
        dialog.close();
    });
    dialog.present();
}

fn undo(state: &Rc<RefCell<AppState>>) {
    if state.borrow_mut().document.undo().is_some() {
        synchronise_editor_from_document(state);
        schedule_persistence(state);
    }
}

fn redo(state: &Rc<RefCell<AppState>>) {
    if state.borrow_mut().document.redo().is_some() {
        synchronise_editor_from_document(state);
        schedule_persistence(state);
    }
}

fn show_find_dialog(state: &Rc<RefCell<AppState>>) {
    let window = state.borrow().window.clone();
    let dialog = gtk::Dialog::builder()
        .title("Find and replace")
        .transient_for(&window)
        .modal(true)
        .build();
    dialog.add_button("Close", gtk::ResponseType::Close);
    let content = dialog.content_area();
    content.set_spacing(8);
    content.set_margin_top(16);
    content.set_margin_bottom(16);
    content.set_margin_start(18);
    content.set_margin_end(18);

    let find = gtk::Entry::new();
    find.set_placeholder_text(Some("Find"));
    let replacement = gtk::Entry::new();
    replacement.set_placeholder_text(Some("Replace"));
    let buttons = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let next = gtk::Button::with_label("Next");
    let replace = gtk::Button::with_label("Replace");
    let replace_all_button = gtk::Button::with_label("All");
    buttons.append(&next);
    buttons.append(&replace);
    buttons.append(&replace_all_button);
    content.append(&find);
    content.append(&replacement);
    content.append(&buttons);

    let next_state = state.clone();
    let next_find = find.clone();
    next.connect_clicked(move |_| find_next(&next_state, &next_find.text()));
    let entry_state = state.clone();
    let entry_find = find.clone();
    find.connect_activate(move |_| find_next(&entry_state, &entry_find.text()));
    let replace_state = state.clone();
    let replace_find = find.clone();
    let replace_replacement = replacement.clone();
    replace.connect_clicked(move |_| {
        replace_current(
            &replace_state,
            &replace_find.text(),
            &replace_replacement.text(),
        )
    });
    let all_state = state.clone();
    let all_find = find.clone();
    let all_replacement = replacement.clone();
    replace_all_button.connect_clicked(move |_| {
        replace_all(&all_state, &all_find.text(), &all_replacement.text())
    });
    dialog.connect_response(|dialog, _| dialog.close());
    dialog.present();
    find.grab_focus();
}

fn find_next(state: &Rc<RefCell<AppState>>, query: &str) {
    if query.is_empty() {
        return;
    }
    let editor = state.borrow().editor.clone();
    let buffer = editor.buffer();
    let cursor = buffer.iter_at_offset(buffer.cursor_position());
    let match_range = cursor
        .forward_search(query, gtk::TextSearchFlags::CASE_INSENSITIVE, None)
        .or_else(|| {
            buffer
                .start_iter()
                .forward_search(query, gtk::TextSearchFlags::CASE_INSENSITIVE, None)
        });
    if let Some((mut start, end)) = match_range {
        buffer.select_range(&start, &end);
        editor.scroll_to_iter(&mut start, 0.2, false, 0.0, 0.0);
        editor.grab_focus();
    } else {
        show_error(state, &format!("No matches for “{query}”."));
    }
}

fn replace_current(state: &Rc<RefCell<AppState>>, query: &str, replacement: &str) {
    if query.is_empty() {
        return;
    }
    let buffer = state.borrow().editor.buffer();
    if let Some((mut start, mut end)) = buffer.selection_bounds() {
        if buffer.text(&start, &end, true).eq_ignore_ascii_case(query) {
            buffer.begin_user_action();
            buffer.delete(&mut start, &mut end);
            buffer.insert(&mut start, replacement);
            buffer.end_user_action();
        }
    }
    find_next(state, query);
}

fn replace_all(state: &Rc<RefCell<AppState>>, query: &str, replacement: &str) {
    if query.is_empty() {
        return;
    }
    let text = state.borrow().document.text.clone();
    let Ok(pattern) = RegexBuilder::new(&regex::escape(query))
        .case_insensitive(true)
        .build()
    else {
        return;
    };
    let updated = pattern.replace_all(&text, replacement).into_owned();
    if updated == text {
        show_error(state, &format!("No matches for “{query}”."));
        return;
    }
    state.borrow_mut().document.set_text_from_editor(updated);
    synchronise_editor_from_document(state);
    schedule_persistence(state);
}

fn show_settings_dialog(state: &Rc<RefCell<AppState>>) {
    let window = state.borrow().window.clone();
    let dialog = gtk::Dialog::builder()
        .title("Settings")
        .transient_for(&window)
        .modal(true)
        .default_width(460)
        .build();
    dialog.add_button("Done", gtk::ResponseType::Close);
    let content = dialog.content_area();
    content.set_spacing(14);
    content.set_margin_top(20);
    content.set_margin_bottom(20);
    content.set_margin_start(24);
    content.set_margin_end(24);

    let theme_label = gtk::Label::new(Some("Theme"));
    theme_label.set_halign(gtk::Align::Start);
    content.append(&theme_label);
    let themes = gtk::Box::new(gtk::Orientation::Horizontal, 5);
    for theme in EditorTheme::ALL {
        let button = gtk::Button::with_label(theme.name());
        let theme_state = state.clone();
        button.connect_clicked(move |_| {
            theme_state.borrow_mut().settings.theme = theme;
            save_settings(&theme_state);
            apply_settings(&theme_state);
        });
        themes.append(&button);
    }
    content.append(&themes);

    let font_label = gtk::Label::new(Some("Typeface"));
    font_label.set_halign(gtk::Align::Start);
    content.append(&font_label);
    let fonts = gtk::ComboBoxText::new();
    let active_font = state.borrow().settings.font;
    for (index, font) in FontChoice::ALL.iter().enumerate() {
        fonts.append_text(font.name());
        if *font == active_font {
            fonts.set_active(Some(index as u32));
        }
    }
    let font_state = state.clone();
    fonts.connect_changed(move |picker| {
        let Some(index) = picker.active() else { return };
        font_state.borrow_mut().settings.font = FontChoice::ALL[index as usize];
        save_settings(&font_state);
        apply_settings(&font_state);
    });
    content.append(&fonts);

    let key_sound = gtk::CheckButton::with_label("Key sound");
    key_sound.set_active(state.borrow().settings.key_sound_enabled);
    let key_sound_state = state.clone();
    key_sound.connect_toggled(move |toggle| {
        key_sound_state.borrow_mut().settings.key_sound_enabled = toggle.is_active();
        save_settings(&key_sound_state);
    });
    content.append(&key_sound);

    let word_count = gtk::CheckButton::with_label("Show word count");
    word_count.set_active(state.borrow().settings.shows_word_count);
    let word_count_state = state.clone();
    word_count.connect_toggled(move |toggle| {
        word_count_state.borrow_mut().settings.shows_word_count = toggle.is_active();
        save_settings(&word_count_state);
        update_word_count(&word_count_state);
    });
    content.append(&word_count);

    dialog.connect_response(|dialog, _| dialog.close());
    dialog.present();
}

fn show_history_dialog(state: &Rc<RefCell<AppState>>) {
    let window = state.borrow().window.clone();
    let snapshots = state.borrow().document.history();
    let dialog = gtk::Dialog::builder()
        .title("Earlier Versions")
        .transient_for(&window)
        .modal(true)
        .default_width(520)
        .default_height(400)
        .build();
    dialog.add_button("Done", gtk::ResponseType::Close);
    let content = dialog.content_area();
    content.set_spacing(10);
    content.set_margin_top(18);
    content.set_margin_bottom(18);
    content.set_margin_start(22);
    content.set_margin_end(22);
    let description = gtk::Label::new(Some(
        "Automatic local snapshots. Restoring one replaces the current document.",
    ));
    description.set_wrap(true);
    description.set_halign(gtk::Align::Start);
    content.append(&description);
    let chooser = gtk::ComboBoxText::new();
    for snapshot in &snapshots {
        chooser.append_text(&snapshot.display_name);
    }
    if !snapshots.is_empty() {
        chooser.set_active(Some(0));
    }
    content.append(&chooser);
    let restore = gtk::Button::with_label("Restore");
    let restore_state = state.clone();
    restore.connect_clicked(move |_| restore_history(&restore_state, &snapshots, chooser.active()));
    content.append(&restore);
    dialog.connect_response(|dialog, _| dialog.close());
    dialog.present();
}

fn restore_history(
    state: &Rc<RefCell<AppState>>,
    snapshots: &[HistorySnapshot],
    active: Option<u32>,
) {
    let Some(snapshot) = active.and_then(|index| snapshots.get(index as usize)) else {
        return;
    };
    let result = state.borrow_mut().document.restore(snapshot);
    if let Err(message) = result {
        show_error(state, &message);
        return;
    }
    synchronise_editor_from_document(state);
    schedule_persistence(state);
}

fn show_command_palette(state: &Rc<RefCell<AppState>>) {
    let window = state.borrow().window.clone();
    let dialog = gtk::Dialog::builder()
        .title("Command Palette")
        .transient_for(&window)
        .modal(true)
        .default_width(420)
        .build();
    let content = dialog.content_area();
    content.set_spacing(5);
    content.set_margin_top(12);
    content.set_margin_bottom(12);
    content.set_margin_start(12);
    content.set_margin_end(12);
    let prompt = gtk::Label::new(Some("Choose a command"));
    prompt.set_halign(gtk::Align::Start);
    content.append(&prompt);

    add_command(&content, "Open document", state, &dialog, show_open_dialog);
    add_command(&content, "Save as", state, &dialog, show_save_dialog);
    add_command(
        &content,
        "Find and replace",
        state,
        &dialog,
        show_find_dialog,
    );
    add_command(
        &content,
        "Restore earlier version",
        state,
        &dialog,
        show_history_dialog,
    );
    add_command(&content, "Settings", state, &dialog, show_settings_dialog);
    add_command(
        &content,
        "Toggle fullscreen",
        state,
        &dialog,
        toggle_fullscreen,
    );

    let word_count = gtk::Button::with_label(if state.borrow().settings.shows_word_count {
        "Hide word count"
    } else {
        "Show word count"
    });
    let count_state = state.clone();
    let count_dialog = dialog.clone();
    word_count.connect_clicked(move |_| {
        {
            let mut app = count_state.borrow_mut();
            app.settings.shows_word_count = !app.settings.shows_word_count;
        }
        save_settings(&count_state);
        update_word_count(&count_state);
        count_dialog.close();
    });
    content.append(&word_count);
    dialog.connect_response(|dialog, _| dialog.close());
    dialog.present();
}

fn add_command(
    content: &gtk::Box,
    title: &str,
    state: &Rc<RefCell<AppState>>,
    dialog: &gtk::Dialog,
    action: fn(&Rc<RefCell<AppState>>),
) {
    let button = gtk::Button::with_label(title);
    let action_state = state.clone();
    let action_dialog = dialog.clone();
    button.connect_clicked(move |_| {
        action_dialog.close();
        action(&action_state);
    });
    content.append(&button);
}

fn toggle_fullscreen(state: &Rc<RefCell<AppState>>) {
    if state.borrow().is_fullscreen {
        exit_fullscreen(state);
    } else {
        let mut app = state.borrow_mut();
        app.window.fullscreen();
        app.is_fullscreen = true;
    }
}

fn exit_fullscreen(state: &Rc<RefCell<AppState>>) {
    if !state.borrow().is_fullscreen {
        return;
    }
    let mut app = state.borrow_mut();
    app.window.unfullscreen();
    app.is_fullscreen = false;
}

fn show_error(state: &Rc<RefCell<AppState>>, message: &str) {
    let window = state.borrow().window.clone();
    let dialog = gtk::Dialog::builder()
        .title("Plaintext")
        .transient_for(&window)
        .modal(true)
        .build();
    dialog.add_button("OK", gtk::ResponseType::Close);
    let content = dialog.content_area();
    content.set_margin_top(18);
    content.set_margin_bottom(18);
    content.set_margin_start(22);
    content.set_margin_end(22);
    let label = gtk::Label::new(Some(message));
    label.set_wrap(true);
    content.append(&label);
    dialog.connect_response(|dialog, _| dialog.close());
    dialog.present();
}

fn buffer_text(buffer: &gtk::TextBuffer) -> String {
    let (start, end) = buffer.bounds();
    buffer.text(&start, &end, true).into()
}
