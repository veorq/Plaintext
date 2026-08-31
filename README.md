# Plaintext

A quiet, fullscreen-first editor for plain text.

- One document at a time
- Local autosave and version history
- No rich text, syntax highlighting, spellcheck, tabs, accounts, or network use

The beta runs on Apple Silicon Macs running macOS 14 or later, 64-bit Windows 10 or 11, and 64-bit Linux with GTK 4. The Windows beta is a self-contained executable and does not require a separate .NET installation.

## Build from source

Plaintext has separate native applications for each platform. The `Package.swift` file at the repository root is the **macOS-only** AppKit application; do not run `swift build` on Linux.

- macOS: run `./build-app.sh`, then open `Plaintext.app`.
- Windows: run `dotnet build Windows/Plaintext.Windows.csproj --configuration Release`.
- Linux: install the Rust toolchain plus GTK 4 and Fontconfig development packages, then run `cargo run --manifest-path Linux/Cargo.toml`.

  On Ubuntu or Debian: `sudo apt install libgtk-4-dev libfontconfig1-dev`.

The Linux release archive contains the executable, bundled fonts, icon, and desktop launcher. Run `Plaintext/Plaintext` from the unpacked archive.

## License

Plaintext is released under the MIT License. The bundled typefaces are released under the SIL Open Font License, Version 1.1; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
