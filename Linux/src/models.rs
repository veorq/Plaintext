use std::{env, fs, path::PathBuf};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EditorTheme {
    Paper,
    Snow,
    Linen,
    Ink,
    Graphite,
    Midnight,
}

impl EditorTheme {
    pub const ALL: [Self; 6] = [
        Self::Paper,
        Self::Snow,
        Self::Linen,
        Self::Ink,
        Self::Graphite,
        Self::Midnight,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Self::Paper => "Paper",
            Self::Snow => "Snow",
            Self::Linen => "Linen",
            Self::Ink => "Ink",
            Self::Graphite => "Graphite",
            Self::Midnight => "Midnight",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Paper => "paper",
            Self::Snow => "snow",
            Self::Linen => "linen",
            Self::Ink => "ink",
            Self::Graphite => "graphite",
            Self::Midnight => "midnight",
        }
    }

    pub fn from_key(value: &str) -> Self {
        Self::ALL
            .into_iter()
            .find(|theme| theme.key() == value)
            .unwrap_or(Self::Paper)
    }

    pub fn palette(self) -> ThemePalette {
        match self {
            Self::Paper => ThemePalette::new("#F6F3EC", "#211F1A", "#666157", "#CCC5AD"),
            Self::Snow => ThemePalette::new("#FFFFFF", "#0D0D0D", "#575757", "#B8CFF5"),
            Self::Linen => ThemePalette::new("#E8E0D1", "#38332C", "#70695C", "#C2B399"),
            Self::Ink => ThemePalette::new("#0E0F11", "#F0F0EB", "#9E9F9C", "#3D5775"),
            Self::Graphite => ThemePalette::new("#21211F", "#C2C0B8", "#85827A", "#4F4D45"),
            Self::Midnight => ThemePalette::new("#0F161C", "#C7D4DC", "#7A8E9C", "#2C4857"),
        }
    }
}

#[derive(Clone, Copy)]
pub struct ThemePalette {
    pub background: &'static str,
    pub foreground: &'static str,
    pub secondary: &'static str,
    pub selection: &'static str,
}

impl ThemePalette {
    const fn new(
        background: &'static str,
        foreground: &'static str,
        secondary: &'static str,
        selection: &'static str,
    ) -> Self {
        Self {
            background,
            foreground,
            secondary,
            selection,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FontChoice {
    Literata,
    Newsreader,
    WorkSans,
    AtkinsonHyperlegible,
}

impl FontChoice {
    pub const ALL: [Self; 4] = [
        Self::Literata,
        Self::Newsreader,
        Self::WorkSans,
        Self::AtkinsonHyperlegible,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Self::Literata => "Literata",
            Self::Newsreader => "Newsreader",
            Self::WorkSans => "Work Sans",
            Self::AtkinsonHyperlegible => "Atkinson Hyperlegible",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Literata => "literata",
            Self::Newsreader => "newsreader",
            Self::WorkSans => "work-sans",
            Self::AtkinsonHyperlegible => "atkinson-hyperlegible",
        }
    }

    pub fn from_key(value: &str) -> Self {
        Self::ALL
            .into_iter()
            .find(|font| font.key() == value)
            .unwrap_or(Self::Literata)
    }
}

#[derive(Clone)]
pub struct Settings {
    pub theme: EditorTheme,
    pub font: FontChoice,
    pub key_sound_enabled: bool,
    pub shows_word_count: bool,
    pub last_document: Option<PathBuf>,
}

impl Settings {
    pub fn load() -> Self {
        let mut settings = Self {
            theme: EditorTheme::Paper,
            font: FontChoice::Literata,
            key_sound_enabled: false,
            shows_word_count: false,
            last_document: None,
        };

        let Ok(content) = fs::read_to_string(settings_path()) else {
            return settings;
        };

        for line in content.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            match key {
                "theme" => settings.theme = EditorTheme::from_key(value),
                "font" => settings.font = FontChoice::from_key(value),
                "key_sound" => settings.key_sound_enabled = value == "true",
                "word_count" => settings.shows_word_count = value == "true",
                "last_document" if !value.is_empty() => {
                    settings.last_document = Some(PathBuf::from(value))
                }
                _ => {}
            }
        }
        settings
    }

    pub fn save(&self) {
        let path = settings_path();
        let Some(parent) = path.parent() else {
            return;
        };
        if fs::create_dir_all(parent).is_err() {
            return;
        }

        let last_document = self
            .last_document
            .as_ref()
            .map(|path| path.to_string_lossy())
            .unwrap_or_default();
        let content = format!(
            "theme={}\nfont={}\nkey_sound={}\nword_count={}\nlast_document={}\n",
            self.theme.key(),
            self.font.key(),
            self.key_sound_enabled,
            self.shows_word_count,
            last_document
        );
        let _ = fs::write(path, content);
    }
}

pub fn support_directory() -> PathBuf {
    data_home().join("Plaintext")
}

fn settings_path() -> PathBuf {
    config_home().join("Plaintext/settings")
}

fn data_home() -> PathBuf {
    env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_directory().join(".local/share"))
}

fn config_home() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_directory().join(".config"))
}

fn home_directory() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}
