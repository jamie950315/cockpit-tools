#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname "$script_dir")
configuration=${CONFIGURATION:-release}
output_root=${OUTPUT_DIR:-"$project_dir/dist"}
bundle="$output_root/Codex Model Manager.app"
binary="$project_dir/.build/$configuration/CodexModelManager"

swift build --package-path "$project_dir" -c "$configuration"

rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary" "$bundle/Contents/MacOS/CodexModelManager"
cp "$project_dir/Resources/Info.plist" "$bundle/Contents/Info.plist"

identity=${CODE_SIGN_IDENTITY:--}
codesign --force --deep --timestamp=none --sign "$identity" "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"

printf '%s\n' "$bundle"
