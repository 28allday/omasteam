# omasteam — working notes & handover

Written 2026-07-25 for a **fresh SteamOS install**. `README.md` describes what
omasteam *is* and how to use it; this file is the stuff that isn't obvious from
the code — how to get the machine back, what bit us, and what's unfinished.

---

## 0. Rebuilding the system after a wipe

The repo lives on the **4TB drive** (`/run/media/deck/4TB GAMES/projects/omasteam`),
so it survives a reinstall. Home does not — `~/.local/bin`, `~/.local/share/omasteam`,
`~/.config/omasteam`, KDE config and all shortcuts are gone after a wipe.

```bash
cd "/run/media/deck/4TB GAMES/projects/omasteam"
./install.sh --with-bar          # everything in this repo installs into ~/.local
# then LOG OUT and back in — see §4 (KWin only grabs shortcuts at session start)
```

Re-add the two themes (they are cloned from git, not stored here):

```bash
omasteam-theme install https://github.com/HANCORE-linux/omarchy-solitude-theme.git
omasteam-theme install https://github.com/OldJobobo/omarchy-the-loop-theme.git
omasteam-theme set the-loop     # what was active at the time of writing
```

Other flags: `--with-omadots` (CLI toolchain, shell configs, nvim/LazyVim),
`--with-starship`, `--theme <git-url>`, `--no-keybindings`. `./install.sh --help`
prints the full list. The script is idempotent — re-running is safe and is the
normal way to apply changes.

Things install.sh does that are easy to forget it does:
- **Removes the stock Plasma panel** (backed up to
  `~/.config/omasteam-panel-backup.appletsrc`). The bar is then the *only*
  desktop chrome — no taskbar, no system tray.
- Installs Krohnkite (tiling) and the keybinding map.
- Writes an autostart entry with an **absolute** `Exec` path (see §4).

### Git state at time of writing

`master`, working tree clean, **in sync with origin as of 2026-07-28** — the bar,
the seven panels and the merged system menu are all public now. The earlier hold
("more system work before this goes public") is lifted; push normally.

Note the state in §6 still stands: several panels are verified by injection and
screenshot but have never been finger-tested on real Deck hardware. Public does
not mean confirmed.

### Backups on the drive

Because none of that history is on GitHub, it exists **only on this drive**.
Two extra copies sit next to the checkout:

```
projects/omasteam                     the working checkout
projects/omasteam-backup.git          bare mirror, wired up as the `drive` remote
projects/omasteam-<date>.bundle       single-file archive of the full history
```

Keep the mirror current after committing — one command, no network:

```bash
git push drive master
```

Refresh the single-file bundle when it matters (it's a snapshot, not a remote):

```bash
git bundle create "../omasteam-$(date +%F).bundle" --all
```

Restore from either one:

```bash
git clone /path/to/omasteam-backup.git omasteam        # from the mirror
git clone /path/to/omasteam-<date>.bundle omasteam     # from the bundle
```

**⚠️ These protect against losing the working folder, not against losing the
drive** — all three copies are on the same disk. The bundle is one self-contained
file precisely so it can be dragged to a USB stick or cloud folder in one go;
doing that (or finally pushing to `origin`) is the only real off-disk backup.

---

## 1. What this thing is, in one page

An Omarchy-4 ("quattro") style desktop on SteamOS, built with **zero system
modification**: SteamOS's root is read-only, so everything is pure userland in
`~/.local`, using the stock Qt6 — no Quickshell, no compiler, no `sudo`.

Every surface follows the same **QML front / bash back** split, because plain
QML under `qmlscene` cannot spawn processes or write files:

```
  bin/omasteam-<thing>            bash: launcher + backend + dispatcher
  artifacts/bar/omasteam-<x>.qml  the surface (a Wayland layer-shell window)
```

1. The launcher gathers state, **renders** the QML (substituting `@@PLACEHOLDER@@`
   values, because argv/env aren't reliably reachable from QML under qmlscene)
   into `~/.local/state/omasteam-<x>/…rendered.qml`, and runs `qmlscene6` on it.
2. The QML pushes chosen actions into a **SQLite outbox** (QtQuick.LocalStorage,
   landing under `~/.local/share/QtProject/QtQmlViewer/QML/OfflineStorage/Databases/*.sqlite`).
3. The launcher drains that table and runs the real command.

**Each surface uses its own table name** — `outbox` (bar), `menu_outbox`,
`vol_outbox`, `bt_outbox`, … The bar daemon drains *any* database containing a
table called `outbox`, so a shared name would let it swallow another surface's
commands.

The surfaces:

| Surface | Opened by | Notes |
|---|---|---|
| bar | autostart | The only always-on surface. `omasteam-bar restart\|stop\|status` |
| menu | `Meta+Alt+Space`, bar `☰` | **One menu for everything** — apps + all settings |
| volume / network / bluetooth / monitor / power | bar chips | quattro-style cards, top-right |
| display / nightlight | bar chips **and** menu leaves | Re-added to the bar 2026-08-03 on request; still in the menu too |
| steam | bar Steam chip | Game Mode *or* desktop client. Replaces the two `~/Desktop` icons install.sh now removes |

The bar daemon (`bin/omasteam-bar-daemon`) polls the system every tick and
writes `~/.local/state/omasteam-bar/state.json`; every surface reads that file
for the live theme palette, so all of them recolour together.

---

## 2. QML + layer-shell gotchas

These each cost hours.

- Launch with **`qmlscene6`, not `qml6`**. `qml6` prints "Did not load any
  objects" and swallows the real error; qmlscene surfaces it.
- **⚠️ Qt sends QML warnings to JOURNALD, not stderr.** Every launcher's
  `>/dev/null 2>&1` and every piped qmlscene run looks clean while errors exist.
  To actually see them:
  ```bash
  QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 \
    timeout 6 qmlscene6 <rendered.qml> > warn.log 2>&1    # a FILE — piping to head/grep also eats it
  # or: journalctl --user -f | grep qmlscene
  ```
  This single fact invalidated a whole first pass of a bug sweep. Related: a
  `Component.onCompleted` **does** run under `QT_QPA_PLATFORM=offscreen` (the
  belief that it doesn't was the same logging artifact).
- Layer-shell needs **`QT_WAYLAND_SHELL_INTEGRATION=layer-shell`** in the
  environment (that's literally what `LayerShellQt::useLayerShell()` sets).
  QML module is `org.kde.layershell`.
- **⚠️ NEVER `export` that variable** in a launcher that also spawns other
  programs. Child Qt apps (kcmshell6, systemsettings, …) then become full-output
  layer surfaces — the symptom is "everything opens full screen". Scope it to
  the one invocation: `VAR=... "$QMLSCENE" "$RENDERED"`.
- **⚠️ LayerShellQt's DEFAULT anchors are ALL FOUR EDGES.** Omitting
  `LayerShell.Window.anchors` stretches the surface across the whole output no
  matter what width/height you set, and the transparent margin around your card
  shows a **frozen snapshot of the desktop**. For a centred float set
  `LayerShell.Window.anchors: LayerShell.Window.AnchorNone` — the enum exists;
  assigning plain `0` fails with "unsupported type QFlags".
- **Window size must be static and nonzero at creation.** A binding that only
  resolves later (`height: panel.height`, which is 0 at map time) makes qmlscene
  map the surface at its ~3/4-screen default and never reconfigure it. Cards are
  therefore fixed-size, rofi-style (fewer rows just leave empty card).
- The attached exclusive-zone property is **`exclusionZone`**, not
  `exclusiveZone`.
- **`LayerShell.Window.margins.top/right/…` DO work** (ExtQMargins wrapper; the
  module's qmltypes file is empty, verified via .so strings + live testing).
  Anchor `Top|Right` + margins = a quattro-style popup under a bar chip. One
  anchored edge per axis keeps the size fixed; the compositor auto-offsets past
  the bar's exclusive zone, so `margins.top` is only the visual gap.
- QML `XMLHttpRequest` refuses `file://` reads without
  **`QML_XHR_ALLOW_FILE_READ=1`** — the surface renders but stays empty. And no
  `?_=` cache-buster on a file:// URL (it makes the path invalid); XHR re-reads
  the file every call anyway.
- **Two `Component.onCompleted` on one object** = "Property value set multiple
  times" = silent no-window death. Only visible via the offscreen run above.
- **Guard your polls.** `if (raw === _lastRaw) return` before reassigning state:
  reassigning identical state re-dirties every binding for nothing.
- **Close paths must unmap first, quit later.** Destroying the layer surface in
  the same event cycle as the input that triggered it has **segfaulted KWin**
  (`Window::bufferGeometryChanged` inside `Transaction::apply`). Every surface
  uses `dismiss() { visible = false; quitTimer.start() }` with a 150ms timer.
- **Two overlays at once** = two keyboard grabs and a card the user can't see
  (they all share the top-right anchor). Every surface calls
  `bin/omasteam-surface-close <its-own-name>` on open.
- **Setting `text:` as an initial property value does not fire `onTextChanged`.**
  A test copy with a preset filter therefore renders *unfiltered* and looks like
  a broken search. Drive test input from a `Timer` (a runtime assignment) instead.
- "Desktop corruption" on the physical panel under repaint load (bands, frozen
  regions while a terminal scrolls hard) is a **pre-existing display artifact**
  of this HDMI 3840x2160 @ 1.7 fractional-scale setup — reproduced with no
  overlay running at all. Don't attribute it to QML surfaces, and don't chase it
  through them.
- Spectacle screenshots can **disagree with the physical panel** under fractional
  scaling (Qt reports dpr 2 at scale 1.7). When geometry is in question, trust
  the user's eyes, or use a bordered probe (`border.color:"lime"; border.width:20`)
  which shows the exact surface rect.

### Reference implementation

A local Omarchy-quattro checkout lives at `~/projects/omarchy-quattro`
(Quickshell-based, so its code can't run here — but the *look* and the panel
inventory are worth copying). `shell/plugins/panels/` has power, monitor,
tailscale, weather, dropbox. Note quattro's "monitor" panel is
brightness/display controls; ours is a system monitor.

---

## 3. Bash / shell gotchas

- **⚠️ `pkill -f` / `pgrep -f` self-match — this bit EIGHT times**
  (each time as a mysterious exit 144). The pattern matches *any* process whose
  command line contains it, **including the agent's own tool shell**, because the
  command line holds the pattern you just typed. Never `pkill -f`/`pgrep -f` with
  a pattern that appears in the same command line. Kill by **PID** after verifying
  against `/proc/<pid>/cmdline`, or use `pgrep -x <comm>` and filter its output.
  Every surface single-instances via a **/proc-verified PID file**
  (`~/.local/state/omasteam-<x>/panel.pid`) for exactly this reason.

  **`bin/omasteam-bar` was the last holdout; converted 2026-08-03** (the eighth
  bite was an agent combining `install …/omasteam-bar-daemon` with a restart in
  one shell). It now records `bar.pid` / `daemon.pid` under
  `~/.local/state/omasteam-bar/` and identifies processes by **argv position**,
  not by substring:

  | | argv[0] | argv[1] |
  |---|---|---|
  | real bar | `qmlscene6` | `…/omasteam-bar.rendered.qml` |
  | real daemon | `bash` | `…/omasteam-bar-daemon` |
  | a shell that merely *mentions* either | `bash` | `-c` |

  That last row is the whole trick — a mentioning shell buries the path in
  `argv[2]`, so it can never satisfy the predicate. **Restarting the bar from any
  shell is now safe**, and the neutrally-named helper script is no longer needed.
  Two traps if you touch this code: the predicates run against *every* process on
  the box, so (a) every `${ARGV[n]}` needs `:-` or `set -u` turns a one-element
  command line into a fatal mid-sweep (that bug shipped for one test cycle and
  made `stop` quietly give up, leaving the bar running), and (b) never relax the
  positional check back to a substring match.
- **`$$` is the MAIN shell's pid inside a background subshell.** Two concurrent
  regens using `"$FILE.$$"` collide (seen as `mv: cannot stat` noise). Use
  `mktemp "$FILE.XXXXXX"`.
- **`setsid -f cmd || fallback` makes the fallback dead code** — `setsid -f`
  always exits 0 immediately. Use `setsid bash -c 'a || b' &`.
- **`grep -q` on a big producer under `set -o pipefail` gives a false negative:**
  grep exits early → the producer gets SIGPIPE (141) → the pipeline "fails".
  This made a font-installed check report the font missing. Use `grep -ciF` plus
  a count test.
- **Under `set -e`, an unguarded `val()` lookup kills the script mid-apply.**
  `omasteam-theme` needs `|| true` on palette queries — a theme missing any one
  key silently killed the whole apply.
- **Templating: use `awk` + `ENVIRON`, never `sed` or `awk -v`.** `sed` treats
  `&`/`\` specially in the replacement and its delimiter can collide with a theme
  name or path; `awk -v` escape-processes its values, which turned the app JSON's
  `\"` back into a bare `"` (one quote in a .desktop `Name` = syntax error = the
  surface never opens). `ENVIRON` is verbatim.
- **`kreadconfig6` exits 0 for a missing key** (printing nothing) — test the
  output string, never the exit code. `kwriteconfig6 --key K --delete` also
  removes the group when K was its last key.
- Shell state in `$(...)` is a subshell: the CPU sampler keeps its previous
  `/proc/stat` sample in a **file** (`$STATE_DIR/cpu.prev`), because a shell
  global would never survive.
- `top -bn1 %CPU` is a since-boot average (every process looks equally busy).
  Use `top -bn2 -d 0.3` and keep the **second** block.
- Scope `find` for outbox databases to `~/.local/share/QtProject` — unscoped, it
  crawled the 75k-file Steam library every second.

---

## 4. KDE / KWin gotchas

- **⚠️ Custom global shortcuts only grab at SESSION START.** On Plasma 6 Wayland
  kglobalaccel is hosted *inside* kwin_wayland, and kwin installs launcher-shortcut
  key grabs only when it reads `kglobalshortcutsrc` at session start. A shortcut
  added mid-session registers at the D-Bus level (`invokeShortcut` works and
  really does launch the thing) but the **physical key does nothing** until a
  logout/login. This is why every custom key in this project needs a relogin.
  `doRegister` *before* `setForeignShortcut` at least creates the component so the
  grab attaches at the next login.
- **Any key that is some component's `.desktop` DEFAULT must be re-cleared every
  login, not just once.** KRunner declares `Meta+Space` as a default, so each
  login kglobalaccel re-granted it and our claim lost (silently, writing an empty
  binding). `bin/omasteam-rebind-shortcuts` runs at login and pushes KRunner to
  `Alt+Space` **before** binding anything else. Meta+Space is currently unbound
  on purpose (the app launcher moved into the menu) but KRunner is still pushed
  off it, so nothing unexpected claims it.
- **Krohnkite reads its config only at script load.** Neither `reconfigure` nor
  toggling the plugin flag re-reads it — you must
  `Scripting.unloadScript krohnkite` then `Scripting.start`.
- **⚠️ Do NOT connect per-window signals from a KWin script.** A watcher script
  connecting to `frameGeometryChanged`/`fullScreenChanged` per window **segfaulted
  kwin_wayland**. One-shot `workspace.windowList()` dumps via `loadScript` are
  safe and are a genuinely useful tool for dumping window classes/geometry
  (`qdbus6 org.kde.KWin /Scripting loadScript <file.js>`, output to
  `journalctl --user`). Note `resourceName` and `resourceClass` both matter.
- KWin's crash handler on this SteamOS build restarts it with inherited Wayland
  fds, so **clients survive** — the desktop flashes and apps live on. Don't read a
  flash as "nothing happened".
- **`plasma-apply-colorscheme` NO-OPS when the scheme name is unchanged.** Write
  the values into live `kdeglobals` with `kwriteconfig6` + `notifyChange(0)`
  instead. Some apps (Dolphin) still need a restart for titlebar/header, because
  the palette is cached per process.
- Generated KDE colour schemes **must include `[ColorEffects:*]` blocks**
  (`Enable=false`). Without them, kdeglobals holds empty-valued ColorEffects keys
  and the runtime inactive effect tints *unfocused* windows blue.
- **Night light is READ-ONLY on D-Bus** (no setter). Config goes to kwinrc
  `[NightColor]` and **must** use `kwriteconfig6 --notify` — KWin watches via
  KConfigWatcher, a plain write is silently ignored and `qdbus6 /KWin reconfigure`
  does not help. Mode enum (from `/usr/share/config.kcfg/nightlightsettings.kcfg`):
  0 Automatic, 1 Location, 2 Times, 3 Constant, written as *names*.
  **⚠️ Unresolved:** writing `Mode=Constant` did not take — D-Bus still reported
  `mode=0`. Worth investigating if the panel's *Always* option misbehaves.
- **⚠️ KWin's NightLight `running` property does NOT mean "tinting".** It means
  "enabled and operating", and is true at midday at full 6500K. To know whether
  the screen is actually warmed, compare `currentTemperature` against the
  configured `DayTemperature` (kwinrc, 6500 when unset). Use
  `NightLight.preview(K)` + `stopPreview` to test tinting without changing config.
- `kwinrulesrc` "apply initially" size rules fix apps that remember a tiled-era
  geometry (a centred float of a full-size window *looks* fullscreen). One
  `kcmshell6` entry covers every kcm module (they share a resourceName).
- **The autostart `.desktop` Exec MUST be an absolute path.** The graphical
  session's PATH does not include `~/.local/bin` (that's a .bashrc addition
  autostart never sources), so a bare `Exec=omasteam-bar` silently fails — and
  since `--with-bar` removes the Plasma panel, that means a completely bare
  desktop after a Game Mode → Desktop switch. Every launcher also prepends
  `~/.local/bin` to PATH for the same reason.
- Game Mode → Desktop restarts the Plasma session, so bar + daemon die and rely
  on autostart. The daemon purges its outbox on startup so a stale click (e.g.
  return-to-gaming) from a dead session can't fire on relaunch and bounce the
  user straight back to Game Mode.
- **Known, not fixable via colour scheme:** the full `systemsettings` app's left
  Kirigami sidebar stays ~`rgb(59,62,63)` (a fixed elevation blend). Individual
  kcm modules have no such sidebar, so it only affects the one "Open Full System
  Settings" leaf.

---

## 5. Testing without a user present

- Live-session env for anything run from an agent shell:
  ```
  WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
  ```
- Screenshot: `spectacle -b -n -f -o shot.png`. Crop/sample without PIL or
  ImageMagick (neither is installed) using ffmpeg:
  ```bash
  ffmpeg -i shot.png -vf "crop=W:H:X:Y" crop.png                       # crop
  ffmpeg -i shot.png -vf "crop=16:16:X:Y,scale=1:1" -f rawvideo \
    -pix_fmt rgb24 - | od -An -tu1                                     # average RGB at a point
  ```
- **Drive a surface without clicking it:** insert a row into its outbox table and
  then kill the overlay by PID; the launcher drains and dispatches on exit.
  ```bash
  sqlite3 <db> "INSERT INTO menu_outbox(cmd) VALUES('launch-desktop:/usr/share/applications/org.kde.ark.desktop');"
  ```
  Find the right database by looking for the table:
  ```bash
  find ~/.local/share/QtProject -path '*OfflineStorage/Databases/*.sqlite' | while read -r d; do
    sqlite3 "$d" "SELECT 1 FROM sqlite_master WHERE name='menu_outbox' LIMIT 1;" | grep -q 1 && echo "$d"
  done
  ```
  (Bar db is `d8b0595b…`, menu `50df3bf3…` — but these are per-database-name
  hashes, so re-derive them after a wipe rather than trusting the numbers.)
- **Probe QML logic headlessly** by inserting a `Timer` into a copy of the
  rendered file that drives input and `console.log`s the result, then running it
  offscreen with `QT_FORCE_STDERR_LOGGING=1` into a file. This is how the menu's
  global search was verified without a single click.
- The bar's own state can be regenerated once with `omasteam-bar-daemon --once`.

---

## 6. State of play (2026-07-25)

### Done and user-confirmed
Bar + workspaces + Return-to-Gaming; system menu; theme switcher incl. full KDE
colour scheme and JetBrains Mono UI font; Krohnkite tiling; `Meta+Alt+Space` and
(then) `Meta+Space` physical grabs; the power panel ("tapped it, works") and the
system monitor panel ("that seems to work"); the inactive-window blue-tint fix.

### Done, verified by injection + screenshots, NOT yet finger-tested
- The **volume / network / bluetooth** panels. Specifically untested paths: a
  **real Bluetooth pair** with headphones or a controller, and **Wi-Fi
  connect-with-password** (there was no known Wi-Fi network to try).
- The **display** panel — especially the apply-on-approval strip on a *real* mode
  change. Its brightness row is hidden on this box (no `/sys/class/backlight`,
  it's an HDMI-only mini PC) and only appears on real Deck hardware.
- The **night light** panel.
- The four rewired menu leaves (Wi-Fi / Bluetooth / Sound / Power).
- The merged **Applications** level and top-level search in the menu.

### Notable hardware caveat
The machine this was developed on reports as a **"Micro Computer (HK)" mini PC**,
not a Deck: no battery (`/sys/class/power_supply` empty), no backlight, no
`powerprofilesctl`/`platform_profile`. So the battery chip, brightness row and
power-profile controls are all untested and some are hidden by design.

Fuller picture (2026-08-03): SteamOS on a **Ryzen 9 7945HX**, 30 GiB, single HDMI
at **2259x1271 @1.7** — not 1280x800, so the bar-width worries in the QML comments
do not bite here. **Two GPUs**: `card0` NVIDIA RTX 5060 Ti (discrete),
`card1` AMD Raphael iGPU. `steamosctl get-default-login-mode` returns `game`, so
"Game Mode" takes the logout branch.

**Do not reason about Deck hardware when working on this repo** — brightness needs
DDC/CI on an external monitor, not `/sys/class/backlight`, and anything
battery/TDP-shaped has nothing to run against.

**GPU stats must stay vendor-agnostic.** `gpu_busy_percent` is an amdgpu/xe
attribute NVIDIA never exposes, and a global `hwmon_by_name amdgpu radeon i915`
lookup will happily pair one card's load with another card's temperature. That
combination made the monitor panel track the **idle iGPU** while the RTX did the
work. `bin/omasteam-monitor` now detects a backend once (`nvidia-smi` for NVIDIA,
per-card sysfs otherwise), prefers the largest-VRAM card as the discrete one,
reads temperature from **that card's own** hwmon, and publishes
`gpu.vendor`/`gpu.model` so the panel can say which chip it is showing.
`OMASTEAM_GPU=nvidia|amd|intel|cardN` overrides the pick.

### Recently decided (don't re-litigate)
- **One menu for everything.** The separate `Meta+Space` app launcher was folded
  into the system menu as an "Applications" level; `Meta+Space` is unbound. An
  earlier session had *split* them, so the code history reads both ways — the
  merge is the current intent.
- ~~**No display / night light chips on the bar.**~~ **Reversed 2026-08-03, on an
  explicit request for both.** The original chips were built, worked, and were
  reverted (`3ca76bb` then `cb720dd`) because the bar read as cluttered; that
  preference no longer holds, so they are back. The panels stay reachable from
  the menu as well. The clutter objection was real, though — if a third chip is
  ever proposed, weigh it against that history rather than adding it by reflex.
  The night light chip earns its width by doubling as a **long-press toggle**,
  which is a thing the menu leaf cannot do.
- **The Steam chip is a panel, not a one-way door (2026-08-03).** It used to fire
  `return-to-gaming` on tap, so the ONLY route to the desktop Steam client was the
  `~/Desktop/steam.desktop` icon — unreachable under tiled windows. It now opens
  `omasteam-steam`: Game Mode (armed, second tap confirms — it ends the session)
  or the desktop client (fires immediately). `return-to-gaming` is kept in the
  daemon as the no-panel fallback and for stale outbox rows.

  install.sh removes the two icons this replaces, but **only when they are the
  stock ones**: `Return.desktop` matched on its `switch-to-game-mode` Exec, and
  `steam.desktop` only while it is still a symlink. A real file at either path is
  someone's own launcher. Removing the symlink does not touch Steam — the system
  entry stays, so it's still in the menu and still the `steam://` handler.
- **The kcm long tail stays kcmshell6.** ~43 settings modules deliberately still
  open KDE's own module rather than being reimplemented — converting them all
  means rebuilding System Settings. Only holdouts with a real omasteam panel were
  converted.

### Open threads / ideas floated but not started
- Weather in the bar centre (real quattro has it; needs a location + outbound fetch).
- Rounded workspace pills, bar transparency.
- A real SNI **system tray** — hard in plain QML, and it's the reason removing the
  Plasma panel loses the tray entirely.
- Tailscale / Dropbox panels (quattro has them) — only if those are installed.
- ~~`bin/omasteam-bar` still uses `pkill -f`; convert to the PID-file pattern if it
  ever bites in normal use.~~ **Done 2026-08-03** — see §3.
- ~~**Cosmetic bug:** the menu's *Appearance & Style* row glyph renders as an
  empty box.~~ **Fixed 2026-07-28.** `U+F53F` is Font Awesome *5*; the Nerd Font
  patch carries only the legacy FA4 block here. It was used twice — the category
  and its own *Colors* leaf — now `U+F0D0` (wand) and `U+F1FB` (eyedropper).
  `U+F042` was the tempting pick for the category but is already the *Global
  Theme* leaf, which would have made the parent duplicate its child.

  **Check codepoints before using them**, all nine surfaces at once:

  ```bash
  for f in artifacts/bar/*.qml; do
    for cp in $(sed 's://.*::' "$f" | grep -oE '0x[0-9A-F]{4}' | sort -u); do
      h="${cp#0x}"; case "${h,,}" in e*|f*) ;; *) continue ;; esac
      fc-list ":charset=${h,,}" family | grep -qi "JetBrainsMono Nerd Font" \
        || echo "MISSING $cp in $f"
    done
  done
  ```

  All 94 glyphs across the nine surfaces passed this as of 2026-07-28.

---

## 7. Editing checklist

After changing a QML surface or a launcher:

1. Edit in the repo (`artifacts/bar/*.qml`, `bin/*`) — never in `~/.local`, which
   is a deploy target.
2. Install to `~/.local` (`./install.sh --with-bar`, or `install -m644/-m755` the
   individual files).
3. Restart the bar if you touched the bar or the daemon (`omasteam-bar restart`).
   Safe from any shell since the §3 conversion — the neutrally-named helper script
   that step used to require is no longer needed.
4. Sweep for QML warnings **via a file**, per §2. Zero warnings is the standard;
   all surfaces were clean as of this writing.
5. `git commit`, then `git push origin master` and `git push drive master` — the
   mirror is worthless if it lags the checkout.
