# omasteam

An Omarchy-flavored desktop for the **Steam Deck** (SteamOS + KDE Plasma 6, Wayland) —
reproduced entirely in **userland** (`~/.local`), since SteamOS's root filesystem is
read-only. No `pacman`, no `sudo`, survives OS updates.

Gives you: **kitty** as the default terminal (JetBrainsMono, hidden tab bar, live theme),
**Polonium** auto-tiling, the full **Omarchy keybinding** set on KDE, an **omadots**
terminal environment (eza/bat/fzf/zoxide/neovim+LazyVim/starship), and a one-command
**theme switcher** that re-themes the *whole* system from any Omarchy theme's git URL.

> **Unofficial & unaffiliated.** This is an independent hobby project. It is **not**
> affiliated with, endorsed by, or connected to Omarchy, Basecamp, or DHH — it just
> brings an Omarchy-style look/workflow to SteamOS + KDE. Names and themes belong to
> their respective owners. See [LICENSE](LICENSE).

## Quick start

```bash
git clone <this-repo-url> ~/omasteam
cd ~/omasteam
./install.sh --with-omadots
# then LOG OUT / reboot
```

## Bootstrapping a freshly-flashed Steam Deck (private repo)

Desktop Mode → Konsole. Since the repo is private, install `gh` and auth first:

```bash
mkdir -p ~/.local/bin && export PATH="$HOME/.local/bin:$PATH"
cd /tmp && curl -fsSL "$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
  | grep -oE 'https://[^\"]+_linux_amd64\.tar\.gz' | head -1)" -o gh.tgz \
  && tar xzf gh.tgz && install -m755 gh_*/bin/gh ~/.local/bin/gh

gh auth login                       # GitHub.com → HTTPS → login with a web browser
gh repo clone 28allday/omasteam ~/omasteam
cd ~/omasteam && ./install.sh --with-omadots
# reboot, then pick a theme:  theme omarchy tokyo-night
```

(Alternative: temporarily flip the repo to public, `git clone https://…`, flip back —
no `gh`/token needed.)

**Themes are optional and up to you** — the install doesn't apply one. After the reboot,
pick any Omarchy theme whenever you like:

```bash
theme https://github.com/OldJobobo/omarchy-miasma-theme.git   # paste any omarchy-*-theme URL
```

(You *can* apply one during install with `--theme <git-url>`, but it's not the default.)

Reboot once — that's required, not optional. It activates the login-gated pieces
(`$TERMINAL`, the Run-In-kitty menu, Polonium's arrow binds, the 9 virtual desktops, and
the autostart that grabs the launcher shortcuts). After the reboot, everything works.

## Flags

| Flag | Effect |
|------|--------|
| *(none)* | Desktop only: kitty, default-terminal, font, Polonium, keybinds |
| `--with-omadots` | + terminal/dev env (eza, bat, fzf, zoxide, neovim/LazyVim, starship, shell) |
| `--omadots-no-nvim` | with `--with-omadots`, skip neovim/LazyVim |
| `--theme <git-url>` | install the theme switcher and apply this Omarchy theme |
| `--with-starship` | standalone starship (implied by `--with-omadots`) |
| `--force-kitty` | reinstall kitty even if present |
| `-h`, `--help` | usage |

Idempotent — safe to re-run.

## Requirements

- SteamOS / KDE Plasma 6 **Wayland** session (uses live D-Bus / kglobalaccel)
- Network (downloads kitty, fonts, CLI tools, and the theme repo)
- Stock tools: `curl unzip git kwriteconfig6 qdbus6 kpackagetool6 uuidgen`

## Theming — after install

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

## Key bindings (Omarchy-style)

`Super+Return` kitty · `Super+Space` KRunner · `Super+F` files · `Super+B` browser ·
`Super+T` btop · `Super+N` neovim · `Super+W` close · `Super+1..9` workspaces ·
`Super+Shift+1..9` move-to-workspace · `Super+arrows` focus · `Super+Shift+arrows` move ·
`Super+Shift+V` float · `Shift+F11` fullscreen · `Meta+Ctrl+Space` next wallpaper.

## Layout

```
install.sh        one idempotent entry point (desktop + terminal + theming)
bin/              omasteam-theme, theme (wrapper), omasteam-rebind-shortcuts
artifacts/        static config files copied into place (kitty.conf, service menu, …)
```

Everything installs into `~/.local` and is safe to re-run. Built for SteamOS's
immutable root — no `pacman`, no `sudo`.
