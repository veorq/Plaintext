#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
build_dir="$project_dir/.build/release"
app_dir="$project_dir/Plaintext.app"
module_cache="$project_dir/.build/module-cache"

cd "$project_dir"
mkdir -p "$module_cache"
CLANG_MODULE_CACHE_PATH="$module_cache" swift build -c release --disable-sandbox

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/Plaintext" "$app_dir/Contents/MacOS/Plaintext"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/Plaintext.icns" "$app_dir/Contents/Resources/Plaintext.icns"
cp -R "$project_dir/Resources/Fonts" "$app_dir/Contents/Resources/Fonts"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$project_dir/ThirdPartyLicenses" "$app_dir/Contents/Resources/ThirdPartyLicenses"
codesign --force --sign - --entitlements "$project_dir/Resources/Plaintext.entitlements" "$app_dir"
printf 'Built %s\n' "$app_dir"
