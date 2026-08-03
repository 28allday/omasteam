# omasteam

An Omarchy-flavored desktop for the **Steam Deck** (SteamOS + KDE Plasma 6, Wayland) —
reproduced entirely in **userland** (`~/.local`), because SteamOS's root filesystem is
read-only. No `pacman`, no `sudo`, survives OS updates.

> **Unofficial & unaffiliated.** This is an independent hobby project. It is **not**
> affiliated with, endorsed by, or connected to Omarchy, Basecamp, or DHH — it just
> brings an Omarchy-style look/workflow to SteamOS + KDE. Names and themes belong to
> their respective owners. MIT licensed ([LICENSE](LICENSE)); see [NOTICE](NOTICE) for the full disclaimer.

## What you get

- **A top bar** — Omarchy-4 ("quattro") style: workspaces, clock, Return-to-Gaming,
  and a status chip per subsystem, each opening its own panel
- **A system menu** on `Meta+Alt+Space` — one keyboard-driven surface for your apps
  *and* a mirror of KDE's System Settings
- **Auto-tiling** via Krohnkite, with the settings surfaces floating instead
- **The Omarchy keybinding set** mapped onto KDE
- **kitty** as the default terminal (JetBrainsMono, hidden tab bar, live theme)
- **A theme switcher** that re-themes the *whole* system from any Omarchy theme's git URL
- Optionally an **omadots** terminal environment — eza, bat, fzf, zoxide,
  neovim + LazyVim, starship

## Screenshots

**Before** — stock SteamOS Desktop Mode (KDE Plasma, default panel + wallpaper):

![Stock SteamOS KDE desktop](screenshots/01-stock-steamos-kde.png)

**After** — omasteam: slim top bar, Omarchy theme + wallpaper, `Return to Gaming Mode` still one click away:

![omasteam themed desktop](screenshots/02-omasteam-desktop.png)

**Krohnkite auto-tiling** — windows tile automatically (settings surfaces opened
from the system menu — kcm panels, the Wi-Fi applet, System Settings — float
centered instead of tiling); here btop, kitty and Firefox share the screen:

![omasteam auto-tiling: btop, kitty, Firefox](screenshots/03-tiling-btop-kitty-firefox.png)

**omadots terminal env** — neovim + LazyVim in a kitty pane alongside btop and Firefox:

![omasteam with LazyVim, btop and Firefox](screenshots/04-tiling-btop-firefox-lazyvim.png)

## Quick start

On the Deck: switch to Desktop Mode, open Konsole, then:

```bash
git clone https://github.com/28allday/omasteam.git ~/omasteam
cd ~/omasteam
./install.sh --with-bar --with-omadots
```

**Then log out and back in** (or reboot). That step is required, not optional —
KWin only grabs global shortcuts at session start, so until you do, the
keybindings, `$TERMINAL`, the Run-In-kitty service menu, the 9 virtual desktops
and the bar's autostart are all installed but inert.

Those two flags are the full experience: `--with-bar` is the bar, the system menu
and the panels; `--with-omadots` is the terminal toolchain. Drop either if you
don't want it — see [Install options](#install-options). The script is idempotent,
so adding a flag later just means re-running it.

## Your first five minutes

Once you're back in the session:

**Press `Meta+Alt+Space`.** That's the system menu, and it's the thing to learn
first — it holds your applications *and* every settings screen. Type to filter,
`Enter` to open, `Esc` to dismiss.

**Pick a theme.** The install deliberately doesn't apply one:

```bash
theme omarchy tokyo-night      # any official Omarchy theme by name
theme                          # list what's installed
```

Everything re-colors at once — bar, panels, kitty, KDE, btop, wallpaper, neovim.

**Try the tiling.** Open two windows (`Meta+Return` for kitty, `Meta+B` for the
browser). They tile automatically. `Meta+arrows` moves focus, `Meta+Shift+arrows`
moves the window, `Meta+Shift+V` floats one.

**Tap the chips** in the top-right of the bar — volume, network, bluetooth, CPU,
clipboard, display, night light, power. Each opens its own panel.

Two things that surprise people, both by design:

- **There is no system tray.** Installing the bar removes the stock Plasma panel,
  and that takes KDE's SNI tray with it. Apps that only live in the tray have
  nowhere to appear. Your old panel is backed up to
  `~/.config/omasteam-panel-backup.appletsrc` if you want it back.
- **`Meta+Space` does nothing.** Apps moved into the system menu, so the old
  separate launcher is gone. KRunner is on **`Alt+Space`**.

## Install options

| Flag | Effect |
|------|--------|
| *(none)* | Desktop only: kitty, default-terminal, font, Krohnkite, keybinds, theme switcher |
| `--with-bar` | + the **bar**, the **system menu** and all the panels. Removes the stock Plasma panel (backed up first) |
| `--with-omadots` | + terminal/dev env (eza, bat, fzf, zoxide, neovim/LazyVim, starship, shell) |
| `--omadots-no-nvim` | with `--with-omadots`, skip neovim/LazyVim |
| `--theme <git-url>` | apply this Omarchy theme during install (the switcher itself is always installed) |
| `--with-starship` | standalone starship (implied by `--with-omadots`) |
| `--no-keybindings` | skip the Omarchy keybinding mapping — leaves KDE's own shortcuts alone |
| `--force-kitty` | reinstall kitty even if present |
| `-h`, `--help` | usage |

**Idempotent** — re-running is safe, and is the normal way to apply changes or add
a flag you skipped.

**Requirements:**

- SteamOS / KDE Plasma 6 **Wayland** session (uses live D-Bus / kglobalaccel)
- Network (downloads kitty, fonts, CLI tools, and the theme repo)
- Stock tools: `curl unzip git kwriteconfig6 qdbus6 kpackagetool6 uuidgen`

Everything installs into `~/.local`. Nothing touches the read-only root.

## Theming

```bash
theme <git-url>          # install & apply any omarchy-*-theme repo
theme omarchy <name>     # install an OFFICIAL Omarchy theme (tokyo-night, gruvbox,
                         #   nord, catppuccin, kanagawa, everforest, rose-pine, …)
theme <name>             # switch between installed themes
theme                    # list installed
theme wallpaper next     # cycle the current theme's backgrounds (also Meta+Ctrl+Space)
```

The ~20 official themes live *inside* `basecamp/omarchy` (`themes/<name>/`), so
`theme omarchy <name>` sparse-fetches just that subfolder. Community themes are
standalone repos — paste their URL to `theme <git-url>`.

Themes re-color kitty, a generated KDE Plasma color scheme + accent, starship, fzf, btop,
GTK apps, wallpaper, and neovim — all from the theme's `colors.toml`. The **icon theme is
left alone** (system default KDE/Breeze) — themes don't touch it, so no distributor logos
sneak into the app launcher.

## The bar

An **Omarchy-4-style top bar** reproduced in pure **QML**, run by SteamOS's stock
**Qt6** as a **wlr-layer-shell** surface. No Quickshell (Omarchy's
compositor-specific shell framework), no compiling, no `sudo`.

```
 ☰  1 2 3 4 5 6 7 8 9        Wed 21:16      steam |  4% 󰂯 󰤨 󰕾 40% 󰁹 ⏻
 menu + workspaces              clock            Return-to-Gaming + status
```

- **Left:** the system menu (`Meta+Alt+Space`) + KWin virtual desktops
  (active = accent; click to switch)
- **Center:** live clock
- **Right:** the **Steam** chip, then one chip per subsystem — each opens its
  own panel:
  - **Steam** → **Game Mode** or the **desktop Steam client**. Game Mode needs a
    confirming second tap (it ends the desktop session); the desktop client
    fires immediately. This chip replaces the two `~/Desktop` icons the
    installer now removes — see below
  - **CPU load** → system monitor: CPU / GPU / RAM / swap / disk meters
    (with temperatures) + the three hungriest processes, live
  - **clipboard** → history from Plasma's own clipboard; tap an entry to make it
    current, `1`-`9` to pick one by number, and Clear (armed) to wipe the lot.
    Multi-line entries collapse to one row and say how many lines they hold
  - **display** → resolution / scale / rotation, applied on approval with an
    automatic revert if you don't confirm
  - **night light** → panel on tap; **long-press toggles the tint** on/off
    without opening anything. Amber when on, dimmed when off; hides itself
    entirely if KWin reports night light unavailable
  - **bluetooth** → power toggle, device list with tap-to-connect/pair
  - **network** → Wi-Fi toggle, network list with tap-to-connect + inline
    password entry
  - **volume** → output/mic sliders + device picker (scroll to change,
    long-press to mute)
  - **battery** → auto-hides if the machine has none
  - **power** → lock / suspend / log out / return to gaming / restart /
    shut down (the last four need a confirming second tap)
- **Theme-synced:** re-colors from the active omasteam theme's `colors.toml`

The display and night-light panels are also still reachable from the system menu,
which is where they lived while the bar had no chips for them.

**The installer removes two `~/Desktop` icons** — SteamOS's `Return to Gaming
Mode` and the `Steam` symlink — because the Steam chip now offers both, and the
desktop underneath tiled windows is the one place you can't reach them. It only
removes them if they are the stock entries (the Return launcher matched on its
`Exec`, and `steam.desktop` only when it is still a symlink); your own launchers
at those paths are left alone. Steam itself is untouched — it stays in the menu
and stays the `steam://` handler.

```bash
omasteam-bar            # start (also autostarts at login)
omasteam-bar stop       # stop bar + daemon
omasteam-bar restart
omasteam-bar status
```

Only one omasteam surface is up at a time: opening any panel or the system menu
closes whichever was already open (`omasteam-surface-close`).

Needs a KDE Plasma 6 **Wayland** session (uses `org.kde.layershell` +
`zwlr_layer_shell_v1`, both stock on SteamOS).

## The system menu (`Meta+Alt+Space`)

Omarchy's other signature piece (`omarchy-menu`), reproduced the same pure-QML
way. Press **`Meta+Alt+Space`** (or click the bar's `☰`) for a centered,
keyboard-driven surface that is the **one menu for everything** — your
applications, plus a mirror of KDE's **System Settings** sidebar:

```
 Applications · Display & Monitor · Accessibility · Connected Devices ·
 Networking · Appearance & Style · Apps & Windows · Sound · Power Management ·
 Input Devices · Workspace · Security & Privacy · Startup & Shutdown ·
 Language & Time · Users · About · Open Full System Settings
 (+ omasteam's own Style / Capture / Power at the bottom)
```

- **Walker-style:** type to filter, `↑`/`↓` to move, `Enter` to open/run,
  `Esc`/`←` to go back, click-outside to dismiss. `Meta+Alt+Space` again toggles it.
- **Search reaches everything.** A query typed at the **top level** searches the
  whole tree at once — applications, settings leaves, themes — and every hit
  shows the category it came from on the right (`Night Light` · *Display &
  Monitor*, `solitude` · *Style · Themes*). Prefix matches rank first, so `fire`
  lands on Firefox. Inside a branch, typing stays scoped to that branch.
- **Applications** is the first row: every installed `.desktop` entry (standard
  XDG dirs, `NoDisplay`/`Hidden` honoured, user overrides win), launched via
  `gio launch`. This used to be a separate `Meta+Space` launcher; it was folded
  in here so there is one surface to learn instead of two.
- Leaves that omasteam has its **own** QML panel for open that panel instead of
  KDE's module — Wi-Fi, Bluetooth and Sound go to the bar's network / bluetooth /
  volume cards, **Display Configuration** opens omasteam's display panel
  (resolution / scale / rotation / brightness, `kscreen-doctor` backend, with
  KDE's *Screen Arrangement* kept alongside it for multi-monitor layout),
  **Night Light** opens omasteam's warmth panel (schedule + temperature, with a
  live preview while you drag), and the **Power** leaves run the same session
  verbs as the power panel (`omasteam-power --run <verb>`), so there is one
  implementation of "how does this desktop log out" rather than two.
  Everything else opens the matching **`kcmshell6`** module; *Open Full System
  Settings* opens the whole app.
  **Style** = next wallpaper + omasteam theme switcher · **Capture** = screenshot
  region/window/full + record (Spectacle).

## Key bindings

With `--no-keybindings` none of this is applied and KDE's own shortcuts stay put.

| Keys | Action |
|------|--------|
| `Meta+Return` | kitty |
| `Meta+Alt+Space` | system menu (apps + settings) |
| `Alt+Space` | KRunner (`Meta+Space` is unbound) |
| `Meta+F` | files (Dolphin) |
| `Meta+B` | browser |
| `Meta+T` | btop |
| `Meta+N` | neovim (with `--with-omadots`) |
| `Meta+W` | close window |
| `Meta+1…9` | switch workspace |
| `Meta+Shift+1…9` | move window to workspace |
| `Meta+arrows` / `Meta+hjkl` | move focus |
| `Meta+Shift+arrows` / `Meta+Shift+hjkl` | move/swap window |
| `Meta+Ctrl+hjkl` | resize the tile |
| `Meta+Shift+V` / `Meta+Shift+Space` | toggle float |
| `Shift+F11` | fullscreen |
| `Meta+Ctrl+Space` | next wallpaper |

Resize is `Meta+Ctrl+hjkl` rather than Omarchy's `Meta+-`/`Meta+=` because KWin's
Zoom effect owns those and always silently wins the conflict.

## What's confirmed, and what isn't

Worth knowing before you rely on a panel. The bar, the system menu, the theme
switcher, tiling, the power panel and the system monitor are **used daily and
confirmed working**. The rest is built and verified by state injection and
screenshots, but has **not been finger-tested on real Deck hardware**:

- a real **Bluetooth pair** (headphones, controller)
- **Wi-Fi connect with a password** — the code path exists, no network was
  available to try it on
- the **display** panel's apply-on-approval countdown against an actual mode change
- the **night light** panel
- the **battery** chip and the display panel's **brightness** row — the machine
  this was developed on is a mini PC with neither a battery nor a backlight, so
  those paths are hidden by design there and only appear on a Deck

None of it can hurt the system — everything lives in `~/.local` and the Plasma
panel is backed up before removal — but if something misbehaves, that list is
where to look first. Reports welcome.

## Under the hood

A small bash daemon (`omasteam-bar-daemon`) polls the system + theme and writes
`~/.local/state/omasteam-bar/state.json`; each surface reads it on a timer and
pushes clicks back through a tiny SQLite outbox, which its bash launcher drains
and executes. That indirection exists because plain QML under `qmlscene` cannot
spawn processes — running commands is the one thing Quickshell adds that stock Qt
lacks.

**Debugging a surface:** Qt sends QML warnings to the *journal*, not to the
launcher's stderr — a broken binding leaves no trace in a terminal. Watch them
with `journalctl --user -f | grep qmlscene`, or run a rendered surface by hand
with `QT_FORCE_STDERR_LOGGING=1` to get them on the console:

```bash
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 \
  qmlscene6 ~/.local/state/omasteam-monitor/omasteam-monitor.rendered.qml
```

```
install.sh        one idempotent entry point (desktop + terminal + theming + bar)
bin/              omasteam-theme, theme (wrapper), omasteam-rebind-shortcuts,
                  omasteam-bar (launcher), omasteam-bar-daemon (bar backend),
                  omasteam-menu (system-menu launcher + dispatcher; also builds
                    the Applications level and launches .desktop entries),
                  omasteam-volume (volume-panel launcher + live dispatcher),
                  omasteam-network (network-panel launcher + nmcli backend),
                  omasteam-bluetooth (bluetooth-panel launcher + bluetoothctl backend),
                  omasteam-power (power-panel launcher + session verbs),
                  omasteam-monitor (system-monitor launcher + /proc sampler),
                  omasteam-display (display panel + kscreen-doctor backend),
                  omasteam-nightlight (night light panel + kwinrc/KWin D-Bus),
                  omasteam-surface-close (closes every overlay but one)
artifacts/        static config files copied into place (kitty.conf, service menu, …)
artifacts/bar/    one .qml per surface — bar, menu, volume, network, bluetooth,
                  power, monitor, display, nightlight (autostart / shortcut
                  entries are generated by install.sh with absolute paths)
```

> Hacking on omasteam itself? **[`NOTES.md`](NOTES.md)** is the working handover:
> rebuilding after a wipe, the architecture in a page, what's decided and
> shouldn't be re-litigated, and the non-obvious gotchas (QML/layer-shell, KWin
> shortcut grabs, `pkill -f` self-matching, Nerd Font codepoints) that each cost
> hours to find.
