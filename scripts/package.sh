#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'Usage: %s APP_PATH OUTPUT_DIR VERSION_LABEL\n' "$0" >&2
    exit 2
fi
app_path="$1"
output_dir="$2"
label="$3"
if [[ ! "$label" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-preview\.[0-9a-f]{12})?$ ]]; then
    printf 'Invalid version label: %s\n' "$label" >&2
    exit 2
fi
if [[ "$(basename "$app_path")" != 'EvenTone.app' || ! -f "$app_path/Contents/MacOS/EvenTone" ]]; then
    printf 'Expected a built EvenTone.app: %s\n' "$app_path" >&2
    exit 2
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
if [[ "${label%%-preview.*}" != "$version" ]]; then
    printf 'Package label does not match app version %s\n' "$version" >&2
    exit 2
fi
arch=$(lipo -archs "$app_path/Contents/MacOS/EvenTone")
if [[ "$arch" != 'arm64' ]]; then
    printf 'This release workflow currently supports arm64; got %s\n' "$arch" >&2
    exit 2
fi
codesign --verify --deep --strict "$app_path"
mkdir -p "$output_dir"
archive="EvenTone-${label}-macOS-arm64.zip"
if [[ -e "$output_dir/$archive" || -e "$output_dir/SHA256SUMS.txt" ]]; then
    printf 'Output already exists; use an empty output directory\n' >&2
    exit 2
fi
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_dir/$archive"
(
    cd "$output_dir"
    shasum -a 256 "$archive" > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
printf 'Packaged: %s/%s\n' "$output_dir" "$archive"
