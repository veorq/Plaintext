#!/usr/bin/env sh
set -eu

usage() {
    cat <<'EOF'
Usage: ./uninstall-linux.sh [--user | --system] [--prefix PATH]

Remove files installed by install-linux.sh.

  --user          Remove the installation under ~/.local (the default)
  --system        Remove the installation under /usr/local
  --prefix PATH   Remove an installation under a custom prefix
  -h, --help      Show this help

DESTDIR may be set by package builders to remove a staged installation.
EOF
}

prefix=${HOME:?HOME is not set}/.local
while [ "$#" -gt 0 ]; do
    case $1 in
        --user) prefix=${HOME:?HOME is not set}/.local ;;
        --system) prefix=/usr/local ;;
        --prefix)
            [ "$#" -ge 2 ] || { echo "uninstall-linux.sh: --prefix requires a path" >&2; exit 2; }
            prefix=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "uninstall-linux.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

destdir=${DESTDIR-}
bindir=$destdir$prefix/bin
datadir=$destdir$prefix/share
appdir=$datadir/plaintext

rm -f -- "$bindir/Plaintext"
rm -f -- "$datadir/applications/plaintext.desktop"
rm -f -- "$datadir/icons/hicolor/512x512/apps/plaintext.png"
rm -f -- "$datadir/metainfo/jp.aumasson.Plaintext.metainfo.xml"
for font in AtkinsonHyperlegible-Regular.ttf Literata-Regular.ttf Newsreader-Regular.ttf WorkSans-Regular.ttf; do
    rm -f -- "$appdir/fonts/$font"
done
rm -f -- "$appdir/uninstall.sh"
rmdir "$appdir/fonts" "$appdir" 2>/dev/null || true

if [ -z "$destdir" ]; then
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$datadir/applications" >/dev/null 2>&1 || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -q -t "$datadir/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "Plaintext removed from $prefix"
