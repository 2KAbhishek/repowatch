#!/usr/bin/env bash

# repowatch: Interactive multi-repo monitor & lazygit launcher 󰊢 
# Author: Abhishek (@2kabhishek)

set -e

VERSION="0.1.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

# Color definitions (ANSI-C quoted for true terminal escape evaluation)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
PURPLE=$'\033[0;35m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m' # No Color

SEP="${DIM}│${NC}"

display_help() {
    cat <<EOF
repowatch: Interactive multi-repo monitor & lazygit launcher 󰊢 

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
  <Enter>             View repository in lazygit
  <Ctrl-O>            Edit repository in \$EDITOR
  <Ctrl-R>            Sync / refresh repository statuses
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

format_relative_date() {
    local d="$1"
    d="${d% ago}"
    case "$d" in
        *second*)
            echo "${d%% second*}s" ;;
        *minute*)
            echo "${d%% minute*}m" ;;
        *hour*)
            echo "${d%% hour*}h" ;;
        *day*)
            echo "${d%% day*}d" ;;
        *week*)
            echo "${d%% week*}w" ;;
        *month*)
            if [[ "$d" =~ ([0-9]+)\ year.*,\ ([0-9]+)\ month ]]; then
                echo "${BASH_REMATCH[1]}y ${BASH_REMATCH[2]}mo"
            else
                echo "${d%% month*}mo"
            fi
            ;;
        *year*)
            echo "${d%% year*}y" ;;
        *)
            echo "$d" ;;
    esac
}

# Fast git status probe for a single repository
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
        local status_col="${GREEN}${NC} ${DIM}-       ${NC}"
        local repo_pad="$(printf "%-22.22s" "$repo_name")"
        local repo_col="${BOLD}${repo_pad}${NC}"
        local branch_pad="$(printf "%-10.10s" "(empty)")"
        local branch_col="${DIM}${branch_pad}${NC}"
        local date_pad="$(printf "%-7.7s" "never")"
        local date_col="${DIM}${date_pad}${NC}"
        local commit_pad="$(printf "%-48.48s" "No commits yet")"
        local commit_col="${DIM}${commit_pad}${NC}"

        echo -e "1\t0\t${repo_col} ${SEP} ${status_col} ${SEP} ${branch_pad} ${SEP} ${date_col} ${SEP} ${commit_col}\t${repo_dir}"
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

    local is_dirty=0
    (( staged > 0 || unstaged > 0 || untracked > 0 || conflicted > 0 )) && is_dirty=1

    # Filter out clean repos if dirty_filter is set
    if [ "$dirty_filter" = "true" ] && (( is_dirty == 0 && ahead == 0 && behind == 0 )); then
        return
    fi

    # 1. Status column (Status Icon + Sync + Local changes) - 10 chars visual
    local sort_key=1
    local badge=""
    if (( is_dirty == 1 || ahead > 0 || behind > 0 )); then
        sort_key=0
        badge="${RED}${BOLD}${NC} "
    else
        badge="${GREEN}${NC} "
    fi

    local c_parts=""
    local c_plain=""

    if (( ahead > 0 && behind > 0 )); then
        c_parts="${PURPLE}${ahead}${behind}${NC}"
        c_plain="${ahead}${behind}"
    elif (( ahead > 0 )); then
        c_parts="${CYAN}${ahead}${NC}"
        c_plain="${ahead}"
    elif (( behind > 0 )); then
        c_parts="${YELLOW}${behind}${NC}"
        c_plain="${behind}"
    fi

    if (( staged > 0 )); then
        [ -n "$c_parts" ] && c_parts="${c_parts} " && c_plain="${c_plain} "
        c_parts="${c_parts}${GREEN}+${staged}${NC}"
        c_plain="${c_plain}+${staged}"
    fi
    if (( unstaged > 0 )); then
        [ -n "$c_parts" ] && c_parts="${c_parts} " && c_plain="${c_plain} "
        c_parts="${c_parts}${YELLOW}~${unstaged}${NC}"
        c_plain="${c_plain}~${unstaged}"
    fi
    if (( untracked > 0 )); then
        [ -n "$c_parts" ] && c_parts="${c_parts} " && c_plain="${c_plain} "
        c_parts="${c_parts}${BLUE}?${untracked}${NC}"
        c_plain="${c_plain}?${untracked}"
    fi
    if (( conflicted > 0 )); then
        [ -n "$c_parts" ] && c_parts="${c_parts} " && c_plain="${c_plain} "
        c_parts="${c_parts}${RED}!${conflicted}${NC}"
        c_plain="${c_plain}!${conflicted}"
    fi

    if [ -z "$c_plain" ]; then
        c_parts="${DIM}-${NC}"
        c_plain="-"
    fi

    local full_plain="X ${c_plain}"
    local chg_pad=$(( 10 - ${#full_plain} ))
    (( chg_pad < 0 )) && chg_pad=0
    local chg_spaces=""
    [ $chg_pad -gt 0 ] && chg_spaces="$(printf "%*s" "$chg_pad" "")"
    local status_col="${badge}${c_parts}${chg_spaces}"

    # 2. Repo name column (22 chars visual)
    local repo_pad="$(printf "%-22.22s" "$repo_name")"
    local repo_col="${BOLD}${repo_pad}${NC}"

    # 3. Branch column (10 chars visual)
    local branch_pad="$(printf "%-10.10s" "$branch")"
    local branch_col="${CYAN}${branch_pad}${NC}"
    [[ "$branch" == "(detached)" || "$branch" == "HEAD" ]] && branch_col="${YELLOW}${branch_pad}${NC}"

    # 4. Date & Commit message separated (7 chars date, 48 chars commit)
    local log_raw
    log_raw="$(git -C "$repo_dir" log -1 --format="%ct%x09%cr%x09%s" 2>/dev/null || echo "0	never	No commits")"
    local commit_time="${log_raw%%	*}"
    local log_rest="${log_raw#*	}"
    local date_raw="${log_rest%%	*}"
    local commit_subj="${log_rest#*	}"
    local date_clean="$(format_relative_date "$date_raw")"

    local date_pad="$(printf "%-7.7s" "$date_clean")"
    local date_col="${DIM}${date_pad}${NC}"

    local commit_pad="$(printf "%-48.48s" "$commit_subj")"
    local commit_col="${commit_pad}"

    # Aligned output with vertical column separators
    echo -e "${sort_key}\t${commit_time}\t${repo_col} ${SEP} ${status_col} ${SEP} ${branch_col} ${SEP} ${date_col} ${SEP} ${commit_col}\t${repo_dir}"
}

# Scan directory for git repositories with pinned headers for fzf
scan_repos() {
    local target_dir="$1"
    local recursive="$2"
    local dirty_filter="${3:-false}"
    local repo_dirs=()

    local keybindings="${DIM}󰌑 󰈈 · ^o 󰏫 · ^r 󰑓 · ^d  · ^g 󰖟${NC}"
    local header="${BOLD}Repository            ${NC} ${SEP} ${BOLD}Status    ${NC} ${SEP} ${BOLD}Branch    ${NC} ${SEP} ${BOLD}Updated${NC} ${SEP} ${BOLD}Last Commit${NC}"
    local divider="${DIM}───────────────────────┼────────────┼────────────┼─────────┼────────────────────────────────────────────────${NC}"

    # Output pinned header lines for fzf --header-lines=3
    echo -e "${keybindings}\t"
    echo -e "${header}\t"
    echo -e "${divider}\t"

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
        echo -e "${YELLOW}No Git repositories found in:${NC} $target_dir\t" >&2
        return 0
    fi

    export -f get_repo_summary format_relative_date
    export RED GREEN YELLOW BLUE PURPLE CYAN BOLD DIM NC SEP

    printf "%s\n" "${repo_dirs[@]}" | xargs -P 16 -I {} bash -c 'get_repo_summary "$@" '"$dirty_filter" _ {} | sort -k1,1n -k2,2nr | cut -f3-
}

# Preview command for fzf
preview_repo() {
    local repo_dir="$1"
    [ -z "$repo_dir" ] && exit 0

    local width="${FZF_PREVIEW_COLUMNS:-80}"
    local rule
    rule="$(printf '%.0s─' $(seq 1 "$width"))"

    echo -e "${BOLD}${CYAN} Repository:${NC} ${BOLD}$repo_dir${NC}"
    
    local remote_url
    remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "No remote")"
    echo -e "${DIM}󰖟 Remote:${NC}     $remote_url"
    echo -e "${DIM}$rule${NC}"

    echo -e "${BOLD}${YELLOW}󰊢 Git Status:${NC}"
    git -C "$repo_dir" -c color.status=always status -sb 2>&1 || true
    echo

    local unpushed_count
    unpushed_count="$(git -C "$repo_dir" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
    if (( unpushed_count > 0 )); then
        echo -e "${DIM}$rule${NC}"
        echo -e "${BOLD}${CYAN} Unpushed Commits (${unpushed_count}):${NC}"
        git -C "$repo_dir" -c color.ui=always log -n 5 --graph --pretty=format:'%C(yellow)%h%Creset %C(cyan)%cr%Creset %s' @{u}..HEAD 2>&1 || true
        echo
        if (( unpushed_count > 5 )); then
            echo -e "${DIM}... and $((unpushed_count - 5)) more unpushed commits${NC}\n"
        fi
    fi

    echo -e "${DIM}$rule${NC}"
    echo -e "${BOLD}${PURPLE}󰜘 Recent Commits:${NC}"
    git -C "$repo_dir" -c color.ui=always log -n 5 --graph --pretty=format:'%C(yellow)%h%Creset %C(cyan)%cr%Creset %s %C(green)(%an)%Creset' 2>&1 || true
    echo

    local stat_width=$(( width > 10 ? width - 4 : 50 ))
    local diff_stat
    diff_stat="$(git -C "$repo_dir" -c color.ui=always diff --stat="$stat_width" 2>&1 || true)"
    local cached_stat
    cached_stat="$(git -C "$repo_dir" -c color.ui=always diff --cached --stat="$stat_width" 2>&1 || true)"

    if [ -n "$diff_stat" ] || [ -n "$cached_stat" ]; then
        echo -e "${DIM}$rule${NC}"
        echo -e "${BOLD}${RED} Changes Summary:${NC}"
        [ -n "$cached_stat" ] && echo -e "${GREEN} Staged:${NC}\n$cached_stat"
        [ -n "$diff_stat" ] && echo -e "${YELLOW} Unstaged:${NC}\n$diff_stat"
    fi
}

open_in_browser() {
    local repo_dir="$1"
    local remote_url
    remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
    if [ -z "$remote_url" ]; then
        return
    fi

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
    [ "$dirty_only" = true ] && initial_query=" "

    local editor_cmd="${EDITOR:-nvim}"
    command -v "$editor_cmd" &>/dev/null || editor_cmd="vim"
    command -v "$editor_cmd" &>/dev/null || editor_cmd="nano"

    while true; do
        local selected
        selected="$("$SCRIPT_PATH" --scan-helper "$target_dir" "$recursive" | fzf \
            --ansi \
            --no-multi \
            --pointer=" " \
            --delimiter=$'\t' \
            --with-nth=1 \
            --header-lines=3 \
            --prompt="󰊢 repowatch [$(basename "$target_dir")] ❯ " \
            --query="$initial_query" \
            --preview="$SCRIPT_PATH --preview-helper {2}" \
            --preview-window="right:50%:wrap:border-left" \
            --bind="ctrl-r:reload($SCRIPT_PATH --scan-helper '$target_dir' $recursive)" \
            --bind="ctrl-d:transform-query(if [[ {q} == ** ]]; then echo ''; else echo ' '; fi)" \
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
