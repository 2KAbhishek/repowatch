#!/usr/bin/env bash

# repowatch: Interactive multi-repo monitor & lazygit launcher 🛰️✨
# Author: Abhishek (@2kabhishek)

set -e

VERSION="0.1.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

display_help() {
    cat <<EOF
repowatch: Interactive multi-repo monitor & lazygit launcher 🛰️✨

Usage: repowatch [directory] [options]

If the target directory is a Git repository, lazygit opens directly.
If not, repowatch scans child repositories and opens an interactive dashboard.

Arguments:
  directory           Directory to inspect (default: current directory)

Options:
  -d, --dirty         Show only repositories with uncommitted / unpushed changes
  -r, --recursive     Scan recursively for nested git repositories (max depth 3)
  -v, --version       Display version information
  -h, --help          Display this help message

Keybindings (in interactive mode):
  <Enter>             Open repository in lazygit
  <Ctrl-O>            Open repository in \$EDITOR (or nvim / vim)
  <Ctrl-R>            Refresh repository statuses
  <Ctrl-D>            Toggle dirty-only filter
  <Ctrl-G>            Open repository remote in browser
  <Esc> / <Ctrl-C>    Exit repowatch
EOF
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        echo -e "${RED}Error:${NC} Required command '$1' is not installed or not in PATH."
        exit 1
    fi
}

check_dependencies() {
    check_command git
    check_command fzf
    check_command lazygit
}

# Fast git status probe for a single repository
# Output format:
# [STATUS] [SYNC] [CHANGES] [REPO_NAME] [BRANCH] [LAST_COMMIT] \t [ABSOLUTE_PATH]
get_repo_summary() {
    local repo_dir="$1"
    local dirty_filter="${2:-false}"
    local repo_name
    repo_name="$(basename "$repo_dir")"

    if [ ! -d "$repo_dir/.git" ] && [ ! -f "$repo_dir/.git" ]; then
        return
    fi

    # Read porcelain v2 status and branch info in a single git execution
    local porcelain_out
    porcelain_out="$(git -C "$repo_dir" status --porcelain=v2 --branch 2>/dev/null || true)"

    if [ -z "$porcelain_out" ]; then
        if [ "$dirty_filter" = "true" ]; then
            return
        fi
        # Empty repo without commits
        local branch="(empty)"
        local status_badge="${GREEN}✓ CLEAN${NC}"
        local sync_badge=" -"
        local change_summary="-"
        local last_commit="No commits yet"
        printf "%b  %-5s  %-12s  ${BOLD}%-22s${NC}  %-16s  ${DIM}%-40s${NC}\t%s\n" \
            "$status_badge" "$sync_badge" "$change_summary" "$repo_name" "$branch" "$last_commit" "$repo_dir"
        return
    fi

    local branch="unknown"
    local ahead=0
    local behind=0
    local staged=0
    local unstaged=0
    local untracked=0
    local conflicted=0

    while IFS= read -r line; do
        case "$line" in
            \#\ branch.head\ *)
                branch="${line### branch.head }"
                ;;
            \#\ branch.ab\ *)
                local ab="${line### branch.ab }"
                ahead="${ab%% -*}"
                ahead="${ahead#+}"
                behind="${ab##* -}"
                ;;
            1\ ??\ *|2\ ??\ *)
                local xy="${line:2:2}"
                local x="${xy:0:1}"
                local y="${xy:1:1}"
                [[ "$x" != "." && "$x" != " " ]] && ((staged++)) || true
                [[ "$y" != "." && "$y" != " " ]] && ((unstaged++)) || true
                ;;
            u\ *)
                ((conflicted++)) || true
                ;;
            \?\ *)
                ((untracked++)) || true
                ;;
        esac
    done <<< "$porcelain_out"

    # Sync badge (ahead / behind)
    local sync_badge=""
    if (( ahead > 0 && behind > 0 )); then
        sync_badge="${PURPLE}↑${ahead} ↓${behind}${NC}"
    elif (( ahead > 0 )); then
        sync_badge="${CYAN}↑${ahead}${NC}"
    elif (( behind > 0 )); then
        sync_badge="${YELLOW}↓${behind}${NC}"
    else
        sync_badge="${DIM}-${NC}"
    fi

    # Changes breakdown
    local changes_list=()
    (( staged > 0 )) && changes_list+=("${GREEN}+${staged}${NC}")
    (( unstaged > 0 )) && changes_list+=("${YELLOW}~${unstaged}${NC}")
    (( untracked > 0 )) && changes_list+=("${BLUE}?${untracked}${NC}")
    (( conflicted > 0 )) && changes_list+=("${RED}!${conflicted}${NC}")

    local change_summary=""
    local is_dirty=0
    if [ ${#changes_list[@]} -gt 0 ]; then
        change_summary="$(IFS=' '; echo "${changes_list[*]}")"
        is_dirty=1
    else
        change_summary="${DIM}clean${NC}"
    fi

    # Check if dirty filter is active
    if [ "$dirty_filter" = "true" ] && (( is_dirty == 0 && ahead == 0 && behind == 0 )); then
        return
    fi

    # Status badge
    local status_badge=""
    if (( is_dirty == 1 || ahead > 0 || behind > 0 )); then
        status_badge="${RED}${BOLD}● DIRTY${NC}"
    else
        status_badge="${GREEN}✓ CLEAN${NC}"
    fi

    # Branch display
    local branch_disp="${CYAN}${branch}${NC}"
    if [[ "$branch" == "(detached)" || "$branch" == "HEAD" ]]; then
        branch_disp="${YELLOW}${branch}${NC}"
    fi

    # Last commit snippet (relative date + subject)
    local last_commit
    last_commit="$(git -C "$repo_dir" log -1 --format="%cr · %s" 2>/dev/null || echo "No commits")"
    if [ ${#last_commit} -gt 42 ]; then
        last_commit="${last_commit:0:39}..."
    fi

    # Aligned output
    printf "%b  %-10b  %-22b  ${BOLD}%-22s${NC}  %-24b  ${DIM}%-42s${NC}\t%s\n" \
        "$status_badge" "$sync_badge" "$change_summary" "$repo_name" "$branch_disp" "$last_commit" "$repo_dir"
}

# Scan directory for git repositories
scan_repos() {
    local target_dir="$1"
    local recursive="$2"
    local dirty_filter="${3:-false}"
    local repo_dirs=()

    if [ "$recursive" = "true" ]; then
        while IFS= read -r git_entry; do
            repo_dirs+=("$(dirname "$git_entry")")
        done < <(find "$target_dir" -maxdepth 3 \( -name ".git" \) -print 2>/dev/null | sort)
    else
        for dir in "$target_dir"/*/; do
            [ -d "$dir" ] || continue
            if [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; then
                repo_dirs+=("${dir%/}")
            fi
        done
    fi

    if [ ${#repo_dirs[@]} -eq 0 ]; then
        echo -e "${YELLOW}No Git repositories found in:${NC} $target_dir" >&2
        return 1
    fi

    # Concurrently gather status summaries using subshells
    export -f get_repo_summary
    export RED GREEN YELLOW BLUE PURPLE CYAN BOLD DIM NC

    printf "%s\n" "${repo_dirs[@]}" | xargs -P 16 -I {} bash -c 'get_repo_summary "$@" '"$dirty_filter" _ {} | sort -k1,1r -k4,4
}

# Preview command for fzf
preview_repo() {
    local repo_dir="$1"
    [ -z "$repo_dir" ] && exit 0

    local rule
    rule="$(printf '%.0s─' {1..50})"

    echo -e "${BOLD}${CYAN}📁 Repository:${NC} ${BOLD}$repo_dir${NC}"
    
    local remote_url
    remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "No remote")"
    echo -e "${DIM}🌐 Remote:${NC}     $remote_url"
    echo -e "${DIM}$rule${NC}"

    echo -e "${BOLD}${YELLOW}📋 Git Status:${NC}"
    git -C "$repo_dir" -c color.status=always status -sb 2>&1 || true
    echo

    echo -e "${DIM}$rule${NC}"
    echo -e "${BOLD}${PURPLE}📜 Recent Commits:${NC}"
    git -C "$repo_dir" -c color.ui=always log -n 5 --graph --pretty=format:'%C(yellow)%h%Creset %C(cyan)%cr%Creset %s %C(green)(%an)%Creset' 2>&1 || true
    echo

    local diff_stat
    diff_stat="$(git -C "$repo_dir" -c color.ui=always diff --stat 2>&1 || true)"
    local cached_stat
    cached_stat="$(git -C "$repo_dir" -c color.ui=always diff --cached --stat 2>&1 || true)"

    if [ -n "$diff_stat" ] || [ -n "$cached_stat" ]; then
        echo -e "${DIM}$rule${NC}"
        echo -e "${BOLD}${RED}📝 Changes Summary:${NC}"
        [ -n "$cached_stat" ] && echo -e "${GREEN}Staged:${NC}\n$cached_stat"
        [ -n "$diff_stat" ] && echo -e "${YELLOW}Unstaged:${NC}\n$diff_stat"
    fi
}

open_in_browser() {
    local repo_dir="$1"
    local remote_url
    remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
    if [ -z "$remote_url" ]; then
        return
    fi

    # Convert SSH / git url to https
    local web_url="$remote_url"
    web_url="${web_url#git@}"
    web_url="${web_url#https://}"
    web_url="${web_url#http://}"
    web_url="https://${web_url/:/\/}"
    web_url="${web_url%.git}"

    if command -v xdg-open &>/dev/null; then
        xdg-open "$web_url" &>/dev/null &
    elif command -v open &>/dev/null; then
        open "$web_url" &>/dev/null &
    fi
}

main() {
    check_dependencies

    local target_dir=""
    local dirty_only=false
    local recursive=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                display_help
                exit 0
                ;;
            -v|--version)
                echo "repowatch v$VERSION"
                exit 0
                ;;
            -d|--dirty)
                dirty_only=true
                shift
                ;;
            -r|--recursive)
                recursive=true
                shift
                ;;
            --preview-helper)
                preview_repo "$2"
                exit 0
                ;;
            --scan-helper)
                scan_repos "$2" "${3:-false}" "${4:-false}"
                exit 0
                ;;
            --browser-helper)
                open_in_browser "$2"
                exit 0
                ;;
            -*)
                echo -e "${RED}Unknown option:${NC} $1" >&2
                display_help
                exit 1
                ;;
            *)
                if [ -z "$target_dir" ]; then
                    target_dir="$1"
                fi
                shift
                ;;
        esac
    done

    # Default target directory is PWD
    target_dir="${target_dir:-$PWD}"
    target_dir="$(readlink -f "$target_dir")"

    if [ ! -d "$target_dir" ]; then
        echo -e "${RED}Error:${NC} Directory '$target_dir' does not exist." >&2
        exit 1
    fi

    # 1. Single Git Repo Mode: If target is already inside a git work tree, open lazygit directly
    if git -C "$target_dir" rev-parse --is-inside-work-tree &>/dev/null; then
        local git_root
        git_root="$(git -C "$target_dir" rev-parse --show-toplevel)"
        exec lazygit -p "$git_root"
    fi

    # 2. Multi-Repo Mode: Interactive Dashboard
    local initial_query=""
    [ "$dirty_only" = true ] && initial_query="DIRTY "

    local editor_cmd="${EDITOR:-nvim}"
    command -v "$editor_cmd" &>/dev/null || editor_cmd="vim"
    command -v "$editor_cmd" &>/dev/null || editor_cmd="nano"

    while true; do
        local repos_output
        repos_output="$(scan_repos "$target_dir" "$recursive")" || exit 1

        local header="STATUS      SYNC        CHANGES                 REPOSITORY              BRANCH                    LAST COMMIT"
        local help_bar="<Enter> lazygit | <C-o> ${editor_cmd} | <C-r> refresh | <C-d> toggle dirty | <C-g> browser | <Esc> quit"

        local selected
        selected="$(echo "$repos_output" | fzf \
            --ansi \
            --delimiter=$'\t' \
            --with-nth=1 \
            --header="$header"$'\n'"$help_bar" \
            --header-lines=0 \
            --prompt="🛰️ repowatch [$(basename "$target_dir")] > " \
            --query="$initial_query" \
            --preview="$SCRIPT_PATH --preview-helper {2}" \
            --preview-window="right:52%:wrap:border-left" \
            --bind="ctrl-r:reload($SCRIPT_PATH --scan-helper '$target_dir' $recursive)" \
            --bind="ctrl-d:transform-query(if [[ {q} == *DIRTY* ]]; then echo ''; else echo 'DIRTY '; fi)" \
            --bind="ctrl-g:execute-silent($SCRIPT_PATH --browser-helper {2})" \
            --bind="ctrl-o:execute($editor_cmd {2} < /dev/tty > /dev/tty 2>&1)+reload($SCRIPT_PATH --scan-helper '$target_dir' $recursive)" \
            --expect=enter,ctrl-c,esc || true)"

        local key
        key="$(echo "$selected" | head -n1)"
        local selection
        selection="$(echo "$selected" | sed 1d)"

        if [ -z "$selection" ] || [[ "$key" == "esc" || "$key" == "ctrl-c" ]]; then
            break
        fi

        local repo_path
        repo_path="$(echo "$selection" | awk -F'\t' '{print $2}')"

        if [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
            # Retain current search query for when we return from lazygit
            initial_query=""
            lazygit -p "$repo_path" || true
        else
            break
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
