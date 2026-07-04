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
THEME_URL=""

KITTY_VERSION_PIN=""          # empty = latest via official installer
POLONIUM_VERSION="v1.2.0"     # pin the KWin script release
OMADOTS_RAW="https://raw.githubusercontent.com/omacom-io/omadots/master/config"

while [ $# -gt 0 ]; do
  case "$1" in
    --with-starship)   WITH_STARSHIP=1 ;;
    --with-omadots)    WITH_OMADOTS=1 ;;
    --omadots-no-nvim) OMADOTS_NVIM=0 ;;
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
# 6. Polonium (auto-tiling KWin script)
# ----------------------------------------------------------------------------
install_polonium() {
  log "Installing Polonium $POLONIUM_VERSION (auto-tiling)"
  local tmp; tmp="$(mktemp -d)"
  curl -fL -o "$tmp/polonium.kwinscript" \
    "https://github.com/zeroxoneafour/polonium/releases/download/$POLONIUM_VERSION/polonium.kwinscript"
  if [ -d ~/.local/share/kwin/scripts/polonium ]; then
    kpackagetool6 --type=KWin/Script --upgrade "$tmp/polonium.kwinscript" >/dev/null
  else
    kpackagetool6 --type=KWin/Script --install "$tmp/polonium.kwinscript" >/dev/null
  fi
  rm -rf "$tmp"
  kwriteconfig6 --file kwinrc --group Plugins --key poloniumEnabled true
  qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
  ok "Polonium installed + enabled"
}

# ----------------------------------------------------------------------------
# 7. Omarchy keybindings -> KDE + Polonium
# ----------------------------------------------------------------------------
configure_keybindings() {
  [ "$DO_KEYBINDINGS" = 1 ] || { ok "Keybindings skipped (--no-keybindings)"; return; }
  log "Mapping Omarchy keybindings into KDE + Polonium"

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
  kw "PoloniumActivateLeft"  "Meta+Left${TAB}Meta+H,none,Polonium: Activate Left"
  kw "PoloniumActivateRight" "Meta+Right${TAB}Meta+L,none,Polonium: Activate Right"
  kw "PoloniumActivateAbove" "Meta+Up${TAB}Meta+K,none,Polonium: Activate Above"
  kw "PoloniumActivateBelow" "Meta+Down${TAB}Meta+J,none,Polonium: Activate Below"
  # Move/swap (Super+Shift+arrows, keep Meta+Shift+hjkl)
  kw "PoloniumPlaceLeft"  "Meta+Shift+Left${TAB}Meta+Shift+H,none,Polonium: Place Window Left"
  kw "PoloniumPlaceRight" "Meta+Shift+Right${TAB}Meta+Shift+L,none,Polonium: Place Window Right"
  kw "PoloniumPlaceAbove" "Meta+Shift+Up${TAB}Meta+Shift+K,none,Polonium: Place Window Above"
  kw "PoloniumPlaceBelow" "Meta+Shift+Down${TAB}Meta+Shift+J,none,Polonium: Place Window Below"
  # Resize (Super+ -/=, keep Meta+Ctrl+hjkl)
  kw "PoloniumResizeLeft"  "Meta+Ctrl+H${TAB}Meta+Minus,none,Polonium: Resize Tile Left"
  kw "PoloniumResizeRight" "Meta+Ctrl+L${TAB}Meta+Equal,none,Polonium: Resize Tile Right"
  # Float toggle (Super+Shift+V, keep Meta+Shift+Space)
  kw "PoloniumToggleActiveTiling" "Meta+Shift+Space${TAB}Meta+Shift+V,none,Polonium: Toggle Tiling on Active Window"

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
  # Polonium) live dirty in its memory with their defaults, and the daemon's next settings
  # sync — triggered seconds later by our own setForeignShortcut calls — writes those
  # defaults back over our file edits. So every kwin/Polonium bind is re-asserted through
  # the daemon below; the file writes above only matter for the no-dbus fallback path.
  if ! have dbus-send; then
    warn "dbus-send missing / no session — conflicting + launcher shortcuts not set"
    ok "Polonium + non-conflicting binds written to file"; return
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
  # Meta+Shift+Left/Right are KWin defaults for prev/next screen — they beat PoloniumPlace*
  setsc "kwin" "Window to Previous Screen" "KWin" "Window to Previous Screen" ""
  setsc "kwin" "Window to Next Screen"     "KWin" "Window to Next Screen"     ""

  # KWin-core binds that needed a conflict freed
  setsc "kwin" "Window Close" "KWin" "Close Window" "$((META+87)),$((ALT+16777267))"        # Meta+W, Alt+F4
  for n in 1 2 3 4 5 6 7 8 9; do
    setsc "kwin" "Switch to Desktop $n" "KWin" "Switch to Desktop $n" "$((META+48+n))"       # Meta+<n>
  done

  # Re-assert every file-written kwin/Polonium bind through the daemon (see comment above)
  setsc "kwin" "PoloniumActivateLeft"  "KWin" "Polonium: Activate Left"  "$((META+KLEFT)),$((META+72))"
  setsc "kwin" "PoloniumActivateRight" "KWin" "Polonium: Activate Right" "$((META+KRIGHT)),$((META+76))"
  setsc "kwin" "PoloniumActivateAbove" "KWin" "Polonium: Activate Above" "$((META+KUP)),$((META+75))"
  setsc "kwin" "PoloniumActivateBelow" "KWin" "Polonium: Activate Below" "$((META+KDOWN)),$((META+74))"
  setsc "kwin" "PoloniumPlaceLeft"  "KWin" "Polonium: Place Window Left"  "$((META+SHIFT+KLEFT)),$((META+SHIFT+72))"
  setsc "kwin" "PoloniumPlaceRight" "KWin" "Polonium: Place Window Right" "$((META+SHIFT+KRIGHT)),$((META+SHIFT+76))"
  setsc "kwin" "PoloniumPlaceAbove" "KWin" "Polonium: Place Window Above" "$((META+SHIFT+KUP)),$((META+SHIFT+75))"
  setsc "kwin" "PoloniumPlaceBelow" "KWin" "Polonium: Place Window Below" "$((META+SHIFT+KDOWN)),$((META+SHIFT+74))"
  setsc "kwin" "PoloniumResizeLeft"  "KWin" "Polonium: Resize Tile Left"  "$((META+CTRL+72)),$((META+45))"  # Meta+Ctrl+H, Meta+-
  setsc "kwin" "PoloniumResizeRight" "KWin" "Polonium: Resize Tile Right" "$((META+CTRL+76)),$((META+61))"  # Meta+Ctrl+L, Meta+=
  setsc "kwin" "PoloniumToggleActiveTiling" "KWin" "Polonium: Toggle Tiling on Active Window" "$((META+SHIFT+32)),$((META+SHIFT+86))"
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
  setsc "org.kde.krunner.desktop" "_launch" "KRunner" "KRunner"      "$((META+32)),$((ALT+32))" # Meta+Space, Alt+Space
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
  # Move the panel to the top. Live via plasmashell scripting (editing appletsrc gets clobbered).
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    'var p = panels(); for (var i = 0; i < p.length; i++) { p[i].location = "top"; }' >/dev/null 2>&1 \
    && ok "Plasma panel moved to top" || warn "could not move panel (plasmashell not running?)"
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
install_polonium
configure_keybindings
configure_panel
install_omadots
install_theme_tool

cat <<'EOF'

──────────────────────────────────────────────
 omasteam setup complete.
 ➜  Keyboard shortcuts were applied LIVE (kglobalaccel) — test them now.
 ➜  LOG OUT / back in (or reboot) to finish activating:
      • $TERMINAL=kitty and the Run-In-kitty service menu
      • Polonium arrow-key binds + the 9 virtual desktops
      • (with --with-omadots) Super+N → nvim
 ➜  In a running kitty, Ctrl+Shift+F5 reloads its config.
 ➜  (with --with-omadots) open a new kitty or `source ~/.bashrc` for the shell env.

 Want a theme? Pick any Omarchy theme whenever you like:
   theme <omarchy-theme-git-url>      (e.g. an omarchy-*-theme GitHub URL)
   theme                              (list installed · switch with: theme <name>)
──────────────────────────────────────────────
EOF
