#!/bin/zsh
# Builds an AU shim for a legacy plug-in described by configs/<Name>.plist.
#
#   ./build.sh [Name]              build build/<Name>Shim.component (default: Geist2)
#   ./build.sh [Name] install      build and install to ~/Library/Audio/Plug-Ins/Components
#   ./build.sh [Name] uninstall    remove the installed shim
set -euo pipefail
here=${0:A:h}
name=${1:-Geist2}
action=${2:-build}
config=$here/configs/$name.plist
bundle=${name}Shim.component
dest=~/Library/Audio/Plug-Ins/Components/$bundle

[[ -f "$config" ]] || { echo "no config: $config" >&2; exit 1; }

if [[ "$action" == "uninstall" ]]; then
    rm -rf "$dest"
    killall -9 AudioComponentRegistrar 2>/dev/null || true
    echo "removed $dest"
    exit 0
fi

exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$config")
out=$here/build/$bundle
rm -rf "$out"
mkdir -p "$out/Contents/MacOS"
cp "$config" "$out/Contents/Info.plist"

# x86_64 because the legacy plug-ins this targets are Intel-only.
clang++ -arch x86_64 -std=c++17 -O2 -bundle -fvisibility=hidden \
    -mmacosx-version-min=11.0 -Wno-deprecated-declarations \
    -DSHIM_VIEW_FACTORY=${exe}ViewFactory \
    "$here/src/AUShim.mm" -o "$out/Contents/MacOS/$exe" \
    -framework AudioToolbox -framework AudioUnit -framework CoreServices \
    -framework CoreAudio -framework Cocoa
codesign --force --sign - "$out"
echo "built $out"

if [[ "$action" == "install" ]]; then
    rm -rf "$dest"
    ditto "$out" "$dest"
    killall -9 AudioComponentRegistrar 2>/dev/null || true
    echo "installed to $dest"
fi
