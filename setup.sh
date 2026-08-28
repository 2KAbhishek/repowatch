#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

get_system_info() {
    [ -e /etc/os-release ] && source /etc/os-release && echo "${ID:-Unknown}" && return
    [ -e /etc/lsb-release ] && source /etc/lsb-release && echo "${DISTRIB_ID:-Unknown}" && return
    [ "$(uname)" == "Darwin" ] && echo "mac" && return
    [ "$(uname -o 2>/dev/null)" == "Android" ] && echo "termux" && return
    echo "unknown"
}

install_packages() {
    local sys_kind
    sys_kind=$(get_system_info)
    echo "Checking repowatch dependencies for $sys_kind..."

    local missing_pkgs=()
    ! command -v git &>/dev/null && missing_pkgs+=("git")
    ! command -v fzf &>/dev/null && missing_pkgs+=("fzf")
    ! command -v lazygit &>/dev/null && missing_pkgs+=("lazygit")

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo "Missing tools: ${missing_pkgs[*]}"
        case "$sys_kind" in
            arch|cachyos|archarm|manjaro|steamos|holo)
                if command -v pacman &>/dev/null; then
                    sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"
                fi
                ;;
            debian|ubuntu|pop|kali)
                if command -v apt-get &>/dev/null; then
                    sudo apt-get update && sudo apt-get install -y "${missing_pkgs[@]}"
                fi
                ;;
            fedora|fedora-asahi-remix)
                if command -v dnf &>/dev/null; then
                    sudo dnf install -y "${missing_pkgs[@]}"
                fi
                ;;
            mac)
                if command -v brew &>/dev/null; then
                    brew install "${missing_pkgs[@]}"
                fi
                ;;
            *)
                echo "Please ensure git, fzf, and lazygit are installed."
                ;;
        esac
    fi
}

setup_symlinks() {
    echo "Setting up repowatch binary link..."
    mkdir -p "$HOME/.local/bin"
    ln -sfnv "$SCRIPT_DIR/repowatch.sh" "$HOME/.local/bin/repowatch"
}

main() {
    case "${1:-}" in
        -s|--symlinks)
            setup_symlinks
            ;;
        -p|--packages)
            install_packages
            ;;
        *)
            install_packages
            setup_symlinks
            ;;
    esac
    echo "repowatch setup completed successfully! 󰊢 "
}

main "$@"
