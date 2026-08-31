use std::{
    fs,
    path::{Path, PathBuf},
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use crate::models::{support_directory, Settings};

#[derive(Clone)]
pub struct HistorySnapshot {
    pub path: PathBuf,
    pub display_name: String,
}

pub struct DocumentController {
    pub text: String,
    pub path: Option<PathBuf>,
    last_snapshot_text: String,
    undo_snapshots: Vec<String>,
    redo_snapshots: Vec<String>,
    last_undo_checkpoint: Option<Instant>,
}

impl DocumentController {
    pub fn restore_previous_session(settings: &Settings) -> Self {
        let mut document = Self::empty();
        if let Some(path) = settings.last_document.as_ref().filter(|path| path.exists()) {
            if document.open(path).is_ok() {
                return document;
            }
        }

        if let Ok(recovery) = fs::read_to_string(recovery_path()) {
            document.text = recovery;
        }
        document
    }

    pub fn empty() -> Self {
        Self {
            text: String::new(),
            path: None,
            last_snapshot_text: String::new(),
            undo_snapshots: Vec::new(),
            redo_snapshots: Vec::new(),
            last_undo_checkpoint: None,
        }
    }

    pub fn display_title(&self) -> String {
        self.path
            .as_ref()
            .and_then(|path| path.file_name())
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| "Untitled".into())
    }

    pub fn set_text_from_editor(&mut self, value: String) {
        if value == self.text {
            return;
        }
        self.record_undo_checkpoint(false);
        self.text = value;
    }

    pub fn new_document(&mut self) {
        self.path = None;
        self.text.clear();
        self.last_snapshot_text.clear();
        self.clear_undo_history();
    }

    pub fn open(&mut self, path: &Path) -> Result<(), String> {
        let text = fs::read_to_string(path).map_err(|_| {
            format!(
                "Plaintext could not open “{}”. Use UTF-8 plain text or Markdown.",
                path.file_name().unwrap_or_default().to_string_lossy()
            )
        })?;
        self.path = Some(path.to_path_buf());
        self.text = text.clone();
        self.last_snapshot_text = text;
        self.clear_undo_history();
        let _ = fs::remove_file(recovery_path());
        Ok(())
    }

    pub fn save(&mut self, path: Option<PathBuf>) -> Result<(), String> {
        let path = path
            .or_else(|| self.path.clone())
            .ok_or_else(|| "Choose a location before saving this document.".to_string())?;
        fs::write(&path, &self.text).map_err(|_| {
            format!(
                "Plaintext could not save “{}”.",
                path.file_name().unwrap_or_default().to_string_lossy()
            )
        })?;
        self.path = Some(path);
        self.write_snapshot_if_needed();
        let _ = fs::remove_file(recovery_path());
        Ok(())
    }

    pub fn save_recovery_or_document(&mut self) {
        if self.path.is_some() {
            let _ = self.save(None);
        } else {
            let _ = fs::create_dir_all(support_directory());
            let _ = fs::write(recovery_path(), &self.text);
        }
    }

    pub fn undo(&mut self) -> Option<String> {
        let previous = self.undo_snapshots.pop()?;
        self.redo_snapshots.push(self.text.clone());
        self.text = previous.clone();
        self.last_undo_checkpoint = None;
        Some(previous)
    }

    pub fn redo(&mut self) -> Option<String> {
        let next = self.redo_snapshots.pop()?;
        self.undo_snapshots.push(self.text.clone());
        self.text = next.clone();
        self.last_undo_checkpoint = None;
        Some(next)
    }

    pub fn history(&self) -> Vec<HistorySnapshot> {
        let Some(directory) = self.history_directory() else {
            return Vec::new();
        };
        let Ok(entries) = fs::read_dir(directory) else {
            return Vec::new();
        };

        let mut snapshots = entries
            .flatten()
            .map(|entry| entry.path())
            .filter(|path| path.extension().is_some_and(|extension| extension == "md"))
            .map(|path| HistorySnapshot {
                display_name: path
                    .file_stem()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .replace('T', " ")
                    .replace('-', ":"),
                path,
            })
            .collect::<Vec<_>>();
        snapshots.sort_by(|left, right| right.path.cmp(&left.path));
        snapshots
    }

    pub fn restore(&mut self, snapshot: &HistorySnapshot) -> Result<(), String> {
        let text = fs::read_to_string(&snapshot.path)
            .map_err(|_| "That earlier version is no longer available.".to_string())?;
        self.record_undo_checkpoint(true);
        self.text = text;
        Ok(())
    }

    fn record_undo_checkpoint(&mut self, force: bool) {
        let needs_checkpoint = force
            || self
                .last_undo_checkpoint
                .is_none_or(|checkpoint| checkpoint.elapsed() > Duration::from_millis(650));
        if needs_checkpoint && self.undo_snapshots.last() != Some(&self.text) {
            self.undo_snapshots.push(self.text.clone());
            if self.undo_snapshots.len() > 200 {
                self.undo_snapshots.remove(0);
            }
        }
        self.redo_snapshots.clear();
        self.last_undo_checkpoint = Some(Instant::now());
    }

    fn clear_undo_history(&mut self) {
        self.undo_snapshots.clear();
        self.redo_snapshots.clear();
        self.last_undo_checkpoint = None;
    }

    fn history_directory(&self) -> Option<PathBuf> {
        let path = self.path.as_ref()?;
        let directory = support_directory()
            .join("History")
            .join(format!("{:x}", fnv1a64(&path.to_string_lossy())));
        let _ = fs::create_dir_all(&directory);
        Some(directory)
    }

    fn write_snapshot_if_needed(&mut self) {
        if self.text == self.last_snapshot_text {
            return;
        }
        let Some(directory) = self.history_directory() else {
            return;
        };
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_millis())
            .unwrap_or_default();
        let path = directory.join(format!("{timestamp}.md"));
        if fs::write(path, &self.text).is_ok() {
            self.last_snapshot_text = self.text.clone();
            for snapshot in self.history().into_iter().skip(80) {
                let _ = fs::remove_file(snapshot.path);
            }
        }
    }
}

fn recovery_path() -> PathBuf {
    support_directory().join("recovery.md")
}

fn fnv1a64(value: &str) -> u64 {
    value
        .bytes()
        .fold(14_695_981_039_346_656_037, |hash, byte| {
            (hash ^ u64::from(byte)).wrapping_mul(1_099_511_628_211)
        })
}
