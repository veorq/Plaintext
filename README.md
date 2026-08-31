# Plaintext

A quiet, fullscreen-first editor for plain text.

- One document at a time
- Local autosave and version history
- No rich text, syntax highlighting, spellcheck, tabs, accounts, or network use

The beta runs on Apple Silicon Macs running macOS 14 or later, 64-bit Windows 10 or 11, and 64-bit Linux with GTK 4. The Windows beta is a self-contained executable and does not require a separate .NET installation.

## Build

On macOS, run `./build-app.sh`, then open `Plaintext.app`.

On Windows, run `dotnet build Windows/Plaintext.Windows.csproj --configuration Release`.

On Linux, install GTK 4 and Fontconfig development packages, then run `cargo run --manifest-path Linux/Cargo.toml`.

The Linux release archive contains the executable, bundled fonts, icon, and desktop launcher. Run `Plaintext/Plaintext` from the unpacked archive.

## License

Plaintext is released under the MIT License. The bundled typefaces are released under the SIL Open Font License, Version 1.1; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
