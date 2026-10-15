#!/bin/zsh
# Lists installed Audio Units that macOS 27+ no longer registers (legacy .rsrc
# only, no AudioComponents in Info.plist) and whether a shim is installed.
setopt null_glob
found=0
for d in /Library/Audio/Plug-Ins/Components/*.component ~/Library/Audio/Plug-Ins/Components/*.component; do
    plist="$d/Contents/Info.plist"
    [[ -f "$plist" ]] || continue
    /usr/libexec/PlistBuddy -c "Print :AudioComponents" "$plist" >/dev/null 2>&1 && continue
    ls "$d/Contents/Resources/"*.rsrc >/dev/null 2>&1 || continue
    exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist" 2>/dev/null)
    archs=$(lipo -archs "$d/Contents/MacOS/$exe" 2>/dev/null)
    short=${exe//[^A-Za-z0-9]/}
    if [[ -d ~/Library/Audio/Plug-Ins/Components/${short}Shim.component ]]; then
        state="shim installed"
    else
        state="needs shim"
    fi
    printf "%-38s %-14s %s\n" "${d:t}" "[$archs]" "$state"
    found=1
done
if (( found )); then
    echo
    echo "To fix one:  tools/make_config.py \"/Library/Audio/Plug-Ins/Components/<Plugin>.component\""
    echo "             ./build.sh <Name> install"
else
    echo "No legacy (resource-only) Audio Units found. Nothing to fix."
fi
