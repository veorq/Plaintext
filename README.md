# Plaintext

A quiet, fullscreen-first editor for plain text.

- One document at a time
- Local autosave and version history
- No rich text, syntax highlighting, spellcheck, tabs, accounts, or network use

The first beta is for Apple Silicon Macs running macOS 14 or later. A native Windows version lives in `Windows/` and is being prepared for its first beta.

## Build

On macOS, run `./build-app.sh`, then open `Plaintext.app`.

On Windows, run `dotnet build Windows/Plaintext.Windows.csproj --configuration Release`.

Plaintext is currently distributed without a license; all rights reserved.
