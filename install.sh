#!/usr/bin/env bash
#
# omasteam — Omarchy-flavored desktop on Steam Deck (SteamOS + KDE Plasma 6)
#
# Idempotent: safe to re-run. Everything installs into ~/.local (SteamOS root is
# read-only, so no pacman / no sudo). See README.md for usage.
#
# Usage:
#   ./install.sh [options]
#     --with-starship     Also install + enable the Starship prompt (default: off)
#     --with-omadots      Phase 2: install the omadots terminal env (CLI toolchain,
#                         shell configs, official starship, btop theme, nvim/LazyVim)
#     --omadots-no-nvim   With --with-omadots, skip neovim/LazyVim
#     --with-bar          Install the omasteam bar: an Omarchy-4-style QML
#                         layer-shell top bar (workspaces, clock, volume,
#                         network, battery, Return-to-Gaming). Removes the stock
#                         Plasma panel (backed up first) so the bar owns the
#                         desktop, Omarchy-style. Also installs the omasteam
#                         system menu (Omarchy-style, Meta+Alt+Space).
#     --theme <git-url>   Install the omasteam-theme switcher, then apply this
#                         Omarchy theme repo (e.g. an omarchy-*-theme git URL)
#     --no-keybindings    Skip the Omarchy keybinding mapping
#     --force-kitty       Reinstall kitty even if already present
#     -h, --help          Show this help
#
# After running, LOG OUT and back in (or reboot) to activate shortcuts,
# $TERMINAL, service menus, and virtual desktops.

set -euo pipefail

# ----------------------------------------------------------------------------
# Setup & options
# ----------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ART="$SCRIPT_DIR/artifacts"

WITH_STARSHIP=0
DO_KEYBINDINGS=1
FORCE_KITTY=0
WITH_OMADOTS=0
OMADOTS_NVIM=1
WITH_BAR=0
THEME_URL=""

KITTY_VERSION_PIN=""          # empty = latest via official installer
# Krohnkite (anametologin fork, actively maintained) replaced Polonium here in
# 2026-07: Polonium's upstream repo was archived Nov 2025.
KROHNKITE_VERSION="0.9.9.2"   # pin the KWin script release
KROHNKITE_URL="https://codeberg.org/anametologin/Krohnkite/releases/download/$KROHNKITE_VERSION/krohnkite-$KROHNKITE_VERSION-1d7fd74.kwinscript"
OMADOTS_RAW="https://raw.githubusercontent.com/omacom-io/omadots/master/config"

while [ $# -gt 0 ]; do
  case "$1" in
    --with-starship)   WITH_STARSHIP=1 ;;
    --with-omadots)    WITH_OMADOTS=1 ;;
    --omadots-no-nvim) OMADOTS_NVIM=0 ;;
    --with-bar)        WITH_BAR=1 ;;
    --theme)           THEME_URL="${2:-}"; [ $# -ge 2 ] && shift ;;
    --no-keybindings)  DO_KEYBINDINGS=0 ;;
    --force-kitty)     FORCE_KITTY=1 ;;
    -h|--help)         awk 'NR>=3{ if($0 ~ /^#/){sub(/^# ?/,"");print} else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

log()  { printf '\033[1;36m::\033[0m %s\n' "$*"; }
ok()   { printf '   \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '   \033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -d "$ART" ] || die "artifacts/ not found next to this script (expected $ART)"

# ----------------------------------------------------------------------------
# 0. Preflight
# ----------------------------------------------------------------------------
preflight() {
  log "Preflight checks"
  for t in curl unzip fc-cache kwriteconfig6 kreadconfig6 kpackagetool6 qdbus6 uuidgen; do
    have "$t" || die "missing required tool: $t"
  done
  [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ] || warn "XDG_CURRENT_DESKTOP is not KDE (got '${XDG_CURRENT_DESKTOP:-unset}') — KDE steps may not apply"
  [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || warn "not a Wayland session — kitty blur and some tiling features need Wayland"
  case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *)
    warn "\$HOME/.local/bin not on PATH; adding it to your .bashrc"
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc" ;;
  esac
  mkdir -p ~/.local/bin ~/.config ~/.local/share/applications
  ok "environment looks good"
}

# ----------------------------------------------------------------------------
# 1. kitty (userland)
# ----------------------------------------------------------------------------
install_kitty() {
  if [ "$FORCE_KITTY" = 0 ] && [ -x "$HOME/.local/kitty.app/bin/kitty" ]; then
    ok "kitty already installed ($("$HOME/.local/kitty.app/bin/kitty" --version 2>/dev/null | awk '{print $2}')) — skipping (use --force-kitty to reinstall)"
  else
    log "Installing kitty (official installer -> ~/.local/kitty.app)"
    if [ -n "$KITTY_VERSION_PIN" ]; then
      curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin installer=version-"$KITTY_VERSION_PIN"
    else
      curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin
    fi
    ok "kitty $("$HOME/.local/kitty.app/bin/kitty" --version | awk '{print $2}') installed"
  fi
  ln -sf ~/.local/kitty.app/bin/kitty  ~/.local/bin/kitty
  ln -sf ~/.local/kitty.app/bin/kitten ~/.local/bin/kitten

  log "Installing kitty desktop launchers (absolute ~/.local paths)"
  mkdir -p ~/.local/share/icons/hicolor/256x256/apps
  for f in kitty kitty-open; do
    src=~/.local/kitty.app/share/applications/$f.desktop
    [ -f "$src" ] || continue
    sed -e "s|Icon=kitty|Icon=$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" \
        -e "s|Exec=kitty|Exec=$HOME/.local/bin/kitty|g" \
        -e "s|Exec=/usr/bin/kitty|Exec=$HOME/.local/bin/kitty|g" \
        "$src" > ~/.local/share/applications/$f.desktop
  done
  cp -f ~/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png \
        ~/.local/share/icons/hicolor/256x256/apps/kitty.png 2>/dev/null || true
  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  ok "launchers installed"
}

# ----------------------------------------------------------------------------
# 2. Default terminal
# ----------------------------------------------------------------------------
set_default_terminal() {
  log "Setting kitty as the default terminal"
  kwriteconfig6 --file kdeglobals --group General --key TerminalApplication kitty
  kwriteconfig6 --file kdeglobals --group General --key TerminalService kitty.desktop
  mkdir -p ~/.config/environment.d
  cp -f "$ART/environment.d-terminal.conf" ~/.config/environment.d/terminal.conf
  cp -f "$ART/xdg-terminals.list"          ~/.config/xdg-terminals.list
  # Right-click "Run In kitty" service menu (shadows the hardcoded Konsole one)
  mkdir -p ~/.local/share/kio/servicemenus
  cp -f "$ART/kittyrun.desktop" ~/.local/share/kio/servicemenus/kittyrun.desktop
  chmod +x ~/.local/share/kio/servicemenus/kittyrun.desktop
  ok "kdeglobals + \$TERMINAL + xdg-terminals.list + service menu set"
}

# ----------------------------------------------------------------------------
# 3. JetBrainsMono Nerd Font
# ----------------------------------------------------------------------------
install_font() {
  if fc-match "JetBrainsMono Nerd Font Mono" 2>/dev/null | grep -qi "JetBrainsMono"; then
    ok "JetBrainsMono Nerd Font already present — skipping download"
    return
  fi
  log "Installing JetBrainsMono Nerd Font -> ~/.local/share/fonts"
  mkdir -p ~/.local/share/fonts/JetBrainsMonoNerd
  local tmp; tmp="$(mktemp -d)"
  curl -fL -o "$tmp/jbm.zip" \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
  unzip -o -j "$tmp/jbm.zip" '*.ttf' -d ~/.local/share/fonts/JetBrainsMonoNerd/ >/dev/null
  rm -rf "$tmp"
  fc-cache -f ~/.local/share/fonts >/dev/null 2>&1
  fc-match "JetBrainsMono Nerd Font Mono" | grep -qi "JetBrainsMono" \
    && ok "font installed and resolvable" || warn "font installed but fc-match did not resolve it"
}

# ----------------------------------------------------------------------------
# 4. kitty config
# ----------------------------------------------------------------------------
install_kitty_config() {
  log "Installing kitty.conf (hyper-snazzy + visual tweaks)"
  mkdir -p ~/.config/kitty
  cp -f "$ART/kitty.conf" ~/.config/kitty/kitty.conf
  if [ -x ~/.local/bin/kitty ]; then
    ~/.local/bin/kitty +runpy \
      'from kitty.config import load_config; load_config("'"$HOME"'/.config/kitty/kitty.conf"); print("ok")' \
      >/dev/null 2>&1 && ok "kitty.conf installed and validated" \
      || warn "kitty.conf installed but validation could not run headlessly"
  else
    ok "kitty.conf installed"
  fi
}

# ----------------------------------------------------------------------------
# 5. Starship (opt-in)
# ----------------------------------------------------------------------------
install_starship() {
  [ "$WITH_STARSHIP" = 1 ] || { ok "Starship not requested (default off) — skipping"; return; }
  log "Installing Starship prompt (opt-in)"
  if ! have starship; then
    curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir "$HOME/.local/bin" --yes
  fi
  [ -f "$ART/starship.toml" ] && cp -f "$ART/starship.toml" ~/.config/starship.toml
  if ! grep -q 'starship init bash' ~/.bashrc 2>/dev/null; then
    printf '\n# Starship prompt\neval "$(starship init bash)"\n' >> ~/.bashrc
  fi
  ok "Starship installed and hooked into ~/.bashrc"
}

# ----------------------------------------------------------------------------
# 6. Krohnkite (auto-tiling KWin script)
# ----------------------------------------------------------------------------
install_krohnkite() {
  log "Installing Krohnkite $KROHNKITE_VERSION (auto-tiling)"
  local tmp; tmp="$(mktemp -d)"
  curl -fL -o "$tmp/krohnkite.kwinscript" "$KROHNKITE_URL"
  if [ -d ~/.local/share/kwin/scripts/krohnkite ]; then
    kpackagetool6 --type=KWin/Script --upgrade "$tmp/krohnkite.kwinscript" >/dev/null
  else
    kpackagetool6 --type=KWin/Script --install "$tmp/krohnkite.kwinscript" >/dev/null
  fi
  rm -rf "$tmp"
  kwriteconfig6 --file kwinrc --group Plugins --key krohnkiteEnabled true
  # Retire Polonium if an older omasteam install enabled it (the script stays
  # on disk for manual rollback; only the plugin flag is flipped).
  kwriteconfig6 --file kwinrc --group Plugins --key poloniumEnabled false
  # Settings surfaces opened from the omasteam menu float instead of tiling.
  # One "kcmshell6" entry covers every kcm module: each gets a distinct
  # resourceClass (kcm_<module>) but they all share resourceName kcmshell6,
  # and Krohnkite matches floatingClass against both.
  kwriteconfig6 --file kwinrc --group Script-krohnkite --key floatingClass \
    "kcmshell6,plasmawindowed,org.kde.plasmawindowed,systemsettings"
  # Floating windows open centered (matches the menu/launcher cards).
  kwriteconfig6 --file kwinrc --group Windows --key Placement Centered
  # Cap the settings windows' initial size ("apply initially" rules). A window
  # that ever ran tiled remembers that huge geometry and would reopen looking
  # fullscreen even as a float; these rules give them sane sizes instead. The
  # kcmshell6 rule only matches the generic shell window (individual modules
  # get class kcm_<module> and pick good natural sizes on their own).
  kwr() { kwriteconfig6 --file kwinrulesrc --group "$1" --key "$2" "$3"; }
  # Merge our rule ids into the existing rule index instead of clobbering it.
  local rules
  rules="$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)"
  for id in omasteam-kcm omasteam-syset; do
    case ",$rules," in *",$id,"*) ;; *) rules="${rules:+$rules,}$id" ;; esac
  done
  kwr General rules "$rules"
  kwr General count "$(awk -F, '{print NF}' <<<"$rules")"
  kwr omasteam-kcm Description "omasteam: generic kcmshell window opens at a sane size"
  kwr omasteam-kcm size "1200,800";  kwr omasteam-kcm sizerule 3
  kwr omasteam-kcm wmclass kcmshell6; kwr omasteam-kcm wmclassmatch 1
  kwr omasteam-kcm wmclasscomplete false; kwr omasteam-kcm types 1
  kwr omasteam-syset Description "omasteam: System Settings opens at a sane size"
  kwr omasteam-syset size "1400,900"; kwr omasteam-syset sizerule 3
  kwr omasteam-syset wmclass systemsettings; kwr omasteam-syset wmclassmatch 1
  kwr omasteam-syset wmclasscomplete false; kwr omasteam-syset types 1
  qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
  # A running Krohnkite only reads its config at script load, and a plain
  # reconfigure (or plugin-flag toggle) does NOT force a re-read — unload the
  # script and let Scripting.start reload it, so config changes apply live.
  qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript krohnkite >/dev/null 2>&1 || true
  qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start 2>/dev/null || true
  ok "Krohnkite installed + enabled"
}

# ----------------------------------------------------------------------------
# 7. Omarchy keybindings -> KDE + Krohnkite
# ----------------------------------------------------------------------------
configure_keybindings() {
  [ "$DO_KEYBINDINGS" = 1 ] || { ok "Keybindings skipped (--no-keybindings)"; return; }
  log "Mapping Omarchy keybindings into KDE + Krohnkite"

  local KGS=kglobalshortcutsrc
  local TAB=$'\t'
  kw()  { kwriteconfig6 --file "$KGS" --group kwin --key "$1" "$2"; }

  # 9 virtual desktops (Super+1..9)
  kwriteconfig6 --file kwinrc --group Desktops --key Number 9
  kwriteconfig6 --file kwinrc --group Desktops --key Rows 1
  for i in 2 3 4 5 6 7 8 9; do
    [ -z "$(kreadconfig6 --file kwinrc --group Desktops --key "Id_$i" 2>/dev/null || true)" ] \
      && kwriteconfig6 --file kwinrc --group Desktops --key "Id_$i" "$(uuidgen)"
  done

  # Focus (Super+arrows, keep Meta+hjkl)
  kw "KrohnkiteFocusLeft"  "Meta+Left${TAB}Meta+H,none,Krohnkite: Focus Left"
  kw "KrohnkiteFocusRight" "Meta+Right${TAB}Meta+L,none,Krohnkite: Focus Right"
  kw "KrohnkiteFocusUp"    "Meta+Up${TAB}Meta+K,none,Krohnkite: Focus Up"
  kw "KrohnkiteFocusDown"  "Meta+Down${TAB}Meta+J,none,Krohnkite: Focus Down"
  # Move/swap (Super+Shift+arrows, keep Meta+Shift+hjkl)
  kw "KrohnkiteShiftLeft"  "Meta+Shift+Left${TAB}Meta+Shift+H,none,Krohnkite: Move Left"
  kw "KrohnkiteShiftRight" "Meta+Shift+Right${TAB}Meta+Shift+L,none,Krohnkite: Move Right"
  kw "KrohnkiteShiftUp"    "Meta+Shift+Up${TAB}Meta+Shift+K,none,Krohnkite: Move Up/Prev"
  kw "KrohnkiteShiftDown"  "Meta+Shift+Down${TAB}Meta+Shift+J,none,Krohnkite: Move Down/Next"
  # Resize (Meta+Ctrl+hjkl). NOT Meta+-/= like Omarchy: KWin's Zoom effect owns
  # Meta+-, Meta+= (and always silently won that conflict, even vs Polonium).
  # NB Krohnkite's action ids really are "growWidth"/"toggleDock" lowercase.
  kw "KrohnkiteShrinkWidth"  "Meta+Ctrl+H,none,Krohnkite: Shrink Width"
  kw "KrohnkitegrowWidth"    "Meta+Ctrl+L,none,Krohnkite: Grow Width"
  kw "KrohnkiteShrinkHeight" "Meta+Ctrl+J,none,Krohnkite: Shrink Height"
  kw "KrohnkiteGrowHeight"   "Meta+Ctrl+K,none,Krohnkite: Grow Height"
  # Float toggle (Super+Shift+V, keep Meta+Shift+Space)
  kw "KrohnkiteToggleFloat" "Meta+Shift+Space${TAB}Meta+Shift+V,none,Krohnkite: Toggle Float"

  # Free Meta+arrows from quick-tile so focus movement wins
  kw "Window Quick Tile Left"   "none,Meta+Left,Quick Tile Window to the Left"
  kw "Window Quick Tile Right"  "none,Meta+Right,Quick Tile Window to the Right"
  kw "Window Quick Tile Top"    "none,Meta+Up,Quick Tile Window to the Top"
  kw "Window Quick Tile Bottom" "none,Meta+Down,Quick Tile Window to the Bottom"

  # Fullscreen + free Meta+T (non-conflicting keys -> file write is fine)
  kw "Window Fullscreen" "Shift+F11,none,Make Window Fullscreen"
  kw "Edit Tiles"        "none,Meta+T,Toggle Tiles Editor"
  # Move-window-to-desktop (Meta+Shift+1..9 is conflict-free -> file is fine)
  for n in 1 2 3 4 5 6 7 8 9; do
    kw "Window to Desktop $n" "Meta+Shift+$n,,Window to Desktop $n"
  done

  # btop launcher target
  cat > ~/.local/share/applications/omarchy-btop.desktop <<EOF
[Desktop Entry]
Type=Application
Name=btop (System Monitor)
Exec=$HOME/.local/bin/kitty -e btop
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
EOF
  update-desktop-database ~/.local/share/applications 2>/dev/null || true

  # --- Everything below MUST go through the live kglobalaccel daemon, not the file. ---
  # Why: (1) the keys we want (Meta+W, Meta+1-9, Meta+B) are owned by Plasma defaults
  # (Overview, Task-Manager entries, Switch Power Profile); a plain file write is silently
  # dropped at login as a "conflict". (2) [services] launcher entries written to the file
  # don't register. setForeignShortcut updates the RUNNING daemon and writes the file, so it
  # sticks across logout AND applies immediately (no relogin). Requires an active session.
  # (3) On a fresh one-shot install, even the "non-conflicting" kwriteconfig6 writes above
  # get CLOBBERED: entries for components the running daemon already registered (kwin core,
  # Krohnkite) live dirty in its memory with their defaults, and the daemon's next settings
  # sync — triggered seconds later by our own setForeignShortcut calls — writes those
  # defaults back over our file edits. So every kwin/Krohnkite bind is re-asserted through
  # the daemon below; the file writes above only matter for the no-dbus fallback path.
  if ! have dbus-send; then
    warn "dbus-send missing / no session — conflicting + launcher shortcuts not set"
    ok "Krohnkite + non-conflicting binds written to file"; return
  fi
  local META=268435456 ALT=134217728 SHIFT=33554432 CTRL=67108864
  local KLEFT=16777234 KUP=16777235 KRIGHT=16777236 KDOWN=16777237 KF11=16777274
  setsc() { # comp action compFriendly actFriendly  keys(comma-sep ints, empty=clear)
    dbus-send --session --type=method_call --dest=org.kde.kglobalaccel \
      /kglobalaccel org.kde.KGlobalAccel.setForeignShortcut \
      array:string:"$1","$2","$3","$4" array:int32:"$5" >/dev/null 2>&1
  }

  # Free the Plasma defaults that collide with Omarchy keys
  setsc "kwin" "Overview" "KWin" "Toggle Overview" ""
  for n in 1 2 3 4 5 6 7 8 9; do
    setsc "plasmashell" "activate task manager entry $n" "plasmashell" "Activate Task Manager Entry $n" ""
  done
  setsc "org_kde_powerdevil" "powerProfile" "Power Management" "Switch Power Profile" ""   # frees Meta+B

  # Free KWin defaults that collide (quick-tile Meta+arrows, tiles editor Meta+T)
  setsc "kwin" "Window Quick Tile Left"   "KWin" "Quick Tile Window to the Left"   ""
  setsc "kwin" "Window Quick Tile Right"  "KWin" "Quick Tile Window to the Right"  ""
  setsc "kwin" "Window Quick Tile Top"    "KWin" "Quick Tile Window to the Top"    ""
  setsc "kwin" "Window Quick Tile Bottom" "KWin" "Quick Tile Window to the Bottom" ""
  setsc "kwin" "Edit Tiles"               "KWin" "Toggle Tiles Editor"             ""
  # Meta+Shift+Left/Right are KWin defaults for prev/next screen — they beat KrohnkiteShift*
  setsc "kwin" "Window to Previous Screen" "KWin" "Window to Previous Screen" ""
  setsc "kwin" "Window to Next Screen"     "KWin" "Window to Next Screen"     ""

  # Clear any binds a pre-Krohnkite omasteam install gave Polonium (its actions
  # linger in kglobalaccel even after the script is disabled and would keep the
  # keys grabbed). No-ops when Polonium was never installed.
  local pa
  for pa in "ActivateLeft:Activate Left" "ActivateRight:Activate Right" \
            "ActivateAbove:Activate Above" "ActivateBelow:Activate Below" \
            "PlaceLeft:Place Window Left" "PlaceRight:Place Window Right" \
            "PlaceAbove:Place Window Above" "PlaceBelow:Place Window Below" \
            "ResizeLeft:Resize Tile Left" "ResizeRight:Resize Tile Right" \
            "ResizeUp:Resize Tile Up" "ResizeDown:Resize Tile Down" \
            "ToggleActiveTiling:Toggle Tiling on Active Window" \
            "ToggleSettingsMenu:Toggle Settings Menu"; do
    setsc "kwin" "Polonium${pa%%:*}" "KWin" "Polonium: ${pa#*:}" ""
  done

  # KWin-core binds that needed a conflict freed
  setsc "kwin" "Window Close" "KWin" "Close Window" "$((META+87)),$((ALT+16777267))"        # Meta+W, Alt+F4
  for n in 1 2 3 4 5 6 7 8 9; do
    setsc "kwin" "Switch to Desktop $n" "KWin" "Switch to Desktop $n" "$((META+48+n))"       # Meta+<n>
  done

  # Re-assert every file-written kwin/Krohnkite bind through the daemon (see comment above)
  setsc "kwin" "KrohnkiteFocusLeft"   "KWin" "Krohnkite: Focus Left"     "$((META+KLEFT)),$((META+72))"
  setsc "kwin" "KrohnkiteFocusRight"  "KWin" "Krohnkite: Focus Right"    "$((META+KRIGHT)),$((META+76))"
  setsc "kwin" "KrohnkiteFocusUp"     "KWin" "Krohnkite: Focus Up"       "$((META+KUP)),$((META+75))"
  setsc "kwin" "KrohnkiteFocusDown"   "KWin" "Krohnkite: Focus Down"     "$((META+KDOWN)),$((META+74))"
  setsc "kwin" "KrohnkiteShiftLeft"   "KWin" "Krohnkite: Move Left"      "$((META+SHIFT+KLEFT)),$((META+SHIFT+72))"
  setsc "kwin" "KrohnkiteShiftRight"  "KWin" "Krohnkite: Move Right"     "$((META+SHIFT+KRIGHT)),$((META+SHIFT+76))"
  setsc "kwin" "KrohnkiteShiftUp"     "KWin" "Krohnkite: Move Up/Prev"   "$((META+SHIFT+KUP)),$((META+SHIFT+75))"
  setsc "kwin" "KrohnkiteShiftDown"   "KWin" "Krohnkite: Move Down/Next" "$((META+SHIFT+KDOWN)),$((META+SHIFT+74))"
  setsc "kwin" "KrohnkiteShrinkWidth"  "KWin" "Krohnkite: Shrink Width"  "$((META+CTRL+72))"  # Meta+Ctrl+H
  setsc "kwin" "KrohnkitegrowWidth"    "KWin" "Krohnkite: Grow Width"    "$((META+CTRL+76))"  # Meta+Ctrl+L
  setsc "kwin" "KrohnkiteShrinkHeight" "KWin" "Krohnkite: Shrink Height" "$((META+CTRL+74))"  # Meta+Ctrl+J
  setsc "kwin" "KrohnkiteGrowHeight"   "KWin" "Krohnkite: Grow Height"   "$((META+CTRL+75))"  # Meta+Ctrl+K
  setsc "kwin" "KrohnkiteToggleFloat"  "KWin" "Krohnkite: Toggle Float"  "$((META+SHIFT+32)),$((META+SHIFT+86))"
  setsc "kwin" "Window Fullscreen" "KWin" "Make Window Fullscreen" "$((SHIFT+KF11))"         # Shift+F11
  for n in 1 2 3 4 5 6 7 8 9; do
    setsc "kwin" "Window to Desktop $n" "KWin" "Window to Desktop $n" "$((META+SHIFT+48+n))" # Meta+Shift+<n>
  done

  # App launchers (via daemon so they actually register). On a FRESH install the daemon's
  # login-time ksycoca snapshot predates the .desktop files we just created (and any
  # just-installed flatpak browser), so these setsc calls silently no-op. The svc() file
  # entry is the safety net: it creates the component at next login, and the autostart
  # rebind (bin/omasteam-rebind-shortcuts) then establishes the real grab. Components the
  # daemon doesn't know are never clobbered by its settings syncs, so the file write is safe.
  svc() { kwriteconfig6 --file "$KGS" --group services --group "$1" --key _launch "$2"; }
  local BROWSER_DESKTOP
  BROWSER_DESKTOP="$(xdg-settings get default-web-browser 2>/dev/null || true)"
  [ -n "$BROWSER_DESKTOP" ] || BROWSER_DESKTOP="org.mozilla.firefox.desktop"
  setsc "kitty.desktop"           "_launch" "kitty"   "Launch kitty" "$((META+16777220))"       # Meta+Return
  setsc "org.kde.dolphin.desktop" "_launch" "Dolphin" "Dolphin"      "$((META+70))"             # Meta+F
  setsc "$BROWSER_DESKTOP"        "_launch" "Browser" "Web Browser"  "$((META+66))"             # Meta+B
  setsc "omarchy-btop.desktop"    "_launch" "btop"    "btop"         "$((META+84))"             # Meta+T
  setsc "org.kde.krunner.desktop" "_launch" "KRunner" "KRunner"      "$((ALT+32))"              # Alt+Space (Meta+Space -> omasteam-apps)
  svc "kitty.desktop"        "Meta+Return,none,Launch kitty"
  svc "omarchy-btop.desktop" "Meta+T,none,btop"
  svc "$BROWSER_DESKTOP"     "Meta+B,none,Web Browser"

  qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
  ok "keybindings applied live via kglobalaccel (browser: $BROWSER_DESKTOP)"
}

# ----------------------------------------------------------------------------
# Phase 2 — omadots terminal/dev environment  (--with-omadots)
# ----------------------------------------------------------------------------
omadots_asset() { # repo  regex -> newest matching browser_download_url
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep -oE '"browser_download_url": *"[^"]+"' | sed 's/.*: *"//;s/"$//' | grep -iE "$2" | head -1
}

install_omadots() {
  [ "$WITH_OMADOTS" = 1 ] || { ok "omadots phase not requested (--with-omadots) — skipping"; return; }
  log "Phase 2: omadots terminal/dev environment"

  # -- CLI toolchain (skip anything already present) --
  local T; T="$(mktemp -d)"; pushd "$T" >/dev/null
  if ! have eza;    then curl -fsSL "$(omadots_asset eza-community/eza 'eza_x86_64-unknown-linux-gnu.tar.gz')" -o e.tgz; tar xzf e.tgz; install -m755 ./eza "$HOME/.local/bin/eza"; ok "eza"; fi
  if ! have bat;    then curl -fsSL "$(omadots_asset sharkdp/bat 'bat-v.*x86_64-unknown-linux-gnu.tar.gz')" -o b.tgz; tar xzf b.tgz; install -m755 "$(find . -name bat -type f -path '*bat-*'|head -1)" "$HOME/.local/bin/bat"; ok "bat"; fi
  if ! have fzf;    then curl -fsSL "$(omadots_asset junegunn/fzf 'fzf-.*linux_amd64.tar.gz')" -o f.tgz; tar xzf f.tgz; install -m755 ./fzf "$HOME/.local/bin/fzf"; ok "fzf"; fi
  if ! have zoxide; then curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh -s -- --bin-dir "$HOME/.local/bin" >/dev/null; ok "zoxide"; fi
  if ! have starship; then curl -sS https://starship.rs/install.sh | sh -s -- --bin-dir "$HOME/.local/bin" --yes >/dev/null; ok "starship"; fi
  popd >/dev/null; rm -rf "$T"; hash -r

  # -- shell configs (2 adaptations: fzf integration, empty-fns guard) --
  mkdir -p ~/.config/shell/fns
  local f; for f in all envs aliases inputrc; do curl -fsSL "$OMADOTS_RAW/shell/$f" -o ~/.config/shell/$f; done
  printf 'for f in "$HOME"/.config/shell/fns/*; do [ -e "$f" ] && source "$f"; done\n' > ~/.config/shell/functions
  curl -fsSL "$OMADOTS_RAW/shell/inits" | sed -e '/if command -v fzf/,/^fi$/c\
if command -v fzf \&>/dev/null; then\
  eval "$(fzf --"$_shell_name")"\
fi' > ~/.config/shell/inits
  ln -sf ~/.config/shell/inputrc ~/.inputrc
  curl -fsSL "$OMADOTS_RAW/starship.toml" -o ~/.config/starship.toml
  mkdir -p ~/.config/btop; curl -fsSL "$OMADOTS_RAW/btop/btop.conf" -o ~/.config/btop/btop.conf
  if ! grep -q "config/shell/all" ~/.bashrc 2>/dev/null; then
    printf '\n# omadots terminal environment (Phase 2)\n[ -f "$HOME/.config/shell/all" ] && source "$HOME/.config/shell/all"\n' >> ~/.bashrc
  fi
  ok "shell wired (eza/bat/fzf/zoxide aliases, official starship, btop theme)"

  # -- neovim + LazyVim --
  if [ "$OMADOTS_NVIM" = 1 ]; then
    if ! have nvim; then
      local NT; NT="$(mktemp -d)"; local NV; NV="$(omadots_asset neovim/neovim 'nvim-linux-x86_64.tar.gz')"; [ -n "$NV" ] || NV="$(omadots_asset neovim/neovim 'nvim-linux64.tar.gz')"
      curl -fsSL "$NV" -o "$NT/nvim.tgz"; rm -rf ~/.local/nvim; mkdir -p ~/.local/nvim
      tar xzf "$NT/nvim.tgz" -C ~/.local/nvim --strip-components=1; ln -sf ~/.local/nvim/bin/nvim "$HOME/.local/bin/nvim"; rm -rf "$NT"; hash -r
    fi
    if [ ! -e ~/.config/nvim/init.lua ]; then
      git clone --depth 1 https://github.com/LazyVim/starter ~/.config/nvim >/dev/null 2>&1
      rm -rf ~/.config/nvim/.git
      curl -fsSL "$OMADOTS_RAW/nvim/lazyvim.json" -o ~/.config/nvim/lazyvim.json
      log "bootstrapping LazyVim plugins (headless, ~1-2 min)"
      timeout 300 nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || true
    fi
    # Super+N launcher. The running kglobalaccel has a login-time service cache, so a
    # brand-new .desktop can't bind live — write the file (registers next login) + try live.
    cat > ~/.local/share/applications/omarchy-nvim.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Neovim
Exec=$HOME/.local/bin/kitty -e $HOME/.local/bin/nvim
Icon=nvim
Terminal=false
Categories=Development;Utility;
EOF
    update-desktop-database ~/.local/share/applications 2>/dev/null || true
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    kwriteconfig6 --file kglobalshortcutsrc --group services --group omarchy-nvim.desktop --key _launch "Meta+N,none,Neovim"
    have dbus-send && dbus-send --session --type=method_call --dest=org.kde.kglobalaccel /kglobalaccel \
      org.kde.KGlobalAccel.setForeignShortcut \
      array:string:"omarchy-nvim.desktop","_launch","Neovim","Neovim" array:int32:268435534 >/dev/null 2>&1 || true
    ok "neovim + LazyVim ready; Super+N binds at next login"
  else
    ok "neovim skipped (--omadots-no-nvim)"
  fi
}

# ----------------------------------------------------------------------------
# omasteam bar — Omarchy-4-style QML top bar (--with-bar)
# ----------------------------------------------------------------------------
# A wlr-layer-shell surface written in pure QML, run by SteamOS's stock Qt6 via
# `qmlscene` + the org.kde.layershell module. No Quickshell, no compiling, no
# sudo. A companion daemon feeds it live state (clock, workspaces, volume,
# network, battery) and the active omasteam theme palette; the bar reads that
# over a Timer and pushes clicks back through a SQLite outbox.
install_bar() {
  [ "$WITH_BAR" = 1 ] || { ok "bar not requested (--with-bar) — skipping"; return; }

  # Hard dependencies, all shipped with SteamOS's KDE — but verify.
  local qs; qs="$(command -v qmlscene6 || command -v qmlscene || true)"
  [ -n "$qs" ] || { warn "qmlscene(6) not found — cannot install the bar"; return; }
  [ -d /usr/lib/qt6/qml/org/kde/layershell ] \
    || [ -d /usr/lib/qt/qml/org/kde/layershell ] \
    || { warn "org.kde.layershell QML module missing — cannot install the bar"; return; }

  log "Installing omasteam bar (QML layer-shell)"
  local share="$HOME/.local/share/omasteam/bar"
  mkdir -p "$share"
  install -m644 "$ART/bar/omasteam-bar.qml"     "$share/omasteam-bar.qml"
  install -m755 "$SCRIPT_DIR/bin/omasteam-bar"        "$HOME/.local/bin/omasteam-bar"
  install -m755 "$SCRIPT_DIR/bin/omasteam-bar-daemon" "$HOME/.local/bin/omasteam-bar-daemon"
  # Keep a copy of the QML beside the installed scripts too (the launcher looks
  # here when run outside the repo checkout).
  install -m755 "$SCRIPT_DIR/bin/omasteam-bar-daemon" "$share/omasteam-bar-daemon"

  # ---- system menu (Omarchy-style, Meta+Alt+Space) ----
  # Same QML-front / bash-back split as the bar: a layer-shell overlay driven by
  # the omasteam-menu launcher, which also dispatches the chosen action.
  install -m644 "$ART/bar/omasteam-menu.qml" "$share/omasteam-menu.qml"
  install -m755 "$SCRIPT_DIR/bin/omasteam-menu" "$HOME/.local/bin/omasteam-menu"
  # Launcher target for the KDE global shortcut (absolute Exec, like the bar's
  # autostart — the session PATH has no ~/.local/bin).
  cat > ~/.local/share/applications/omasteam-menu.desktop <<EOF
[Desktop Entry]
Type=Application
Name=omasteam Menu
Comment=Omarchy-style system menu (Meta+Alt+Space)
Exec=$HOME/.local/bin/omasteam-menu
Icon=applications-system
Terminal=false
Categories=System;
NoDisplay=true
EOF
  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  # Bind Meta+Alt+Space -> the menu launcher. A brand-new .desktop can't bind
  # live (this session's ksycoca predates it), so write the file entry (registers
  # at next login) AND try live; the omasteam-rebind autostart re-asserts the grab.
  # Keycode 402653216 = Meta(0x10000000)+Alt(0x08000000)+Space(0x20).
  kwriteconfig6 --file kglobalshortcutsrc --group services \
    --group omasteam-menu.desktop --key _launch "Meta+Alt+Space,none,omasteam Menu"
  if have dbus-send; then
    # doRegister CREATES the launcher's kglobalaccel component so the grab
    # attaches in THIS session. Without it, a brand-new .desktop's shortcut only
    # binds after the next login (kglobalaccel, hosted in kwin, reads the
    # [services] file just at session start). setForeignShortcut then assigns the
    # key. kbuildsycoca6 first so the freshly-written .desktop is resolvable.
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    dbus-send --session --type=method_call --dest=org.kde.kglobalaccel /kglobalaccel \
      org.kde.KGlobalAccel.doRegister \
      array:string:"omasteam-menu.desktop","_launch","omasteam Menu","omasteam Menu" >/dev/null 2>&1 || true
    dbus-send --session --type=method_call --dest=org.kde.kglobalaccel /kglobalaccel \
      org.kde.KGlobalAccel.setForeignShortcut \
      array:string:"omasteam-menu.desktop","_launch","omasteam Menu","omasteam Menu" \
      array:int32:402653216 >/dev/null 2>&1 || true
  fi
  ok "system menu installed; Meta+Alt+Space bound (live + persisted)"

  # ---- app launcher (Omarchy-style, Meta+Space) ----
  # Separate from the system menu: omasteam-apps is JUST the .desktop app picker.
  install -m644 "$ART/bar/omasteam-apps.qml" "$share/omasteam-apps.qml"
  install -m755 "$SCRIPT_DIR/bin/omasteam-apps" "$HOME/.local/bin/omasteam-apps"
  cat > ~/.local/share/applications/omasteam-apps.desktop <<EOF
[Desktop Entry]
Type=Application
Name=omasteam Apps
Comment=Omarchy-style application launcher (Meta+Space)
Exec=$HOME/.local/bin/omasteam-apps
Icon=applications-all
Terminal=false
Categories=System;
NoDisplay=true
EOF
  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  # Bind Meta+Space -> the app launcher (krunner is moved to Alt+Space only in
  # configure_keybindings so this key is free). Keycode 268435488 = Meta+Space.
  # Same doRegister-then-setForeignShortcut dance as the system menu so the grab
  # attaches live; the rebind autostart re-asserts it at login.
  kwriteconfig6 --file kglobalshortcutsrc --group services \
    --group omasteam-apps.desktop --key _launch "Meta+Space,none,omasteam Apps"
  if have dbus-send; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    dbus-send --session --type=method_call --dest=org.kde.kglobalaccel /kglobalaccel \
      org.kde.KGlobalAccel.doRegister \
      array:string:"omasteam-apps.desktop","_launch","omasteam Apps","omasteam Apps" >/dev/null 2>&1 || true
    dbus-send --session --type=method_call --dest=org.kde.kglobalaccel /kglobalaccel \
      org.kde.KGlobalAccel.setForeignShortcut \
      array:string:"omasteam-apps.desktop","_launch","omasteam Apps","omasteam Apps" \
      array:int32:268435488 >/dev/null 2>&1 || true
  fi
  ok "app launcher installed; Meta+Space bound (live + persisted)"

  # Autostart at login (KDE Wayland). Exec MUST be an absolute path: the
  # graphical session's PATH does not include ~/.local/bin (that's added by
  # .bashrc, which autostart never sources), so a bare "omasteam-bar" is not
  # found and nothing launches — notably after a Game Mode → Desktop switch,
  # which restarts the Plasma session.
  mkdir -p ~/.config/autostart
  cat > ~/.config/autostart/omasteam-bar.desktop <<EOF
[Desktop Entry]
Type=Application
Name=omasteam bar
Comment=Omarchy-style top bar (QML layer-shell) for SteamOS + KDE
Exec=$HOME/.local/bin/omasteam-bar
Terminal=false
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
NoDisplay=true
EOF
  ok "bar + daemon installed; autostarts at next login"

  # Start it now so the change is visible without a relogin. setsid fully
  # detaches it into its own session so it survives this script and isn't tied
  # to the caller's process group.
  if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    setsid "$HOME/.local/bin/omasteam-bar" restart >/dev/null 2>&1 </dev/null &
    ok "bar started (live)"
  fi
}

# ----------------------------------------------------------------------------
# Move the Plasma panel (taskbar) to the top of the screen (Omarchy-style)
# ----------------------------------------------------------------------------
configure_panel() {
  # Plasma Style -> Breeze "default" so the panel/taskbar FOLLOWS the color scheme.
  # (SteamOS ships the fixed "Vapor" style, which ignores themes — panel never recolors.)
  if have plasma-apply-desktoptheme; then
    plasma-apply-desktoptheme default >/dev/null 2>&1 \
      && ok "Plasma Style set to Breeze (panel follows the theme color scheme)" \
      || warn "could not set Plasma Style"
  fi
  have qdbus6 || { warn "qdbus6 missing — leaving panel position as-is"; return; }
  # Back up the panel layout once so removal/relocation is reversible.
  local cfg="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  local bk="$HOME/.config/omasteam-panel-backup.appletsrc"
  [ -f "$cfg" ] && [ ! -f "$bk" ] && cp -f "$cfg" "$bk" \
    && ok "Plasma panel layout backed up ($bk)"
  # With the omasteam bar installed it OWNS the desktop chrome, Omarchy-style —
  # so the stock Plasma panel is removed entirely (no bottom taskbar). This
  # drops Plasma's system tray; omasteam-bar carries network/volume/battery/
  # power/return-to-gaming/menu instead. Restore with the backup above, or:
  #   qdbus6 org.kde.plasmashell /PlasmaShell evaluateScript 'var p=new Panel; p.location="bottom"'
  # Without the bar, the Plasma panel just moves to the top (Omarchy-style).
  # Live via plasmashell scripting — editing appletsrc directly gets clobbered.
  if [ "$WITH_BAR" = 1 ]; then
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
      'panels().forEach(function(p){ p.remove() })' >/dev/null 2>&1 \
      && ok "Plasma panel removed (omasteam bar owns the desktop)" \
      || warn "could not remove panel (plasmashell not running?)"
  else
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
      'var p = panels(); for (var i = 0; i < p.length; i++) { p[i].location = "top"; }' >/dev/null 2>&1 \
      && ok "Plasma panel moved to top" || warn "could not move panel (plasmashell not running?)"
  fi
  # No launch feedback: kill the bouncing busy-cursor (and taskbar pulse) shown
  # while an app starts — e.g. the cog that bounces after picking a settings
  # entry in the omasteam menu. On Plasma 6 Wayland the feedback is drawn by
  # PLASMASHELL, which reads klaunchrc only at startup — restart it (after the
  # panel scripting above; the layout persists in appletsrc) so the change
  # applies now instead of at the next login.
  kwriteconfig6 --file klaunchrc --group FeedbackStyle --key BusyCursor false
  kwriteconfig6 --file klaunchrc --group FeedbackStyle --key TaskbarButton false
  kwriteconfig6 --file klaunchrc --group BusyCursorSettings --key Bouncing false
  systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1 || true
  ok "Launch feedback disabled (no bouncing cursor)"
}

# ----------------------------------------------------------------------------
# Theme switcher (omasteam-theme) + optional --theme apply
# ----------------------------------------------------------------------------
# NOTE: icon theming intentionally omitted — we keep the system's generic KDE (Breeze)
# icons. (Yaru brought the Ubuntu distributor logo into the app launcher.)
install_theme_tool() {
  if [ -f "$SCRIPT_DIR/bin/omasteam-theme" ]; then
    install -m755 "$SCRIPT_DIR/bin/omasteam-theme" "$HOME/.local/bin/omasteam-theme"
    [ -f "$SCRIPT_DIR/bin/theme" ] && install -m755 "$SCRIPT_DIR/bin/theme" "$HOME/.local/bin/theme"
    ok "installed omasteam-theme + 'theme' shortcut (type 'theme <git-url>' to re-theme)"
  else
    warn "bin/omasteam-theme not found — theme switcher not installed"; return
  fi

  # Meta+Ctrl+Space -> cycle the current theme's wallpapers (Omarchy's background combo).
  # Same ksycoca caveat as Super+N: binds at next login (file written now).
  cat > ~/.local/share/applications/omasteam-wallpaper-next.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Next Wallpaper (omasteam)
Exec=$HOME/.local/bin/omasteam-theme wallpaper next
Icon=preferences-desktop-wallpaper
Terminal=false
NoDisplay=true
Categories=Utility;
EOF
  update-desktop-database ~/.local/share/applications 2>/dev/null || true
  kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  kwriteconfig6 --file kglobalshortcutsrc --group services --group omasteam-wallpaper-next.desktop --key _launch "Meta+Ctrl+Space,none,Next Wallpaper"
  have dbus-send && dbus-send --session --type=method_call --dest=org.kde.kglobalaccel /kglobalaccel \
    org.kde.KGlobalAccel.setForeignShortcut \
    array:string:"omasteam-wallpaper-next.desktop","_launch","Next Wallpaper","Next Wallpaper" array:int32:335544352 >/dev/null 2>&1 || true
  ok "Meta+Ctrl+Space -> next wallpaper (binds at next login)"

  # Custom .desktop launchers (Super+N, Meta+Ctrl+Space) load from the file as
  # "reserved but not grabbed" — a login-time daemon rebind makes them actually fire.
  if [ -f "$SCRIPT_DIR/bin/omasteam-rebind-shortcuts" ]; then
    install -m755 "$SCRIPT_DIR/bin/omasteam-rebind-shortcuts" "$HOME/.local/bin/omasteam-rebind-shortcuts"
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/omasteam-rebind.desktop <<EOF
[Desktop Entry]
Type=Application
Name=omasteam rebind shortcuts
Exec=$HOME/.local/bin/omasteam-rebind-shortcuts
X-KDE-autostart-phase=2
NoDisplay=true
EOF
    ok "login-time shortcut rebind installed (fixes Super+N / Meta+Ctrl+Space after relogin)"
  fi

  if [ -n "$THEME_URL" ]; then
    log "applying theme: $THEME_URL"
    "$HOME/.local/bin/omasteam-theme" install "$THEME_URL" || warn "theme apply failed"
  fi
}

# ----------------------------------------------------------------------------
# Run
# ----------------------------------------------------------------------------
preflight
install_kitty
set_default_terminal
install_font
install_kitty_config
install_starship
install_krohnkite
configure_keybindings
install_bar
configure_panel
install_omadots
install_theme_tool

cat <<'EOF'

──────────────────────────────────────────────
 omasteam setup complete.
 ➜  Keyboard shortcuts were applied LIVE (kglobalaccel) — test them now.
 ➜  LOG OUT / back in (or reboot) to finish activating:
      • $TERMINAL=kitty and the Run-In-kitty service menu
      • Krohnkite arrow-key binds + the 9 virtual desktops
      • (with --with-omadots) Super+N → nvim
 ➜  In a running kitty, Ctrl+Shift+F5 reloads its config.
 ➜  (with --with-omadots) open a new kitty or `source ~/.bashrc` for the shell env.

 Want a theme? Pick any Omarchy theme whenever you like:
   theme <omarchy-theme-git-url>      (e.g. an omarchy-*-theme GitHub URL)
   theme                              (list installed · switch with: theme <name>)
──────────────────────────────────────────────
EOF
