use std::{
    env,
    ffi::{c_char, c_int, c_void, CString},
    path::PathBuf,
};

#[link(name = "fontconfig")]
extern "C" {
    fn FcConfigGetCurrent() -> *mut c_void;
    fn FcConfigAppFontAddFile(config: *mut c_void, file: *const c_char) -> c_int;
}

pub fn register_bundled_fonts() {
    let config = unsafe { FcConfigGetCurrent() };
    if config.is_null() {
        return;
    }

    for filename in [
        "Literata-Regular.ttf",
        "Newsreader-Regular.ttf",
        "WorkSans-Regular.ttf",
        "AtkinsonHyperlegible-Regular.ttf",
    ] {
        let path = resource_directory().join("fonts").join(filename);
        let Ok(path) = CString::new(path.to_string_lossy().as_bytes()) else {
            continue;
        };
        unsafe {
            FcConfigAppFontAddFile(config, path.as_ptr());
        }
    }
}

pub fn resource_directory() -> PathBuf {
    if let Some(directory) = env::var_os("PLAINTEXT_RESOURCE_DIR") {
        return PathBuf::from(directory);
    }

    if let Ok(executable) = env::current_exe() {
        if let Some(directory) = executable.parent() {
            let bundled = directory.join("fonts");
            if bundled.is_dir() {
                return directory.to_path_buf();
            }
        }
    }

    let development_resources = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("resources");
    if development_resources.join("fonts").is_dir() {
        return development_resources;
    }

    PathBuf::from("/usr/share/plaintext")
}
