<h1 align="center">Legacy AU Shim</h1>

<p align="center">
  <b>Bring old Audio Unit plug-ins back to life on macOS 27.</b><br>
  FXpansion Geist2, Spitter2 and other classic plug-ins that were never updated: the originals, unmodified.
</p>

<p align="center">
  <a href="https://github.com/terminaldan8/legacy-au-shim/actions/workflows/build.yml"><img alt="build" src="https://github.com/terminaldan8/legacy-au-shim/actions/workflows/build.yml/badge.svg"></a>
  <img alt="macOS 27+" src="https://img.shields.io/badge/macOS-27%2B-black?logo=apple">
  <img alt="Apple Silicon via Rosetta" src="https://img.shields.io/badge/Apple%20Silicon-via%20Rosetta-555">
  <img alt="Audio Unit v2" src="https://img.shields.io/badge/Audio%20Unit-v2-blue">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## In plain English

You updated your Mac to **macOS 27**, and now a plug-in you love, like **Geist2**, has
vanished from Ableton Live, Logic or your other music apps. Your old songs open with the
plug-in **missing**.

**The plug-in isn't broken.** It's still on your Mac. macOS 27 just stopped *recognizing*
plug-ins that introduce themselves the old-fashioned way, and some plug-ins were never
updated because their makers moved on.

**This project fixes that.** It adds a tiny helper, a "shim", for each affected plug-in. Think
of it as a **travel adapter**: your music app plugs into the adapter, and the adapter plugs
into your original plug-in. Nothing about the plug-in itself changes.

After installing it:

- ✅ The plug-in shows up again in your music apps
- ✅ Your **old songs open with all their plug-in settings**
- ✅ It sounds and works exactly as before, because it *is* the original plug-in
- ✅ You can remove it any time with one command

> **Is this a crack?** No. You must already own the plug-in, and its own license check
> still runs normally. See [Is it safe?](#is-it-safe)

---

## Do I need this?

**Yes, if all of these are true:**

1. Your Mac runs **macOS 27** or newer
2. A plug-in that worked before the upgrade is now **missing** from your music apps
3. It's one of the plug-ins in the [compatibility list](#compatibility) (currently FXpansion
   **Geist2** or **Spitter2**), or another plug-in that was never updated

**Not sure?** Ableton Live users can check: when you open an old song, Live shows the
plug-in as missing, and its log file (`Log.txt`) contains *"Restore 1 failed: Geist2"*.

> **Missing an Intel-only VST instead?** Native music apps can't load Intel VST or VST 3
> plug-ins at all. That's a different problem, solved by the sibling project
> [VST AU Bridge](https://github.com/terminaldan8/vst-au-bridge), which turns them into Audio Units.

---

## Install it: step by step

No experience needed. It takes about 5 minutes, most of it waiting for downloads. You'll
copy and paste three commands into an app called **Terminal**.

### Step 1: Open Terminal

1. Open **Finder** and go to **Applications → Utilities**.
2. Double-click **Terminal**.

A window with a blinking cursor appears. That's where you'll paste the commands. To paste:
right-click inside the window and choose **Paste**, then press **Return**.

### Step 2: Install Apple's free developer tools

Paste this and press Return:

```sh
xcode-select --install
```

- A pop-up appears asking to install the **command line developer tools**. Click
  **Install**, then **Agree**, and wait until it says the software was installed (a few minutes).
- If Terminal instead says *"command line tools are already installed"*, great. You
  already have them; go to the next step.

### Step 3: Make sure Rosetta is installed

Rosetta is Apple's free translator that lets older Intel plug-ins run on newer Macs. If the
plug-in worked before, you most likely have it already. Paste this to be sure:

```sh
softwareupdate --install-rosetta --agree-to-license
```

It either installs Rosetta or says it's already installed. Both are fine. (It may ask for
your Mac password. That's Apple's installer, not this project. When you type it, nothing
appears on screen; that's normal.)

### Step 4: Download and install the shim

Paste this whole line and press Return. Use the version for your plug-in.

**For Geist2:**

```sh
cd ~ && git clone https://github.com/terminaldan8/legacy-au-shim.git && cd legacy-au-shim && ./build.sh Geist2 install
```

**For Spitter2:** same line, ending in `./build.sh Spitter2 install`.

When it's done, the last line reads:

```text
installed to /Users/yourname/Library/Audio/Plug-Ins/Components/Geist2Shim.component
```

That's it. The shim is installed. (This also saved the project in a folder called
`legacy-au-shim` in your home folder. You can leave it there.)

### Step 5: Restart your music app

1. **Quit** your music app completely (in its menu bar, choose **Quit**) and open it again.
2. **Ableton Live users:** if the plug-in still doesn't appear, open **Live → Settings →
   Plug-Ins**, hold the **Option** key and click **Rescan**.
3. Open an old song that used the plug-in. Its settings should be back.

> 💡 **Tip:** before opening an important song the first time, make a copy of it, just in case.

### Removing it

Open Terminal and paste:

```sh
cd ~/legacy-au-shim && ./build.sh Geist2 uninstall
```

(Use `Spitter2` instead of `Geist2` if that's the one you installed.)

---

## Compatibility

Tested on macOS 27.0 (26A428) · Apple M1 Max · Ableton Live 12.4.6

| Plug-in | Install name | Checked with Apple's validator | Tested in a music app |
|---|---|:---:|---|
| **FXpansion Geist2** 2.1.2 | `Geist2` | ✅ | ✅ Ableton Live: songs restore, editor opens |
| **FXpansion Spitter2** 2.1.2 | `Spitter2` | ✅ | ✅ Ableton Live: loads and runs |

Both are FXpansion plug-ins that were never updated after 2019. Plug-ins that are still
maintained usually aren't affected; if you have an old copy of one, **updating it** from its
maker is the better fix.

**Help grow this list.** The plug-ins this fixes are mostly abandoned ones that are hard to
find. If you get another one working (or not), please
[open an issue](https://github.com/terminaldan8/legacy-au-shim/issues) and say which plug-in and
version.

---

## Is it safe?

You build the shim yourself from this source code. There's no ready-made program to
download and trust blindly, and the whole thing is small enough to read.

**How small:** the shim is a single file, [`src/AUShim.mm`](src/AUShim.mm) (about 375
lines, commented), plus a 45-line [`build.sh`](build.sh). That's everything.

**What it does:**
- Loads the plug-in you already have installed (read-only), and passes your music app's
  calls to it.
- Installs one file, `~/Library/Audio/Plug-Ins/Components/<Name>Shim.component`, in your
  **user** folder.
- `build.sh` restarts macOS's `AudioComponentRegistrar` so the new plug-in is picked up
  immediately. macOS relaunches it automatically.

**What it doesn't do:**
- ❌ No internet access: no downloads, no tracking, no "phoning home"
- ❌ No password or `sudo`, and no system folders touched
- ❌ Never modifies the original plug-in, its signature or its license
- ❌ Doesn't run other programs or write files while it's running

**Check it yourself** (from the `legacy-au-shim` folder):

```sh
grep -nEi "NSURL(Session|Connection)|socket|curl|http" src/AUShim.mm   # no output = no networking code
grep -n sudo build.sh                                                    # no output = never asks for root
./build.sh Geist2 && nm -u build/Geist2Shim.component/Contents/MacOS/Geist2Shim   # every system function it uses
```

Every change is also built automatically on GitHub's macOS machines, which **fail the build
if the shim ever uses networking or program-launching functions**. See the *build* badge at
the top and the [workflow](.github/workflows/build.yml).

**The one unusual trick, in plain words:** the old plug-in remembers an internal "who am I"
value, which modern macOS no longer accepts for some messages. The shim swaps that single
value for the one your music app uses, but only after checking it holds exactly what's
expected; otherwise it leaves it alone and logs a warning. It's a few lines, marked in the
source, and it never touches the plug-in's code or copy protection.

---

## Troubleshooting

| What you see | What to do |
|---|---|
| The plug-in is still missing | Quit the music app completely (menu bar → **Quit**) and reopen it. In Live, Option-click **Rescan** (Settings → Plug-Ins). |
| Step 4 says *"destination path 'legacy-au-shim' already exists"* | You've downloaded it before. Run `cd ~/legacy-au-shim && git pull && ./build.sh Geist2 install` instead. |
| *"xcrun: error: invalid active developer path"* or *"git: command not found"* | Apple's developer tools aren't installed yet. Repeat [Step 2](#step-2-install-apples-free-developer-tools). |
| *"no config"* | The install name is misspelled. Use `Geist2` or `Spitter2`. |
| *Not Authorised* / license message | The plug-in's own license isn't active on this Mac. Authorize it the normal way (e.g. FXpansion's license manager). The shim doesn't touch licensing. |
| Live says *"Lost the connection to the Audio Unit plug-in"* | The plug-in crashed. Please [open an issue](https://github.com/terminaldan8/legacy-au-shim/issues) and attach the newest `AUHostingService…` file from `~/Library/Logs/DiagnosticReports`. |

---

## FAQ

**Is this a crack?**
No. The shim only fixes how macOS *finds* the plug-in. It loads your installed copy
unmodified, and that copy's own license and copy protection run exactly as before. A
plug-in that isn't authorized on your Mac still refuses to run.

**Does it change how the plug-in sounds?**
No. All audio, presets, the editor and saving come from the original plug-in. The shim
just passes messages through.

**Will my songs still work if I remove the shim later?**
Yes. The plug-in saves its settings in its own format; the shim doesn't change them.

**Why does it need Rosetta?**
These plug-ins were made for older Intel Macs. Rosetta lets them run on newer Apple
Silicon Macs (M1, M2, …), just like before macOS 27.

**What happens when Apple removes Rosetta?**
Then Intel-only plug-ins stop working, with or without this shim. This buys time; it can't
turn an old plug-in into a new one.

**Can I just edit the plug-in's files instead?**
Please don't. It breaks the plug-in's digital signature, and copy-protected plug-ins (like
Geist2) then refuse to load.

---

## For developers and the curious

### Why it broke

Old AUs announce themselves through a `thng` resource in a Carbon `.rsrc` file and a
Component Manager entry point (for example `SymbiosisEntry`). They have no
`AudioComponents` entry in their `Info.plist`. macOS 27 no longer registers these:
`auval -v aumu FxG2 FXPN` reports *didn't find the component*, even under Rosetta.

### How it works

1. **Registration.** The shim's `Info.plist` has an `AudioComponents` entry copied from
   the legacy `thng` resource (type / subtype / manufacturer / name / version), with
   `factoryFunction = AUShimFactory`.
2. **Loading.** On open, `dlopen`s `LegacyAUBinary` and looks up `LegacyAUEntry`.
3. **Component Manager bridge.** Registers that entry locally with `RegisterComponent`,
   then `OpenAComponent`s a private instance. This still works on macOS 27, even though
   the system no longer *discovers* such components.
4. **Forwarding.** Every AU selector (Initialize, Get/SetProperty, Get/SetParameter,
   ScheduleParameters, Render, Reset, MIDIEvent, listeners and render notifies) is
   marshalled into an LP64 `ComponentParameters` block (`params[0]` = instance, then
   arguments in order) and passed to the entry with the instance storage.
5. **Instance fix-up.** The plug-in reports parameter and property changes using its
   stored instance handle, which AudioToolbox rejects for private Component Manager
   instances. The shim points that field (offset 8 in Symbiosis and AUBase objects;
   the value is verified first) at the host's instance. Symbiosis needs the original
   handle back while saving or restoring state (`LegacyAUStateUsesLegacyInstance`).
6. **Editor.** `kAudioUnitProperty_CocoaUI` returns the shim's own view factory, which
   asks the plug-in for its real factory and hands it the private instance.

Shims are built `x86_64`. Native Apple Silicon hosts run them out-of-process under
Rosetta, just as they ran these plug-ins before macOS 27.

| Plug-in | Audio Unit ID (for `auval -v`) |
|---|---|
| Geist2 | `aumu FxG2 FXPN` |
| Spitter2 | `aufx FXS2 FXPN` |

### Find affected plug-ins

```sh
for d in /Library/Audio/Plug-Ins/Components/*.component; do
  if ! /usr/libexec/PlistBuddy -c "Print :AudioComponents" "$d/Contents/Info.plist" >/dev/null 2>&1 \
     && ls "$d/Contents/Resources" 2>/dev/null | grep -q "\.rsrc$"; then
    basename "$d"
  fi
done
```

### Adding another plug-in

1. Copy an existing config:
   ```sh
   cp configs/Geist2.plist configs/SomePlugin.plist
   ```
2. Find the plug-in's ID and name in its resource file. The ID is the 4+4+4 characters
   right after `aumu`, `aufx` or `aumf` (here: type `aufx`, subtype `Smpl`, manufacturer `Manu`):
   ```sh
   strings -a "/Library/Audio/Plug-Ins/Components/Some Plugin.component/Contents/Resources/"*.rsrc
   #   aufxSmplManu
   #   Vendor: Some Plugin
   #   SymbiosisEntry
   ```
3. Edit `configs/SomePlugin.plist`:
   - `AudioComponents` → `type`, `subtype`, `manufacturer`, `name` (the "Vendor: Plugin"
     string), and `version`, calculated as major × 65536 + minor × 256 + patch
     (for example 1.0.0 = `65536` and 2.1.2 = `131330`)
   - `LegacyAUBinary` → `/Library/Audio/Plug-Ins/Components/Some Plugin.component/Contents/MacOS/<executable>`
   - `LegacyAUEntry` → the `…Entry` name from step 2 (also listed by `nm -gU <binary>`)
   - `CFBundleExecutable`, `CFBundleName`, `CFBundleIdentifier` → something unique, e.g. `SomePluginShim`
4. Build and check: `./build.sh SomePlugin install`, then `auval -v aufx Smpl Manu`.
   If `auval` reports *Class Data fields … do not match*, add
   `<key>LegacyAUStateUsesLegacyInstance</key><true/>` (or `<false/>`) and rebuild.

Logs from the shim appear in Console.app; search for **`AUShim`**.

### Config reference

`configs/<Name>.plist` becomes the shim bundle's `Info.plist`.

| Key | Meaning |
|---|---|
| `AudioComponents` | The legacy ID, name and version (must match exactly); `factoryFunction` is always `AUShimFactory` |
| `LegacyAUBinary` | Path to the genuine plug-in binary |
| `LegacyAUEntry` | Its Component Manager entry point (from the `dlle` resource) |
| `LegacyAUStateUsesLegacyInstance` | Optional. Which handle the plug-in needs while saving or restoring state. Defaults to `true` for `SymbiosisEntry` and `false` otherwise |
| `CFBundleExecutable` | Also names the shim's Objective-C view class, so keep it unique per shim |

### Project layout

| Path | Purpose |
|---|---|
| [`src/AUShim.mm`](src/AUShim.mm) | The shim: AU v2 plug-in interface → Component Manager bridge |
| [`configs/`](configs) | Ready-made configs |
| [`build.sh`](build.sh) | `./build.sh <Name> [install\|uninstall]` |

### Limitations

- Relies on deprecated Carbon Component Manager APIs that Apple still ships; a future
  macOS release could remove them.
- Not forwarded: SysEx, `AudioUnitProcess`/`ProcessMultiple`, Carbon (non-Cocoa)
  editors. AU v3 plug-ins aren't affected by this problem anyway.

---

## Contributing

Plug-in reports are the most valuable contribution: they grow the compatibility list and
`configs/`. Bug fixes and support for other wrappers are welcome too. Please test with
`auval` in both modes (`auval …` and `arch -x86_64 auval …`) before opening a PR.

## Disclaimer

Not affiliated with Apple or any plug-in vendor. Product names are trademarks of their
respective owners. This project loads software you already own and have installed; it
does not modify, bypass or redistribute it. Use at your own risk, and back up your
projects.

## License

[MIT](LICENSE)
