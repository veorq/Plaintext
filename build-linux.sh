#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
version=${1:?"Usage: ./build-linux.sh v0.1.0-beta.9"}
stage_dir="$project_dir/Linux/dist/Plaintext"
archive_dir="$project_dir/Linux/dist"

cargo build --manifest-path "$project_dir/Linux/Cargo.toml" --release --locked

mkdir -p "$stage_dir/fonts" "$stage_dir/ThirdPartyLicenses"
cp "$project_dir/Linux/target/release/Plaintext" "$stage_dir/Plaintext"
cp "$project_dir/Linux/resources/plaintext.desktop" "$stage_dir/plaintext.desktop"
cp "$project_dir/Linux/resources/plaintext.png" "$stage_dir/plaintext.png"
cp "$project_dir/Linux/resources/jp.aumasson.Plaintext.metainfo.xml" "$stage_dir/jp.aumasson.Plaintext.metainfo.xml"
cp "$project_dir/install-linux.sh" "$stage_dir/install-linux.sh"
cp "$project_dir/uninstall-linux.sh" "$stage_dir/uninstall-linux.sh"
chmod 755 "$stage_dir/install-linux.sh" "$stage_dir/uninstall-linux.sh"
cp "$project_dir/Linux/resources/fonts/"*.ttf "$stage_dir/fonts/"
cp "$project_dir/LICENSE" "$stage_dir/LICENSE"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$stage_dir/THIRD_PARTY_NOTICES.md"
cp "$project_dir/ThirdPartyLicenses/"*.txt "$stage_dir/ThirdPartyLicenses/"

archive="$archive_dir/Plaintext-${version}-linux-x86_64.tar.gz"
tar -C "$archive_dir" -czf "$archive" Plaintext
sha256sum "$archive" > "$archive.sha256"

printf 'Built %s\n' "$archive"
