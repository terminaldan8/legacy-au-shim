#!/usr/bin/env python3 -I
"""Generate configs/<Name>.plist for a legacy (resource-only) AU bundle.

Usage: tools/make_config.py /Library/Audio/Plug-Ins/Components/Foo.component [Name]

Reads the bundle's .rsrc (a data-fork resource file) for its 'thng' component
resource: type/subtype/manufacturer, version, name ('STR ') and entry point
('dlle'). Writes a ready-to-build shim config next to configs/Geist2.plist.
"""
import os
import plistlib
import re
import struct
import sys


def parse_rsrc(data):
    """Return {type: {id: bytes}} from a classic resource file."""
    data_off, map_off, _, _ = struct.unpack(">IIII", data[:16])
    type_list_off, name_list_off = struct.unpack(">HH", data[map_off + 24:map_off + 28])
    tl = map_off + type_list_off
    ntypes = struct.unpack(">H", data[tl:tl + 2])[0] + 1
    out = {}
    for i in range(ntypes):
        e = tl + 2 + i * 8
        rtype = data[e:e + 4].decode("mac_roman")
        count = struct.unpack(">H", data[e + 4:e + 6])[0] + 1
        ref_off = struct.unpack(">H", data[e + 6:e + 8])[0]
        for j in range(count):
            r = tl + ref_off + j * 12
            rid = struct.unpack(">h", data[r:r + 2])[0]
            attrs_off = struct.unpack(">I", data[r + 4:r + 8])[0]
            d = data_off + (attrs_off & 0xFFFFFF)
            length = struct.unpack(">I", data[d:d + 4])[0]
            out.setdefault(rtype, {})[rid] = data[d + 4:d + 4 + length]
    return out


def pstr(b):
    return b[1:1 + b[0]].decode("mac_roman")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    bundle = os.path.abspath(sys.argv[1].rstrip("/"))
    info = plistlib.load(open(os.path.join(bundle, "Contents/Info.plist"), "rb"))
    if "AudioComponents" in info:
        sys.exit("This plug-in already registers the modern way (AudioComponents); no shim needed.")
    exe = info["CFBundleExecutable"]
    res_dir = os.path.join(bundle, "Contents/Resources")
    rsrcs = [f for f in os.listdir(res_dir) if f.endswith(".rsrc")]
    if not rsrcs:
        sys.exit("No .rsrc found in Contents/Resources.")
    res = parse_rsrc(open(os.path.join(res_dir, rsrcs[0]), "rb").read())

    thngs = res.get("thng", {})
    # Prefer the audio unit, not a Carbon view component ('auvw').
    thng = next((t for t in thngs.values() if t[:4] != b"auvw"), None)
    if thng is None:
        sys.exit("No AU 'thng' resource found.")
    ctype, sub, manu = (thng[i:i + 4].decode("mac_roman") for i in (0, 4, 8))
    name_id = struct.unpack(">h", thng[30:32])[0]
    info_id = struct.unpack(">h", thng[36:38])[0]
    version = struct.unpack(">I", thng[44:48])[0] if len(thng) >= 48 else 0x10000
    # Platform entries follow: flags(4) + ResourceSpec(type 4 + id 2) + platform(2).
    entry = None
    if len(thng) >= 58:
        count = struct.unpack(">i", thng[54:58])[0]
        for k in range(count):
            p = 58 + k * 12
            rtype, rid = thng[p + 4:p + 8], struct.unpack(">h", thng[p + 8:p + 10])[0]
            if rtype == b"dlle" and rid in res.get("dlle", {}):
                entry = res["dlle"][rid].split(b"\0")[0].decode("mac_roman")
                break
    if not entry:
        dlles = list(res.get("dlle", {}).values())
        entry = dlles[0].split(b"\0")[0].decode("mac_roman") if dlles else "SymbiosisEntry"

    strs = res.get("STR ", {})
    au_name = pstr(strs[name_id]) if name_id in strs else info.get("CFBundleName", exe)
    au_desc = pstr(strs[info_id]) if info_id in strs else au_name

    short = re.sub(r"[^A-Za-z0-9]", "", sys.argv[2] if len(sys.argv) > 2 else exe)
    config = {
        "CFBundleDevelopmentRegion": "English",
        "CFBundleExecutable": f"{short}Shim",
        "CFBundleIdentifier": f"io.github.gsdan8.aushim.{short}",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": f"{short}Shim",
        "CFBundlePackageType": "BNDL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1.0",
        "LegacyAUBinary": os.path.join(bundle, "Contents/MacOS", exe),
        "LegacyAUEntry": entry,
        "AudioComponents": [{
            "type": ctype, "subtype": sub, "manufacturer": manu,
            "name": au_name, "description": f"{au_desc} (macOS 27 compatibility shim)",
            "version": version, "factoryFunction": "AUShimFactory",
        }],
    }
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "configs", f"{short}.plist")
    with open(out, "wb") as f:
        plistlib.dump(config, f)
    print(f"wrote {out}")
    print(f"  {ctype} {sub} {manu}  \"{au_name}\"  entry={entry}  version=0x{version:x}")
    print(f"next: ./build.sh {short} install && auval -v {ctype} {sub} {manu}")


if __name__ == "__main__":
    main()
