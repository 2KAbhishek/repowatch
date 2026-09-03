#!/usr/bin/env bash
set -e

current_dir="${BASH_SOURCE[0]%/*}"
[[ "$current_dir" == "${BASH_SOURCE[0]}" || "$current_dir" == "." ]] && current_dir="$PWD"

for cmd in git fzf lazygit; do
    command -v "$cmd" &>/dev/null || echo "Warning: '$cmd' is not installed."
done

mkdir -p "$HOME/.local/bin"
ln -sfnv "$current_dir/repowatch.sh" "$HOME/.local/bin/repowatch"

echo "repowatch setup completed successfully!"
