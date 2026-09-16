#!/bin/bash

# Claude Code Status Line — hybrid edition
#   Base:  tzengyuxio/claude-statusline (2-line layout, official 5h/7d quota, git status)
#   Plus:  ccsl-style 5h window (elapsed/5h + reset clock), plain-text icon mode,
#          upstream update notice, Windows (Git Bash) compatibility fixes.
#
# Line 1: Model │ ctx ★ ★ ★ ★ ☆ ☆ ☆ ☆ ☆ ☆ 42% │ Cost   │ 5h ★ ★ ★ ★ ☆ ☆ ☆ ☆ ☆ ☆  40% elapsed/5h reset HH:MM
# Line 2: Directory │ Git Branch & Status │ Venv │ Vim │ session │ 7d ★ ☆ ☆ ☆ ☆ ☆ ☆ ☆ ☆ ☆   8%     reset M/D HH:MM   (usage column aligned, tails right-aligned)

input=$(cat)
now=$(date +%s)

# ==================== User settings ====================
# Icons: 1 = Nerd Font glyphs, 0 = plain text (works with any font)
USE_NERD_FONT="${STATUSLINE_NERD_FONT:-0}"
CACHE_TTL=60              # seconds between usage API refreshes
UPDATE_CHECK_TTL=86400    # seconds between upstream update checks (1 day); 0 = disable
UPSTREAM_URL="https://raw.githubusercontent.com/tzengyuxio/claude-statusline/main/statusline-command.sh"
UPSTREAM_BASE_SHA="6fcf104c6f731da982483bd9ec9af889aa9a7a19ade251c7cf7146df07c310e2"  # upstream version this file was patched from
# =======================================================

# Portable file mtime (GNU stat on Linux/Git Bash, BSD stat on macOS)
file_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f%m "$1" 2>/dev/null || echo 0
}

# Portable epoch -> local time formatting (GNU date first, BSD date fallback)
fmt_epoch() {
    date -d "@$1" "+$2" 2>/dev/null || date -r "$1" "+$2" 2>/dev/null
}

# --- Extract all values in a single jq call (tr strips CRLF from Windows jq) ---
eval "$(jq -r '
    @sh "model=\(.model.display_name // "?")",
    @sh "cwd=\(.workspace.current_dir // ".")",
    @sh "used_pct=\(.context_window.used_percentage // 0)",
    @sh "cost=\(.cost.total_cost_usd // 0)",
    @sh "duration_ms=\(.cost.total_duration_ms // 0)",
    @sh "lines_added=\(.cost.total_lines_added // 0)",
    @sh "lines_removed=\(.cost.total_lines_removed // 0)",
    @sh "vim_mode=\(.vim.mode // "")",
    @sh "rl_pct5h=\((.rate_limits.five_hour.used_percentage // -1) | floor)",
    @sh "rl_epoch5h=\((.rate_limits.five_hour.resets_at // 0) | floor)",
    @sh "rl_pct7d=\((.rate_limits.seven_day.used_percentage // -1) | floor)",
    @sh "rl_epoch7d=\((.rate_limits.seven_day.resets_at // 0) | floor)"
' <<< "$input" | tr -d '\r')"

dir_name="${cwd##*/}"

# --- Theme detection ---
# Override with STATUSLINE_THEME=dark|light|auto (default: auto)
detect_theme() {
    local theme="${STATUSLINE_THEME:-auto}"
    if [ "$theme" != "auto" ]; then echo "$theme"; return; fi

    # macOS system appearance
    if [ "$(uname -s)" = "Darwin" ] && defaults read -g AppleInterfaceStyle &>/dev/null; then
        echo "dark"; return
    fi

    # COLORFGBG env var (e.g. "15;0" → bg=0 is dark)
    if [ -n "$COLORFGBG" ]; then
        local bg="${COLORFGBG##*;}"
        if [ "$bg" -lt 8 ] 2>/dev/null; then
            echo "dark"
        else
            echo "light"
        fi
        return
    fi

    echo "dark"
}

THEME=$(detect_theme)

# --- Colors ---
RST=$'\033[0m'
BOLD=$'\033[1m'

if [ "$THEME" = "light" ]; then
    DIM=$'\033[90m'              # bright black (gray) — visible on light bg
    CYAN=$'\033[36m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
    MAGENTA=$'\033[35m'
    BLUE=$'\033[34m'
    BG_RED=$'\033[41m'
    WHITE_BOLD=$'\033[1;30m'     # bold black — for alert badge text on light bg
else
    DIM=$'\033[2m'
    CYAN=$'\033[36m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
    MAGENTA=$'\033[35m'
    BLUE=$'\033[34m'
    BG_RED=$'\033[41m'
    WHITE_BOLD=$'\033[1;37m'
fi

# --- Icons ---
if [ "$USE_NERD_FONT" = "1" ]; then
    ICON_MODEL="󰚩"     # nf-md-robot
    ICON_CTX="󰍛"       # nf-md-memory
    ICON_DIR="󰝰"       # nf-md-folder_outline
    ICON_GIT="󰘬"       # nf-md-source_branch
    ICON_COST="󰄉"      # nf-md-cash
    ICON_WARN=""       # nf-fa-warning
    ICON_VIM="󰕷"       # nf-md-vim
    ICON_VENV="󰌠"      # nf-md-language_python
    ICON_UPD="󰚰"       # nf-md-update
    ICON_TIMER="󰅐"     # nf-md-clock_outline
else
    ICON_MODEL="◆"
    ICON_CTX="ctx"
    ICON_DIR="▸"
    ICON_GIT="⎇"
    ICON_COST=""
    ICON_WARN="!"
    ICON_VIM="vi"
    ICON_VENV="py"
    ICON_UPD="↑"
    ICON_TIMER="◷"
fi

QUOTA_WARN=80   # 5h usage % at which the red badge appears

SEP="${DIM} │ ${RST}"

# --- Color helper for utilization percentage ---
# Thresholds: green < 50, yellow 50-79, red >= 80
pct_color() {
    local pct=$1
    if [ "$pct" -lt 50 ]; then echo "$GREEN"
    elif [ "$pct" -lt 80 ]; then echo "$YELLOW"
    else echo "$RED"
    fi
}

# --- Context percentage ---
pct_int=${used_pct%.*}
pct_int=${pct_int:-0}
CTX_COLOR=$(pct_color "$pct_int")

# --- Star gauge: ★ ★ ★ ★ ☆ ☆ ☆ ☆ ☆ ☆ (STAR_SEGMENTS stars, rounded to nearest) ---
# Used for the context bar and the 5h / 7d usage gauges.
STAR_SEGMENTS=10
# Spacing inserted between stars (set to "" for a tight gauge).
STAR_GAP=" "
star_gauge() {
    local pct=$1 filled empty g="" i sep=""
    filled=$(( (pct * STAR_SEGMENTS + 50) / 100 ))
    [ "$filled" -gt "$STAR_SEGMENTS" ] && filled=$STAR_SEGMENTS
    [ "$filled" -lt 0 ] && filled=0
    empty=$((STAR_SEGMENTS - filled))
    for ((i = 0; i < filled; i++)); do g="${g}${sep}★"; sep=$STAR_GAP; done
    for ((i = 0; i < empty; i++)); do g="${g}${sep}☆"; sep=$STAR_GAP; done
    echo "$g"
}

# --- Context gauge ---
bar=$(star_gauge "$pct_int")

# --- Cost ---
printf -v cost_str '$%.2f' "$cost"

# --- Git info (single git status --porcelain call) ---
git_info=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch="detached"

    staged=0 unstaged=0 untracked=0
    while IFS= read -r line; do
        x=${line:0:1}
        y=${line:1:1}
        if [ "$x$y" = "??" ]; then
            ((untracked++))
        else
            [ "$x" != " " ] && [ "$x" != "?" ] && ((staged++))
            [ "$y" != " " ] && ((unstaged++))
        fi
    done < <(git -C "$cwd" status --porcelain 2>/dev/null)

    status=""
    [ "$staged" -gt 0 ] && status="${status} ${GREEN}+${staged}${RST}"
    [ "$unstaged" -gt 0 ] && status="${status} ${YELLOW}~${unstaged}${RST}"
    [ "$untracked" -gt 0 ] && status="${status} ${DIM}?${untracked}${RST}"

    git_info="${SEP}${MAGENTA}${ICON_GIT} ${branch}${RST}${status}"
fi

# --- Python venv detection (Unix bin/python or Windows Scripts/python.exe) ---
venv_str=""
venv_name="" py_ver=""
if [ -n "$VIRTUAL_ENV" ]; then
    venv_name="${VIRTUAL_ENV##*/}"
else
    for venv_dir in "$cwd/.venv" "$cwd/venv" "$cwd/.env"; do
        for py in "${venv_dir}/bin/python" "${venv_dir}/Scripts/python.exe"; do
            if [ -f "$py" ]; then
                venv_name="${venv_dir##*/}"
                py_ver=$("$py" --version 2>/dev/null | awk '{print $2}' | cut -d. -f1-2)
                break 2
            fi
        done
    done
fi
if [ -n "$venv_name" ]; then
    venv_str="${SEP}${YELLOW}${ICON_VENV} ${venv_name}${py_ver:+ ($py_ver)}${RST}"
fi

# --- Vim mode ---
vim_str=""
if [ -n "$vim_mode" ]; then
    [[ "$vim_mode" == "NORMAL" ]] && vim_color=$BLUE || vim_color=$GREEN
    vim_str="${SEP}${vim_color}${BOLD}${ICON_VIM} ${vim_mode}${RST}"
fi

# --- Anthropic OAuth usage API (cached, background refresh) ---
CACHE_DIR="$HOME/.claude/statusline-cache"
USAGE_CACHE="$CACHE_DIR/usage.dat"
LOCK_FILE="$CACHE_DIR/usage-update.lock"
[ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR" 2>/dev/null

refresh_usage_cache() {
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        lock_age=$(( now - $(file_mtime "$LOCK_FILE") ))
        [ "$lock_age" -gt 60 ] && rm -r "$LOCK_FILE" 2>/dev/null || return
        mkdir "$LOCK_FILE" 2>/dev/null || return
    fi
    (
        # macOS Keychain first (macOS only), then the credentials file
        token=""
        [ "$(uname -s)" = "Darwin" ] && token=$(security find-generic-password -s "Claude Code-credentials" -a "$(whoami)" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        [ -z "$token" ] && token=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
        if [ -n "$token" ]; then
            resp=$(curl -s --max-time 5 \
                -H "Authorization: Bearer $token" \
                -H "anthropic-beta: oauth-2025-04-20" \
                https://api.anthropic.com/api/oauth/usage 2>/dev/null)
            if echo "$resp" | jq -e '.five_hour' > /dev/null 2>&1; then
                echo "$resp" | jq -r '
                    def to_epoch:
                        if . == null or . == "" then 0
                        else (sub("[.][0-9]+";"") | sub("[+]00:00$";"Z") | (if endswith("Z") then . else . + "Z" end) | fromdateiso8601)
                        end;
                    "\(.five_hour.utilization // 0 | floor) \(.five_hour.resets_at | to_epoch) \(.seven_day.utilization // 0 | floor) \(.seven_day.resets_at | to_epoch)"
                ' 2>/dev/null | tr -d '\r' > "$USAGE_CACHE.tmp" && mv "$USAGE_CACHE.tmp" "$USAGE_CACHE"
            fi
        fi
        rm -r "$LOCK_FILE" 2>/dev/null
    ) > /dev/null 2>&1 &
    disown 2>/dev/null
}

fmt_hm() {
    local s=$1
    [ "$s" -lt 0 ] && s=0
    echo "$((s / 3600))h$((s % 3600 / 60))m"
}

# Star gauge: ★ ★ ★ ★ ☆ ☆ ☆ ☆ ☆ ☆ (STAR_SEGMENTS stars, rounded to nearest)
# Usage segments are built as head ("5h ★ ★ ★ ☆ ☆ ☆ ☆ ☆ ☆ ☆  16%") + tail ("0h19m/5h reset 02:50").
# The tails are later padded to equal width so the two lines end at the same column.

# 5h window, ccsl style:  5h ★ ★ ★ ☆ ☆ ☆ ☆ ☆ ☆ ☆  16% 0h19m/5h reset 02:50
# Sets head_5h / tail_5h.
seg_5h() {
    local pct=$1 reset=$2 show_clock=$3 color
    color=$(pct_color "$pct")
    head_5h="${SEP}${DIM}5h${RST} ${color}$(star_gauge "$pct") $(printf "%3d" "$pct")%${RST}"
    tail_5h=""
    if [ "$reset" -gt 0 ] 2>/dev/null; then
        local start=$((reset - 18000)) elapsed clock
        elapsed=$((now - start))
        [ "$elapsed" -gt 18000 ] && elapsed=18000
        clock=$(fmt_epoch "$reset" "%H:%M")
        tail_5h="$(fmt_hm "$elapsed")/5h"
        [ "$show_clock" = "1" ] && tail_5h="${tail_5h} reset ${clock}"
    fi
}

# 7d window:  7d ★ ★ ☆ ☆ ☆ ☆ ☆ ☆ ☆ ☆  24% reset 9/3 15:00
# Sets head_7d / tail_7d.
seg_7d() {
    local pct=$1 reset=$2 color
    color=$(pct_color "$pct")
    head_7d="${SEP}${DIM}7d${RST} ${color}$(star_gauge "$pct") $(printf "%3d" "$pct")%${RST}"
    tail_7d=""
    if [ "$reset" -gt 0 ] 2>/dev/null; then
        tail_7d="reset $(fmt_epoch "$reset" "%-m/%-d %H:%M")"
    fi
}

# --- Usage source: Claude Code's built-in rate_limits (fresh, no network) first;
#     fall back to the OAuth usage API cache when the JSON carries no rate_limits.
usage_5h="" usage_7d="" quota_badge="" head_5h="" tail_5h="" head_7d="" tail_7d=""
pct5h="" epoch5h="" pct7d="" epoch7d="" usage_src=""
if [ "${rl_pct5h:--1}" -ge 0 ] 2>/dev/null; then
    pct5h=$rl_pct5h epoch5h=$rl_epoch5h pct7d=$rl_pct7d epoch7d=$rl_epoch7d
    usage_src="builtin"
else
    if [ ! -f "$USAGE_CACHE" ]; then
        refresh_usage_cache
    else
        cache_age=$(( now - $(file_mtime "$USAGE_CACHE") ))
        [ "$cache_age" -gt "$CACHE_TTL" ] && refresh_usage_cache
    fi
    if [ -f "$USAGE_CACHE" ]; then
        read -r pct5h epoch5h pct7d epoch7d < "$USAGE_CACHE" 2>/dev/null
        epoch7d=${epoch7d//$'\r'/}
        usage_src="api"
    fi
fi
if [ -n "$usage_src" ]; then
    if [ -n "$pct5h" ] && [ "$pct5h" != "-1" ]; then
        if [ "$pct5h" -ge "$QUOTA_WARN" ] 2>/dev/null; then
            badge_clock=""
            [ "${epoch5h:-0}" -gt 0 ] 2>/dev/null && badge_clock=" reset $(fmt_epoch "$epoch5h" "%H:%M")"
            quota_badge="${BG_RED}${WHITE_BOLD} ${ICON_WARN} 5h ${pct5h}%${badge_clock} ${RST} "
        fi
        seg_5h "$pct5h" "${epoch5h:-0}" 1
    fi
    if [ -n "$pct7d" ] && [ "$pct7d" != "-1" ]; then
        seg_7d "$pct7d" "${epoch7d:-0}"
    fi
    # Right-align the tails: pad the shorter one on the left so both lines end at the same column
    tail_w=$(( ${#tail_5h} > ${#tail_7d} ? ${#tail_5h} : ${#tail_7d} ))
    [ -n "$head_5h" ] && usage_5h="${head_5h}${tail_5h:+ ${DIM}$(printf "%${tail_w}s" "$tail_5h")${RST}}"
    [ -n "$head_7d" ] && usage_7d="${head_7d}${tail_7d:+ ${DIM}$(printf "%${tail_w}s" "$tail_7d")${RST}}"
fi

# --- Session elapsed time + lines added/removed ---
session_str=""
if [ "${duration_ms:-0}" -gt 0 ] 2>/dev/null; then
    session_str="${SEP}${DIM}${ICON_TIMER} $(fmt_hm $((duration_ms / 1000)))${RST}"
    if [ "${lines_added:-0}" -gt 0 ] || [ "${lines_removed:-0}" -gt 0 ]; then
        session_str="${session_str} ${GREEN}+${lines_added}${RST}${DIM}/${RST}${RED}-${lines_removed}${RST}"
    fi
fi

# --- Upstream update notice (checked once per UPDATE_CHECK_TTL, never auto-applied) ---
UPD_STAMP="$CACHE_DIR/upstream.check"
UPD_SHA_FILE="$CACHE_DIR/upstream.sha"
upd_str=""
if [ "$UPDATE_CHECK_TTL" -gt 0 ] 2>/dev/null; then
    if [ ! -f "$UPD_STAMP" ] || [ $(( now - $(file_mtime "$UPD_STAMP") )) -gt "$UPDATE_CHECK_TTL" ]; then
        touch "$UPD_STAMP" 2>/dev/null
        (
            sha=$(curl -fsSL --max-time 5 "$UPSTREAM_URL" 2>/dev/null | sha256sum 2>/dev/null | cut -d' ' -f1)
            [ ${#sha} -eq 64 ] && echo "$sha" > "$UPD_SHA_FILE"
        ) > /dev/null 2>&1 &
        disown 2>/dev/null
    fi
    if [ -f "$UPD_SHA_FILE" ]; then
        read -r upstream_sha < "$UPD_SHA_FILE"
        upstream_sha=${upstream_sha//$'\r'/}
        if [ -n "$upstream_sha" ] && [ "$upstream_sha" != "$UPSTREAM_BASE_SHA" ]; then
            upd_str="${SEP}${DIM}${ICON_UPD} upstream updated${RST}"
        fi
    fi
fi

# --- Build output ---
# Layout: usage segments form a right-hand column (5h on line 1, 7d on line 2) that starts
# just after the longer of the two left parts, so both lines line up vertically.
visible_len() {
    local s
    s=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g')
    echo "${#s}"
}
# pad_to STR COL -> STR padded with spaces up to visible width COL
pad_to() {
    local str=$1 col=$2 pad
    pad=$(( col - $(visible_len "$str") ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%s%*s' "$str" "$pad" ""
}

cost_seg="${DIM}${ICON_COST:+$ICON_COST }${cost_str}${RST}"
line1_tail="${SEP}${cost_seg}"

if [ "$pct_int" -ge 90 ]; then
    line1="${BG_RED}${WHITE_BOLD} ${ICON_WARN} CTX ${pct_int}% ${RST} ${quota_badge}${CYAN}${BOLD}${ICON_MODEL} ${model}${RST}${SEP}${CTX_COLOR}${bar}${RST}${line1_tail}"
else
    line1="${quota_badge}${CYAN}${BOLD}${ICON_MODEL} ${model}${RST}${SEP}${DIM}${ICON_CTX}${RST} ${CTX_COLOR}${bar} ${pct_int}%${RST}${line1_tail}"
fi

line2="${BLUE}${ICON_DIR} ${dir_name}${RST}${git_info}${venv_str}${vim_str}${session_str}${upd_str}"

# Right column: both usage segments (which start with SEP) begin at the same column
if [ -n "$usage_5h" ] || [ -n "$usage_7d" ]; then
    len1=$(visible_len "$line1")
    len2=$(visible_len "$line2")
    col=$(( len1 > len2 ? len1 : len2 ))
    line1="$(pad_to "$line1" "$col")${usage_5h}"
    line2="$(pad_to "$line2" "$col")${usage_7d}"
fi

printf '%s\n%s' "$line1" "$line2"
