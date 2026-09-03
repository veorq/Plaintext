#!/usr/bin/env sh
set -eu

usage() {
    cat <<'EOF'
Usage: ./install-linux.sh [--user | --system] [--prefix PATH]

Install Plaintext and its Linux desktop resources.

  --user          Install under ~/.local (the default)
  --system        Install under /usr/local
  --prefix PATH   Install under a custom prefix
  -h, --help      Show this help

DESTDIR may be set by package builders to stage an installation.
EOF
}

prefix=${HOME:?HOME is not set}/.local
while [ "$#" -gt 0 ]; do
    case $1 in
        --user) prefix=${HOME:?HOME is not set}/.local ;;
        --system) prefix=/usr/local ;;
        --prefix)
            [ "$#" -ge 2 ] || { echo "install-linux.sh: --prefix requires a path" >&2; exit 2; }
            prefix=$2
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "install-linux.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -x "$script_dir/Plaintext" ] && [ -d "$script_dir/fonts" ]; then
    binary=$script_dir/Plaintext
    resources=$script_dir
elif [ -x "$script_dir/Linux/target/release/Plaintext" ]; then
    binary=$script_dir/Linux/target/release/Plaintext
    resources=$script_dir/Linux/resources
else
    echo "install-linux.sh: no release binary found" >&2
    echo "Run ./build-linux.sh VERSION first, or run this script from an unpacked release." >&2
    exit 1
fi

destdir=${DESTDIR-}
bindir=$destdir$prefix/bin
datadir=$destdir$prefix/share
appdir=$datadir/plaintext

install -d "$bindir" "$appdir/fonts" "$datadir/applications" \
    "$datadir/icons/hicolor/512x512/apps" "$datadir/metainfo"
install -m 755 "$binary" "$bindir/Plaintext"
for font in "$resources/fonts/"*.ttf; do
    install -m 644 "$font" "$appdir/fonts/$(basename -- "$font")"
done
install -m 644 "$resources/plaintext.desktop" "$datadir/applications/plaintext.desktop"
install -m 644 "$resources/plaintext.png" "$datadir/icons/hicolor/512x512/apps/plaintext.png"
install -m 644 "$resources/jp.aumasson.Plaintext.metainfo.xml" \
    "$datadir/metainfo/jp.aumasson.Plaintext.metainfo.xml"
install -m 755 "$script_dir/uninstall-linux.sh" "$appdir/uninstall.sh"

if [ -z "$destdir" ]; then
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database "$datadir/applications" >/dev/null 2>&1 || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -q -t "$datadir/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "Plaintext installed under $prefix"
case :$PATH: in
    *:"$prefix/bin":*) ;;
    *) echo "Add $prefix/bin to PATH to run Plaintext from a terminal." ;;
esac
echo "To uninstall: $prefix/share/plaintext/uninstall.sh --prefix '$prefix'"
