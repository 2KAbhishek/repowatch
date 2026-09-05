<div align = "center">

<h1><a href="https://github.com/2kabhishek/repowatch">repowatch</a></h1>

<a href="https://github.com/2KAbhishek/repowatch/blob/main/LICENSE">
<img alt="License" src="https://img.shields.io/github/license/2kabhishek/repowatch?style=flat&color=eee&label="> </a>

<a href="https://github.com/2KAbhishek/repowatch/graphs/contributors">
<img alt="People" src="https://img.shields.io/github/contributors/2kabhishek/repowatch?style=flat&color=ffaaf2&label=People"> </a>

<a href="https://github.com/2KAbhishek/repowatch/stargazers">
<img alt="Stars" src="https://img.shields.io/github/stars/2kabhishek/repowatch?style=flat&color=98c379&label=Stars"></a>

<a href="https://github.com/2KAbhishek/repowatch/network/members">
<img alt="Forks" src="https://img.shields.io/github/forks/2kabhishek/repowatch?style=flat&color=66a8e0&label=Forks"> </a>

<a href="https://github.com/2KAbhishek/repowatch/watchers">
<img alt="Watches" src="https://img.shields.io/github/watchers/2kabhishek/repowatch?style=flat&color=f5d08b&label=Watches"> </a>

<a href="https://github.com/2KAbhishek/repowatch/pulse">
<img alt="Last Updated" src="https://img.shields.io/github/last-commit/2kabhishek/repowatch?style=flat&color=e06c75&label="> </a>

<h3>Interactive Multi-Repo Monitor 📡📁</h3>

<figure>
  <img src="images/screenshot.png" alt="repowatch in action">
  <br/>
  <figcaption>repowatch in action</figcaption>
</figure>

</div>

**repowatch** is an interactive multi-repository dashboard and [lazygit](https://github.com/jesseduffield/lazygit) launcher. When run inside any directory:

- **If it's already a Git repository**: launches `lazygit` directly.
- **If it's a parent workspace**: concurrently scans all nested repositories, displays their health/status badges (`clean`, `staged`, `unstaged`, `untracked`, `ahead/behind`), and lets you seamlessly jump into `lazygit` on any repo and return with live-refreshed status.

## ✨ Features

- ⚡ **Instant Multi-Repo Overview**: Concurrent status scanning across dozens of repositories in milliseconds.
- 🎯 **Direct Pass-Through**: Opens `lazygit` immediately if invoked inside a single Git repository.
- 🔍 **Interactive TUI**: Powered by `fzf` with live previews showing branch status, recent commit graph, and working tree diffs.
- 🚦 **Dirty Repo Filtering**: Instant toggle to focus only on repositories needing attention.
- 🔄 **Seamless Loop**: Launch `lazygit` or `$EDITOR` and return right back to your dashboard with auto-refreshed states.

## ⚡ Setup

### ⚙️ Requirements

- `git`
- `lazygit`
- `fzf`

### 💻 Installation

```bash
git clone https://github.com/2kabhishek/repowatch
cd repowatch

# Automated setup
./setup.sh

# Or manual symlink
ln -sfnv "$PWD/repowatch.sh" ~/.local/bin/repowatch
```

## 🚀 Usage

```bash
# Scan current directory (or launch lazygit if inside a repo)
repowatch

# Scan a specific directory
repowatch ~/Projects

# Show only repositories with uncommitted or unpushed changes
repowatch -d

# Scan recursively with custom depth
repowatch -r 5 ~/Workspaces

# Force overview mode even if inside a Git repository
repowatch -o
```

### ⌨️ Keybindings

| Key                  | Action                                                                 |
| :------------------- | :--------------------------------------------------------------------- |
| `<Enter>`            | **View**: Open repository in `view_tool` (default: `lazygit`, `tig`)   |
| `<Ctrl-D>`           | **Dirty**: Toggle filter for dirty repositories                        |
| `<Ctrl-E>`           | **Edit**: Open repository in `edit_tool` (`$EDITOR` / `nvim` / `vim`)  |
| `<Ctrl-G>`           | **Web**: Open repository remote URL in browser                         |
| `<Ctrl-O>`           | **Terminal**: Open interactive subshell in repository                  |
| `<Ctrl-R>`           | **Refresh**: Fast local rescan of repository statuses                  |
| `<Ctrl-S>`           | **Sync**: Pull upstream changes & push commits across all repositories |
| `<Ctrl-U>`           | **Upstream**: Fetch remote tracking branches across all repositories   |
| `<Esc>` / `<Ctrl-C>` | **Quit**: Exit `repowatch`                                             |

### ⚙️ Configuration

`repowatch` can be customized using a simple configuration file located at `~/.config/repowatch/config` or `~/.repowatchrc`.

To generate a starter configuration file with all available options:

```bash
repowatch -i  # or: repowatch --init-config
```

Example configuration (`~/.config/repowatch/config`):

```ini
# Column Widths
repo_width = 22
status_width = 10
branch_width = 10
date_width = 7
commit_width = 48

# Scan Settings
max_depth = 3
parallel_jobs = 16
dirty_only = false
recursive = false
preview_percent = 50

# Tools
view_tool = lazygit   # lazygit, tig, gitui, or any git viewer
edit_tool = nvim      # defaults to $EDITOR, nvim, vim, or nano

# Icons & Badges (Nerd Fonts)
icon_clean = 
icon_dirty = 
icon_ahead = 
icon_behind = 
icon_view = 
icon_edit = 
icon_web = 󰖟
icon_shell = 
icon_refresh = 󰑓
icon_sync = 
icon_upstream = 󰜮
```

## 🏗️ What's Next

- You tell me!

## 🧑‍💻 Behind The Code

### 🌈 Inspiration

Managing dozens of local repositories across workspaces makes it easy to lose track of uncommitted experiments, stash remnants, or unpushed commits. `repowatch` bridges the gap between workspace oversight and repo-level TUI operations.

### 🧰 Tooling

- [dots2k](https://github.com/2kabhishek/dots2k) — Dev Environment
- [nvim2k](https://github.com/2kabhishek/nvim2k) — Personalized Editor
- [sway2k](https://github.com/2kabhishek/sway2k) — Desktop Environment
- [qute2k](https://github.com/2kabhishek/qute2k) — Personalized Browser

### 🔍 More Info

- [bare-minimum](https://github.com/2kabhishek/bare-minimum) — General purpose template
- [gh-repo-man](https://github.com/2kabhishek/gh-repo-man) — GitHub repo manager

<hr>

<div align="center">

<strong>⭐ hit the star button if you found this useful ⭐</strong><br>

<a href="https://github.com/2KAbhishek/repowatch">Source</a>
| <a href="https://2kabhishek.github.io/blog" target="_blank">Blog </a>
| <a href="https://twitter.com/2kabhishek" target="_blank">Twitter </a>
| <a href="https://linkedin.com/in/2kabhishek" target="_blank">LinkedIn </a>
| <a href="https://2kabhishek.github.io/links" target="_blank">More Links </a>
| <a href="https://2kabhishek.github.io/projects" target="_blank">Other Projects </a>

</div>
