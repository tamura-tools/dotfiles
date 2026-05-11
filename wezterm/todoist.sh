#!/bin/bash
# ============================================
#  Todoist Dashboard (macOS/Linux)
#  WezTerm Pane Dashboard with Todoist + Clock
#  Interactive: [a]dd  [c]omplete  [d]elete  [r]efresh  [q]uit
# ============================================

API_KEY="${TODOIST_API_KEY:-}"
INTERVAL=60
THM="tokyo-night"

E=$'\033'
R="${E}[0m"
B="${E}[1m"

RUNTIME_DIR="${TMPDIR:-/tmp}/todoist-dashboard-$$"
mkdir -p "$RUNTIME_DIR"
IDS_FILE="$RUNTIME_DIR/task_ids"
: > "$IDS_FILE"

declare_theme() {
    case "$THM" in
        tokyo-night)
            C_fg="${E}[38;2;169;177;214m"
            C_accent="${E}[38;2;187;154;247m"
            C_highlight="${E}[38;2;224;175;104m"
            C_success="${E}[38;2;158;206;106m"
            C_warning="${E}[38;2;224;175;104m"
            C_error="${E}[38;2;247;118;142m"
            C_dim="${E}[38;2;86;95;137m"
            C_cyan="${E}[38;2;125;207;255m"
            C_border="${E}[38;2;60;64;90m"
            ;;
        synthwave)
            C_fg="${E}[38;2;230;210;255m"
            C_accent="${E}[38;2;255;56;172m"
            C_highlight="${E}[38;2;255;198;68m"
            C_success="${E}[38;2;114;255;178m"
            C_warning="${E}[38;2;255;198;68m"
            C_error="${E}[38;2;255;56;100m"
            C_dim="${E}[38;2;100;80;130m"
            C_cyan="${E}[38;2;54;215;255m"
            C_border="${E}[38;2;80;60;110m"
            ;;
        dracula)
            C_fg="${E}[38;2;248;248;242m"
            C_accent="${E}[38;2;189;147;249m"
            C_highlight="${E}[38;2;241;250;140m"
            C_success="${E}[38;2;80;250;123m"
            C_warning="${E}[38;2;255;184;108m"
            C_error="${E}[38;2;255;85;85m"
            C_dim="${E}[38;2;98;114;164m"
            C_cyan="${E}[38;2;139;233;253m"
            C_border="${E}[38;2;68;71;90m"
            ;;
        nord)
            C_fg="${E}[38;2;216;222;233m"
            C_accent="${E}[38;2;136;192;208m"
            C_highlight="${E}[38;2;235;203;139m"
            C_success="${E}[38;2;163;190;140m"
            C_warning="${E}[38;2;235;203;139m"
            C_error="${E}[38;2;191;97;106m"
            C_dim="${E}[38;2;76;86;106m"
            C_cyan="${E}[38;2;143;188;187m"
            C_border="${E}[38;2;67;76;94m"
            ;;
        gruvbox)
            C_fg="${E}[38;2;235;219;178m"
            C_accent="${E}[38;2;211;134;155m"
            C_highlight="${E}[38;2;250;189;47m"
            C_success="${E}[38;2;184;187;38m"
            C_warning="${E}[38;2;254;128;25m"
            C_error="${E}[38;2;251;73;52m"
            C_dim="${E}[38;2;124;111;100m"
            C_cyan="${E}[38;2;131;165;152m"
            C_border="${E}[38;2;80;73;69m"
            ;;
        catppuccin)
            C_fg="${E}[38;2;205;214;244m"
            C_accent="${E}[38;2;203;166;247m"
            C_highlight="${E}[38;2;249;226;175m"
            C_success="${E}[38;2;166;227;161m"
            C_warning="${E}[38;2;250;179;135m"
            C_error="${E}[38;2;243;139;168m"
            C_dim="${E}[38;2;88;91;112m"
            C_cyan="${E}[38;2;137;220;235m"
            C_border="${E}[38;2;69;71;90m"
            ;;
    esac
}

declare_theme

SEP="${C_border}$(printf '\xe2\x94\x80%.0s' {1..44})${R}"

printf "${E}[?25l"

cleanup() {
    printf "${E}[?25h"
    rm -rf "$RUNTIME_DIR" 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

if [ -z "$API_KEY" ]; then
    echo ""
    echo "  ${C_error}${B}! TODOIST_API_KEY is not set${R}"
    echo ""
    echo "  ${C_fg}Add to ~/.zshenv:${R}"
    echo "  ${C_cyan}export TODOIST_API_KEY=\"your-api-key\"${R}"
    echo ""
    echo "  ${C_dim}Then restart WezTerm${R}"
    echo ""
    sleep 5
fi

# --- Todoist API helpers ----------------------------------------

api_get() {
    # $1: path
    curl -s -H "Authorization: Bearer $API_KEY" \
        "https://api.todoist.com/api/v1$1" 2>/dev/null
}

api_post() {
    # $1: path  $2: json body (or empty)
    if [ -n "$2" ]; then
        curl -s -X POST \
            -H "Authorization: Bearer $API_KEY" \
            -H "Content-Type: application/json; charset=utf-8" \
            -d "$2" \
            "https://api.todoist.com/api/v1$1" 2>/dev/null
    else
        curl -s -X POST \
            -H "Authorization: Bearer $API_KEY" \
            "https://api.todoist.com/api/v1$1" 2>/dev/null
    fi
}

api_delete() {
    curl -s -X DELETE -H "Authorization: Bearer $API_KEY" \
        "https://api.todoist.com/api/v1$1" 2>/dev/null
}

show_message() {
    # $1: text  $2: color (default dim)  $3: seconds (default 1)
    local color="${2:-$C_dim}"
    local secs="${3:-1}"
    echo ""
    echo "  ${color}  ${1}${R}"
    sleep "$secs"
}

read_line() {
    # $1: prompt  -> echoes line on stdout
    printf "${E}[?25h"
    echo ""
    printf "  ${C_cyan}> %s:${R} " "$1"
    local line
    IFS= read -r line
    printf "${E}[?25l"
    printf '%s' "$line"
}

resolve_task_id() {
    # $1: number string  -> echoes id on stdout, or empty
    local num="$1"
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        show_message "[ERR] Not a number" "$C_error"
        return 1
    fi
    local total
    total=$(wc -l < "$IDS_FILE" | tr -d ' ')
    if [ "$num" -lt 1 ] || [ "$num" -gt "$total" ]; then
        show_message "[ERR] Out of range (1-$total)" "$C_error"
        return 1
    fi
    sed -n "${num}p" "$IDS_FILE"
    return 0
}

do_add() {
    if [ -z "$API_KEY" ]; then show_message "API not set" "$C_warning"; return; fi
    local content
    content=$(read_line "Add task")
    [ -z "$content" ] && return
    local body
    body=$(python3 -c "
import json, sys
print(json.dumps({'content': sys.argv[1], 'due_string': 'today'}))
" "$content")
    local resp
    resp=$(api_post "/tasks" "$body")
    if echo "$resp" | python3 -c "import sys, json; json.loads(sys.stdin.read()).get('id')" >/dev/null 2>&1; then
        show_message "[OK] Added" "$C_success"
    else
        show_message "[ERR] Failed to add" "$C_error" 2
    fi
}

do_complete() {
    if [ -z "$API_KEY" ]; then show_message "API not set" "$C_warning"; return; fi
    local total
    total=$(wc -l < "$IDS_FILE" | tr -d ' ')
    if [ "$total" -eq 0 ]; then show_message "No tasks" "$C_dim"; return; fi
    local num id
    num=$(read_line "Complete # (1-$total)")
    [ -z "$num" ] && return
    id=$(resolve_task_id "$num") || return
    if [ -z "$id" ]; then return; fi
    api_post "/tasks/$id/close" "" >/dev/null
    show_message "[OK] Completed #$num" "$C_success"
}

do_delete() {
    if [ -z "$API_KEY" ]; then show_message "API not set" "$C_warning"; return; fi
    local total
    total=$(wc -l < "$IDS_FILE" | tr -d ' ')
    if [ "$total" -eq 0 ]; then show_message "No tasks" "$C_dim"; return; fi
    local num id
    num=$(read_line "Delete # (1-$total)")
    [ -z "$num" ] && return
    id=$(resolve_task_id "$num") || return
    if [ -z "$id" ]; then return; fi
    api_delete "/tasks/$id" >/dev/null
    show_message "[OK] Deleted #$num" "$C_success"
}

# --- Main loop --------------------------------------------------

while true; do
    tasks_json="[]"
    task_count=0
    completed_count=0

    if [ -n "$API_KEY" ]; then
        today_date=$(TZ="Asia/Tokyo" date +"%Y-%m-%d")
        raw_json=$(api_get "/tasks")

        # Filter, sort, and emit JSON of displayed tasks
        tasks_json=$(echo "$raw_json" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', []) if isinstance(data, dict) else (data if isinstance(data, list) else [])
    today = '$today_date'
    filtered = [t for t in results if t.get('due') and t['due'].get('date','') <= today]
    filtered.sort(key=lambda t: t.get('priority', 1), reverse=True)
    print(json.dumps(filtered))
except Exception:
    print('[]')
" 2>/dev/null)

        # Write IDs in display order
        echo "$tasks_json" | python3 -c "
import sys, json
try:
    tasks = json.load(sys.stdin)
    for t in tasks:
        print(t.get('id', ''))
except Exception:
    pass
" > "$IDS_FILE" 2>/dev/null

        task_count=$(wc -l < "$IDS_FILE" | tr -d ' ')

        today_iso=$(TZ="Asia/Tokyo" date +"%Y-%m-%dT00:00:00")
        completed_json=$(api_get "/tasks/completed?since=$today_iso")
        completed_count=$(echo "$completed_json" | python3 -c "
import sys, json
try:
    print(len(json.load(sys.stdin).get('items', [])))
except Exception:
    print(0)
" 2>/dev/null)
    fi

    task_count=${task_count:-0}
    completed_count=${completed_count:-0}
    all_total=$((task_count + completed_count))

    time_str=$(TZ="Asia/Tokyo" date +"%H:%M:%S")
    date_str=$(TZ="Asia/Tokyo" date +"%Y-%m-%d (%a)")

    clear

    echo ""
    echo "  ${C_accent}${B}  Todoist Dashboard${R}"
    echo "  ${SEP}"
    echo ""
    echo "  ${C_highlight}${B}  ${time_str}${R}"
    echo "  ${C_fg}  ${date_str}${R}"
    echo ""
    echo "  ${SEP}"

    echo ""
    echo "  ${C_cyan}${B}  Today's Tasks${R}"
    echo ""

    if [ -z "$API_KEY" ]; then
        echo "  ${C_warning}  API not set${R}"
    elif [ "$task_count" -eq 0 ] 2>/dev/null; then
        echo "  ${C_success}  All clear!${R}"
    else
        echo "$tasks_json" | python3 -c "
import sys, json
tasks = json.load(sys.stdin)
if not isinstance(tasks, list):
    sys.exit(0)
R = '${R}'
B = '${B}'
colors = {
    4: ('${C_error}', 'p1'),
    3: ('${C_warning}', 'p2'),
    2: ('${C_cyan}', 'p3'),
    1: ('${C_dim}', 'p4'),
}
for i, t in enumerate(tasks[:12]):
    p = t.get('priority', 1)
    pc, pl = colors.get(p, ('${C_dim}', 'p4'))
    name = t.get('content', '')
    if len(name) > 28:
        name = name[:25] + '...'
    pad = ' ' * max(0, 28 - len(name))
    num = f'{i+1:2d}'
    print(f'  ${C_dim}[{num}]{R} ${C_fg}{name}{pad}{pc}({pl}){R}')
if len(tasks) > 12:
    rem = len(tasks) - 12
    print(f'  ${C_dim}  ... +{rem} more{R}')
" 2>/dev/null
    fi

    echo ""
    echo "  ${SEP}"
    echo ""

    # Progress bar
    bar_w=20
    fill=0
    if [ "$all_total" -gt 0 ]; then
        fill=$((completed_count * bar_w / all_total))
    fi
    empty=$((bar_w - fill))
    f_bar=$(printf '\xe2\x96\x88%.0s' $(seq 1 $fill 2>/dev/null) 2>/dev/null)
    e_bar=$(printf '\xe2\x96\x91%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null)
    [ "$fill" -eq 0 ] && f_bar=""
    [ "$empty" -eq 0 ] && e_bar=""
    echo "  ${C_success}  [OK] ${completed_count}/${all_total} done${R}  ${C_success}${f_bar}${C_dim}${e_bar}${R}"

    echo ""
    echo "  ${SEP}"
    echo "  ${C_dim}  [a]dd  [c]omplete  [d]elete  [r]efresh  [q]uit${R}"
    echo "  ${C_dim}  Refresh: ${INTERVAL}s  |  Theme: ${THM}${R}"

    # --- Wait for INTERVAL seconds or a keypress ---------------
    action=""
    elapsed=0
    while [ "$elapsed" -lt "$INTERVAL" ] && [ -z "$action" ]; do
        key=""
        read -t 1 -n 1 -s key
        case "$key" in
            a) action="add" ;;
            c) action="complete" ;;
            d) action="delete" ;;
            r) action="refresh" ;;
            q) action="quit" ;;
        esac
        elapsed=$((elapsed + 1))
    done

    case "$action" in
        add)      do_add ;;
        complete) do_complete ;;
        delete)   do_delete ;;
        quit)     break ;;
    esac
done

cleanup
