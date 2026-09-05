#!/usr/bin/env bash

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

DEFAULT_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/repowatch/config"

# Configuration Defaults (overridden via ~/.config/repowatch/config or ~/.repowatchrc)
CONFIG_REPO_WIDTH=22
CONFIG_STATUS_WIDTH=10
CONFIG_BRANCH_WIDTH=10
CONFIG_DATE_WIDTH=7
CONFIG_COMMIT_WIDTH=48
CONFIG_MAX_DEPTH=3
CONFIG_PARALLEL_JOBS=16
CONFIG_DIRTY_ONLY=false
CONFIG_RECURSIVE=false
CONFIG_VIEW_TOOL="lazygit"
CONFIG_EDIT_TOOL="${EDITOR:-nvim}"
CONFIG_PREVIEW_PERCENT=50

CONFIG_ICON_CLEAN=""
CONFIG_ICON_DIRTY=""
CONFIG_ICON_AHEAD=""
CONFIG_ICON_BEHIND=""
CONFIG_ICON_VIEW=""
CONFIG_ICON_EDIT=""
CONFIG_ICON_WEB="󰖟"
CONFIG_ICON_SHELL=""
CONFIG_ICON_REFRESH="󰑓"
CONFIG_ICON_SYNC=""
CONFIG_ICON_UPSTREAM="󰜮"

load_config() {
    local config_file="${REPOWATCH_CONFIG:-$DEFAULT_CONFIG_PATH}"
    [ ! -f "$config_file" ] && config_file="$HOME/.repowatchrc"
    [ ! -f "$config_file" ] && return 0

    while IFS='=' read -r key val || [ -n "$key" ]; do
        key="$(echo "$key" | tr -d '[:space:]')"
        [[ -z "$key" || "$key" == \#* ]] && continue
        val="${val%%#*}"
        val="$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\''\(]//' -e 's/["'\''\)]$//')"

        case "$key" in
        repo_width)      CONFIG_REPO_WIDTH="$val" ;;
        status_width)    CONFIG_STATUS_WIDTH="$val" ;;
        branch_width)    CONFIG_BRANCH_WIDTH="$val" ;;
        date_width)      CONFIG_DATE_WIDTH="$val" ;;
        commit_width)    CONFIG_COMMIT_WIDTH="$val" ;;
        max_depth)       CONFIG_MAX_DEPTH="$val" ;;
        parallel_jobs)   CONFIG_PARALLEL_JOBS="$val" ;;
        dirty_only)      CONFIG_DIRTY_ONLY="$val" ;;
        recursive)       CONFIG_RECURSIVE="$val" ;;
        view_tool)       CONFIG_VIEW_TOOL="$val" ;;
        edit_tool)       CONFIG_EDIT_TOOL="$val" ;;
        editor)          CONFIG_EDIT_TOOL="$val" ;;
        preview_percent) CONFIG_PREVIEW_PERCENT="$val" ;;
        icon_clean)      CONFIG_ICON_CLEAN="$val" ;;
        icon_dirty)      CONFIG_ICON_DIRTY="$val" ;;
        icon_ahead)      CONFIG_ICON_AHEAD="$val" ;;
        icon_behind)     CONFIG_ICON_BEHIND="$val" ;;
        icon_view)       CONFIG_ICON_VIEW="$val" ;;
        icon_edit)       CONFIG_ICON_EDIT="$val" ;;
        icon_web)        CONFIG_ICON_WEB="$val" ;;
        icon_shell)      CONFIG_ICON_SHELL="$val" ;;
        icon_refresh)    CONFIG_ICON_REFRESH="$val" ;;
        icon_sync)       CONFIG_ICON_SYNC="$val" ;;
        icon_upstream)   CONFIG_ICON_UPSTREAM="$val" ;;
        esac
    done < "$config_file"
}

init_config() {
    local target_config="$DEFAULT_CONFIG_PATH"
    if [ -f "$target_config" ]; then
        echo -e "${YELLOW}Config file already exists:${NC} $target_config"
        return 0
    fi

    local script_dir
    script_dir="$(dirname "$SCRIPT_PATH")"
    local example_conf="$script_dir/repowatch.conf.example"

    if [ ! -f "$example_conf" ]; then
        example_conf="/usr/share/repowatch/repowatch.conf.example"
    fi

    if [ ! -f "$example_conf" ]; then
        echo -e "${RED}Error:${NC} Example config file 'repowatch.conf.example' not found." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$target_config")"
    cp "$example_conf" "$target_config"
    echo -e "${GREEN}Created default config at:${NC} $target_config"
}

display_help() {
    cat <<EOF
repowatch: Interactive multi-repo monitor 󰊢 

Usage: repowatch [directory] [options]

If the target directory is a Git repository, it opens directly in view_tool (default: lazygit).
If not, repowatch scans child repositories and opens an interactive dashboard.

Arguments:
  directory           Directory to inspect (default: current directory)

Options:
  -d, --dirty         Show only repositories with uncommitted / unpushed changes
  -r, --recursive     Scan recursively for nested git repositories (max depth 3)
  -o, --overview      Force overview mode even if inside a Git repository
  --init-config       Generate default configuration file in ~/.config/repowatch/config
  -v, --version       Display version information
  -h, --help          Display this help message

Keybindings (in interactive mode):
  <Enter>             View repository in view_tool (default: lazygit)
  <Ctrl-D>            Toggle dirty-only filter
  <Ctrl-E>            Edit repository in edit_tool / \$EDITOR
  <Ctrl-G>            Open repository remote in browser
  <Ctrl-O>            Open terminal / subshell in repository
  <Ctrl-R>            Refresh repository statuses (local scan)
  <Ctrl-S>            Sync (pull & push) all repositories
  <Ctrl-U>            Fetch upstream for all repositories
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
    local vtool="${CONFIG_VIEW_TOOL%% *}"
    if [ -n "$vtool" ] && ! command -v "$vtool" &>/dev/null; then
        echo -e "${YELLOW}Warning:${NC} Configured view_tool '$vtool' not found in PATH." >&2
    fi
}

is_git_repo() {
    [ -d "$1/.git" ] || [ -f "$1/.git" ]
}

open_view_tool() {
    local repo_dir="$1"
    local tool="${CONFIG_VIEW_TOOL:-lazygit}"
    (
        cd "$repo_dir" || exit 1
        case "$tool" in
        lazygit) lazygit -p "$repo_dir" 2>/dev/null || lazygit ;;
        gitui)   gitui -d "$repo_dir" 2>/dev/null || gitui ;;
        tig)     tig ;;
        *)       eval "$tool" ;;
        esac
    ) || true
}

format_relative_date() {
    local d="$1"
    d="${d% ago}"
    case "$d" in
    *second*)
        printf -v "$2" "%ss" "${d%% second*}"
        ;;
    *minute*)
        printf -v "$2" "%sm" "${d%% minute*}"
        ;;
    *hour*)
        printf -v "$2" "%sh" "${d%% hour*}"
        ;;
    *day*)
        printf -v "$2" "%sd" "${d%% day*}"
        ;;
    *week*)
        printf -v "$2" "%sw" "${d%% week*}"
        ;;
    *month*)
        if [[ "$d" =~ ([0-9]+)\ year.*,\ ([0-9]+)\ month ]]; then
            printf -v "$2" "%sy %smo" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        else
            printf -v "$2" "%smo" "${d%% month*}"
        fi
        ;;
    *year*)
        printf -v "$2" "%sy" "${d%% year*}"
        ;;
    *)
        printf -v "$2" "%s" "$d"
        ;;
    esac
}

# Fast git status probe for a single repository
get_repo_summary() {
    local repo_dir="$1"
    local dirty_filter="${2:-false}"
    local repo_name="${repo_dir##*/}"

    is_git_repo "$repo_dir" || return

    # Read porcelain v2 status and branch info in a single git execution
    local porcelain_out
    porcelain_out="$(git -c gc.auto=0 --no-optional-locks -C "$repo_dir" status --porcelain=v2 --branch 2>/dev/null || true)"

    if [ -z "$porcelain_out" ]; then
        if [ "$dirty_filter" = "true" ]; then
            return
        fi
        local empty_pad=$((CONFIG_STATUS_WIDTH - 3))
        ((empty_pad < 0)) && empty_pad=0
        local empty_spaces=""
        [ $empty_pad -gt 0 ] && printf -v empty_spaces "%*s" "$empty_pad" ""
        local status_col="${GREEN}${CONFIG_ICON_CLEAN}${NC} ${DIM}-${empty_spaces}${NC}"

        local repo_pad branch_pad date_pad commit_pad
        printf -v repo_pad "%-${CONFIG_REPO_WIDTH}.${CONFIG_REPO_WIDTH}s" "$repo_name"
        local repo_col="${BOLD}${repo_pad}${NC}"
        printf -v branch_pad "%-${CONFIG_BRANCH_WIDTH}.${CONFIG_BRANCH_WIDTH}s" "(empty)"
        local branch_col="${DIM}${branch_pad}${NC}"
        printf -v date_pad "%-${CONFIG_DATE_WIDTH}.${CONFIG_DATE_WIDTH}s" "never"
        local date_col="${DIM}${date_pad}${NC}"
        printf -v commit_pad "%-${CONFIG_COMMIT_WIDTH}.${CONFIG_COMMIT_WIDTH}s" "No commits yet"
        local commit_col="${DIM}${commit_pad}${NC}"

        echo -e "1\t0\t${repo_col} ${SEP} ${status_col} ${SEP} ${branch_col} ${SEP} ${date_col} ${SEP} ${commit_col}\t${repo_dir}"
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
        1\ ??\ * | 2\ ??\ *)
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
    done <<<"$porcelain_out"

    local is_dirty=0
    ((staged > 0 || unstaged > 0 || untracked > 0 || conflicted > 0)) && is_dirty=1

    # Filter out clean repos if dirty_filter is set
    if [ "$dirty_filter" = "true" ] && ((is_dirty == 0 && ahead == 0 && behind == 0)); then
        return
    fi

    # 1. Status column (Status Icon + Sync + Local changes)
    local sort_key=1
    local badge=""
    if ((is_dirty == 1 || ahead > 0 || behind > 0)); then
        sort_key=0
        badge="${RED}${BOLD}${CONFIG_ICON_DIRTY}${NC} "
    else
        badge="${GREEN}${CONFIG_ICON_CLEAN}${NC} "
    fi

    local c_parts=""
    local c_plain=""

    if ((ahead > 0 && behind > 0)); then
        c_parts="${PURPLE}${CONFIG_ICON_AHEAD}${ahead}${CONFIG_ICON_BEHIND}${behind}${NC}"
        c_plain="${CONFIG_ICON_AHEAD}${ahead}${CONFIG_ICON_BEHIND}${behind}"
    elif ((ahead > 0)); then
        c_parts="${CYAN}${CONFIG_ICON_AHEAD}${ahead}${NC}"
        c_plain="${CONFIG_ICON_AHEAD}${ahead}"
    elif ((behind > 0)); then
        c_parts="${YELLOW}${CONFIG_ICON_BEHIND}${behind}${NC}"
        c_plain="${CONFIG_ICON_BEHIND}${behind}"
    fi

    if ((staged > 0)); then
        [ -n "$c_parts" ] && c_parts="${c_parts} " && c_plain="${c_plain} "
        c_parts="${c_parts}${GREEN}+${staged}${NC}"
        c_plain="${c_plain}+${staged}"
    fi
    if ((unstaged > 0)); then
        [ -n "$c_parts" ] && c_parts="${c_parts} " && c_plain="${c_plain} "
        c_parts="${c_parts}${YELLOW}~${unstaged}${NC}"
        c_plain="${c_plain}~${unstaged}"
    fi
    if ((untracked > 0)); then
        [ -n "$c_parts" ] && c_parts="${c_parts} " && c_plain="${c_plain} "
        c_parts="${c_parts}${BLUE}?${untracked}${NC}"
        c_plain="${c_plain}?${untracked}"
    fi
    if ((conflicted > 0)); then
        [ -n "$c_parts" ] && c_parts="${c_parts} " && c_plain="${c_plain} "
        c_parts="${c_parts}${RED}!${conflicted}${NC}"
        c_plain="${c_plain}!${conflicted}"
    fi

    if [ -z "$c_plain" ]; then
        c_parts="${DIM}-${NC}"
        c_plain="-"
    fi

    local full_plain="X ${c_plain}"
    local chg_pad=$((CONFIG_STATUS_WIDTH - ${#full_plain}))
    ((chg_pad < 0)) && chg_pad=0
    local chg_spaces=""
    [ $chg_pad -gt 0 ] && printf -v chg_spaces "%*s" "$chg_pad" ""
    local status_col="${badge}${c_parts}${chg_spaces}"

    # 2. Repo name column
    local repo_pad
    printf -v repo_pad "%-${CONFIG_REPO_WIDTH}.${CONFIG_REPO_WIDTH}s" "$repo_name"
    local repo_col="${BOLD}${repo_pad}${NC}"

    # 3. Branch column
    local branch_pad
    printf -v branch_pad "%-${CONFIG_BRANCH_WIDTH}.${CONFIG_BRANCH_WIDTH}s" "$branch"
    local branch_col="${CYAN}${branch_pad}${NC}"
    [[ "$branch" == "(detached)" || "$branch" == "HEAD" ]] && branch_col="${YELLOW}${branch_pad}${NC}"

    # 4. Date & Commit message separated
    local log_raw
    log_raw="$(git -c gc.auto=0 --no-optional-locks -C "$repo_dir" log -1 --no-patch --format="%ct%x09%cr%x09%s" 2>/dev/null || echo "0	never	No commits")"
    local commit_time="${log_raw%%	*}"
    local log_rest="${log_raw#*	}"
    local date_raw="${log_rest%%	*}"
    local commit_subj="${log_rest#*	}"
    local date_clean
    format_relative_date "$date_raw" date_clean

    local date_pad commit_pad
    printf -v date_pad "%-${CONFIG_DATE_WIDTH}.${CONFIG_DATE_WIDTH}s" "$date_clean"
    local date_col="${DIM}${date_pad}${NC}"

    printf -v commit_pad "%-${CONFIG_COMMIT_WIDTH}.${CONFIG_COMMIT_WIDTH}s" "$commit_subj"
    local commit_col="${commit_pad}"

    # Aligned output with vertical column separators
    echo -e "${sort_key}\t${commit_time}\t${repo_col} ${SEP} ${status_col} ${SEP} ${branch_col} ${SEP} ${date_col} ${SEP} ${commit_col}\t${repo_dir}"
}

# Find all git repository directories under target_dir
find_repo_dirs() {
    local target_dir="$1"
    local recursive="$2"
    local -n _out_dirs="$3"
    _out_dirs=()

    if [ "$recursive" = "true" ]; then
        while IFS= read -r git_entry; do
            _out_dirs+=("$(dirname "$git_entry")")
        done < <(find "$target_dir" -maxdepth "$CONFIG_MAX_DEPTH" -name ".git" -prune -print 2>/dev/null | sort)
    else
        is_git_repo "$target_dir" && _out_dirs+=("${target_dir%/}")
        for dir in "$target_dir"/*/; do
            [ -d "$dir" ] || continue
            is_git_repo "$dir" && _out_dirs+=("${dir%/}")
        done
    fi
}

# Scan directory for git repositories with pinned headers for fzf
scan_repos() {
    local target_dir="$1"
    local recursive="$2"
    local dirty_filter="${3:-false}"
    local repo_dirs=()

    local keybindings="${DIM}󰌑 ${CONFIG_ICON_VIEW} · ^d ${CONFIG_ICON_DIRTY} · ^e ${CONFIG_ICON_EDIT} · ^g ${CONFIG_ICON_WEB} · ^o ${CONFIG_ICON_SHELL} · ^r ${CONFIG_ICON_REFRESH} · ^s ${CONFIG_ICON_SYNC} · ^u ${CONFIG_ICON_UPSTREAM} ${NC}"

    local h_repo h_status h_branch h_date h_commit
    printf -v h_repo "%-*s" "$CONFIG_REPO_WIDTH" "Repository"
    printf -v h_status "%-*s" "$CONFIG_STATUS_WIDTH" "Status"
    printf -v h_branch "%-*s" "$CONFIG_BRANCH_WIDTH" "Branch"
    printf -v h_date "%-*s" "$CONFIG_DATE_WIDTH" "Updated"
    printf -v h_commit "%-*s" "$CONFIG_COMMIT_WIDTH" "Last Commit"
    local header="${BOLD}${h_repo}${NC} ${SEP} ${BOLD}${h_status}${NC} ${SEP} ${BOLD}${h_branch}${NC} ${SEP} ${BOLD}${h_date}${NC} ${SEP} ${BOLD}${h_commit}${NC}"

    local d_repo d_status d_branch d_date d_commit
    printf -v d_repo "%*s" $((CONFIG_REPO_WIDTH + 1)) ""
    printf -v d_status "%*s" $((CONFIG_STATUS_WIDTH + 2)) ""
    printf -v d_branch "%*s" $((CONFIG_BRANCH_WIDTH + 2)) ""
    printf -v d_date "%*s" $((CONFIG_DATE_WIDTH + 2)) ""
    printf -v d_commit "%*s" "$CONFIG_COMMIT_WIDTH" ""
    local CROSS="${DIM}┼${NC}"
    local divider="${DIM}${d_repo// /─}${NC}${CROSS}${DIM}${d_status// /─}${NC}${CROSS}${DIM}${d_branch// /─}${NC}${CROSS}${DIM}${d_date// /─}${NC}${CROSS}${DIM}${d_commit// /─}${NC}"

    # Output pinned header lines for fzf --header-lines=3
    echo -e "${keybindings}\t"
    echo -e "${header}\t"
    echo -e "${divider}\t"

    find_repo_dirs "$target_dir" "$recursive" repo_dirs

    if [ ${#repo_dirs[@]} -eq 0 ]; then
        echo -e "${YELLOW}No Git repositories found in:${NC} $target_dir\t" >&2
        return 0
    fi

    export -f get_repo_summary format_relative_date is_git_repo
    export RED GREEN YELLOW BLUE PURPLE CYAN BOLD DIM NC SEP
    export CONFIG_REPO_WIDTH CONFIG_STATUS_WIDTH CONFIG_BRANCH_WIDTH CONFIG_DATE_WIDTH CONFIG_COMMIT_WIDTH
    export CONFIG_ICON_CLEAN CONFIG_ICON_DIRTY CONFIG_ICON_AHEAD CONFIG_ICON_BEHIND

    printf "%s\0" "${repo_dirs[@]}" | xargs -0 -P "$CONFIG_PARALLEL_JOBS" -I {} bash -c 'get_repo_summary "$@" '"$dirty_filter" _ {} | sort -k1,1n -k2,2nr | cut -f3-
}

# Fetch upstream tracking branches across all repositories, then scan
fetch_repos() {
    local target_dir="$1"
    local recursive="$2"
    local dirty_filter="${3:-false}"
    local repo_dirs=()

    find_repo_dirs "$target_dir" "$recursive" repo_dirs

    if [ ${#repo_dirs[@]} -gt 0 ]; then
        printf "%s\0" "${repo_dirs[@]}" | xargs -0 -P "$CONFIG_PARALLEL_JOBS" -I {} git -C "{}" fetch --prune -q 2>/dev/null || true
    fi

    scan_repos "$target_dir" "$recursive" "$dirty_filter"
}

# Helper to sync (pull & push) a single repository
sync_single_repo() {
    local repo_dir="$1"
    is_git_repo "$repo_dir" || return

    # 1. Fetch latest upstream
    git -c gc.auto=0 --no-optional-locks -C "$repo_dir" fetch --prune -q 2>/dev/null || true

    # 2. Check tracking branch and status
    if git -c gc.auto=0 --no-optional-locks -C "$repo_dir" rev-parse --abbrev-ref @{u} &>/dev/null; then
        local status_out
        status_out="$(git -c gc.auto=0 --no-optional-locks -C "$repo_dir" status --porcelain=v2 --branch 2>/dev/null || true)"

        local ahead=0
        local behind=0
        local is_dirty=0

        while IFS= read -r line; do
            case "$line" in
            \#\ branch.ab\ *)
                local ab="${line### branch.ab }"
                ahead="${ab%% -*}"
                ahead="${ahead#+}"
                behind="${ab##* -}"
                ;;
            1\ * | 2\ * | u\ * | \?\ *)
                is_dirty=1
                ;;
            esac
        done <<< "$status_out"

        # Safe Pull: Only fast-forward if behind and worktree is not dirty
        if (( behind > 0 && is_dirty == 0 )); then
            git -c gc.auto=0 --no-optional-locks -C "$repo_dir" pull --ff-only -q 2>/dev/null || true
        fi

        # Push: If ahead of remote
        if (( ahead > 0 )); then
            git -c gc.auto=0 --no-optional-locks -C "$repo_dir" push -q 2>/dev/null || true
        fi
    fi
}

# Full batch sync: Pull upstream changes and push local commits across all repositories
sync_repos() {
    local target_dir="$1"
    local recursive="$2"
    local dirty_filter="${3:-false}"
    local repo_dirs=()

    find_repo_dirs "$target_dir" "$recursive" repo_dirs

    if [ ${#repo_dirs[@]} -gt 0 ]; then
        export -f sync_single_repo is_git_repo
        printf "%s\0" "${repo_dirs[@]}" | xargs -0 -P "$CONFIG_PARALLEL_JOBS" -I {} bash -c 'sync_single_repo "$@"' _ {} 2>/dev/null || true
    fi

    scan_repos "$target_dir" "$recursive" "$dirty_filter"
}

# Preview command for fzf
preview_repo() {
    local repo_dir="$1"
    [ -z "$repo_dir" ] && exit 0

    local width="${FZF_PREVIEW_COLUMNS:-80}"
    local rule
    printf -v rule '%*s' "$width" ''
    rule="${rule// /─}"

    echo -e "${BOLD}${CYAN} Repository:${NC} ${BOLD}$repo_dir${NC}"

    local remote_url
    remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "No remote")"
    echo -e "${DIM}󰖟 Remote:${NC}     $remote_url"
    echo -e "${DIM}$rule${NC}"

    echo -e "${BOLD}${YELLOW}󰊢 Git Status:${NC}"
    git -c color.status=always --no-optional-locks -C "$repo_dir" status -sb 2>&1 || true
    echo

    local unpushed_count
    unpushed_count="$(git -c gc.auto=0 --no-optional-locks -C "$repo_dir" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
    if ((unpushed_count > 0)); then
        echo -e "${DIM}$rule${NC}"
        echo -e "${BOLD}${CYAN} Unpushed Commits (${unpushed_count}):${NC}"
        git -c color.ui=always --no-optional-locks -C "$repo_dir" log -n 5 --graph --pretty=format:'%C(yellow)%h%Creset %C(cyan)%cr%Creset %s' @{u}..HEAD 2>&1 || true
        echo
        if ((unpushed_count > 5)); then
            echo -e "${DIM}... and $((unpushed_count - 5)) more unpushed commits${NC}\n"
        fi
    fi

    echo -e "${DIM}$rule${NC}"
    echo -e "${BOLD}${PURPLE}󰜘 Recent Commits:${NC}"
    git -c color.ui=always --no-optional-locks -C "$repo_dir" log -n 5 --graph --pretty=format:'%C(yellow)%h%Creset %C(cyan)%cr%Creset %s %C(green)(%an)%Creset' 2>&1 || true
    echo

    local stat_width=$((width > 10 ? width - 4 : 50))
    local diff_stat
    diff_stat="$(git -c color.ui=always --no-optional-locks -C "$repo_dir" diff --no-ext-diff --stat="$stat_width" 2>&1 || true)"
    local cached_stat
    cached_stat="$(git -c color.ui=always --no-optional-locks -C "$repo_dir" diff --no-ext-diff --cached --stat="$stat_width" 2>&1 || true)"

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
    if [[ "$remote_url" =~ ^git@([^:]+):(.*)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local path="${BASH_REMATCH[2]}"
        path="${path%.git}"
        web_url="https://${host}/${path}"
    elif [[ "$remote_url" =~ ^https?:// ]]; then
        web_url="${remote_url%.git}"
    fi

    if command -v xdg-open &>/dev/null; then
        xdg-open "$web_url" &>/dev/null &
    elif command -v open &>/dev/null; then
        open "$web_url" &>/dev/null &
    fi
}

main() {
    load_config
    check_dependencies

    local target_dir=""
    local dirty_only="${CONFIG_DIRTY_ONLY:-false}"
    local recursive="${CONFIG_RECURSIVE:-false}"
    local overview=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            display_help
            exit 0
            ;;
        -v | --version)
            echo "repowatch v$VERSION"
            exit 0
            ;;
        --init-config)
            init_config
            exit 0
            ;;
        -d | --dirty)
            dirty_only=true
            shift
            ;;
        -r | --recursive)
            recursive=true
            shift
            ;;
        -o | --overview)
            overview=true
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
        --fetch-helper)
            fetch_repos "$2" "${3:-false}" "${4:-false}"
            exit 0
            ;;
        --sync-helper)
            sync_repos "$2" "${3:-false}" "${4:-false}"
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

    # 1. Single Git Repo Mode: If target is already inside a git work tree, open view_tool directly
    if [ "$overview" != "true" ] && git -C "$target_dir" rev-parse --is-inside-work-tree &>/dev/null; then
        local git_root
        git_root="$(git -C "$target_dir" rev-parse --show-toplevel)"
        open_view_tool "$git_root"
        exit 0
    fi

    # 2. Multi-Repo Mode: Interactive Dashboard
    local initial_query=""
    [ "$dirty_only" = true ] && initial_query=" "

    local editor_cmd="${CONFIG_EDIT_TOOL:-${EDITOR:-nvim}}"
    command -v "$editor_cmd" &>/dev/null || editor_cmd="vim"
    command -v "$editor_cmd" &>/dev/null || editor_cmd="nano"

    # Disable terminal flow control so Ctrl-S can be captured cleanly
    stty -ixon 2>/dev/null || true

    local scan_cmd="$SCRIPT_PATH --scan-helper '$target_dir' $recursive"

    while true; do
        local selected
        selected="$($scan_cmd | fzf \
            --ansi \
            --no-multi \
            --no-hscroll \
            --pointer=" " \
            --delimiter=$'\t' \
            --with-nth=1 \
            --header-lines=3 \
            --prompt="󰊢 repowatch [$(basename "$target_dir")] ❯ " \
            --query="$initial_query" \
            --preview="$SCRIPT_PATH --preview-helper {2}" \
            --preview-window="right:${CONFIG_PREVIEW_PERCENT:-50}%:wrap:border-left" \
            --bind="ctrl-d:transform-query(if [[ {q} == ** ]]; then echo ''; else echo ' '; fi)" \
            --bind="ctrl-e:execute($editor_cmd {2} < /dev/tty > /dev/tty 2>&1)+reload($scan_cmd)" \
            --bind="ctrl-g:execute-silent($SCRIPT_PATH --browser-helper {2})" \
            --bind="ctrl-o:execute(cd {2} && \${SHELL:-bash} < /dev/tty > /dev/tty 2>&1)+reload($scan_cmd)" \
            --bind="ctrl-r:reload($scan_cmd)" \
            --bind="ctrl-s:reload($SCRIPT_PATH --sync-helper '$target_dir' $recursive)" \
            --bind="ctrl-u:reload($SCRIPT_PATH --fetch-helper '$target_dir' $recursive)" \
            --expect=enter,ctrl-c,esc || true)"

        local key
        key="$(echo "$selected" | head -n1)"
        local selection
        selection="$(echo "$selected" | sed 1d)"

        if [ -z "$selection" ] || [[ "$key" == "esc" || "$key" == "ctrl-c" ]]; then
            break
        fi

        local repo_path="${selection##*$'\t'}"

        if [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
            initial_query=""
            open_view_tool "$repo_path"
        else
            break
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
