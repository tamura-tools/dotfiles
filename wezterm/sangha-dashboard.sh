#!/bin/bash
# ============================================
#  Sangha Dashboard v1.3 (macOS/Linux)
#  WezTerm Pane Dashboard with Todoist + Clock
# ============================================

# --- Configuration ---
API_KEY="YOUR_API_KEY_HERE"  # Todoist APIキーを貼る
INTERVAL=60
THM="tokyo-night"

# ESC
E=$'\033'
R="${E}[0m"
B="${E}[1m"

# --- Color Themes ---
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

# Separator
SEP="${C_border}$(printf '─%.0s' {1..44})${R}"

# Hide cursor
printf "${E}[?25l"

cleanup() {
    printf "${E}[?25h"
    exit 0
}
trap cleanup EXIT INT TERM

# --- Main Loop ---
while true; do
    # --- Fetch Todoist tasks ---
    tasks_json=""
    completed_count=0
    task_count=0

    if [ "$API_KEY" != "YOUR_API_KEY_HERE" ]; then
        tasks_json=$(curl -s -H "Authorization: Bearer $API_KEY" \
            "https://api.todoist.com/rest/v2/tasks?filter=today%7Coverdue" 2>/dev/null)

        today=$(date -u +"%Y-%m-%dT00:00:00")
        completed_json=$(curl -s -H "Authorization: Bearer $API_KEY" \
            "https://api.todoist.com/sync/v9/completed/get_all?since=$today" 2>/dev/null)
        completed_count=$(echo "$completed_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('items',[])))" 2>/dev/null || echo 0)

        task_count=$(echo "$tasks_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo 0)
    fi

    all_total=$((task_count + completed_count))

    # --- Time (JST) ---
    time_str=$(TZ="Asia/Tokyo" date +"%H:%M:%S")
    date_str=$(TZ="Asia/Tokyo" date +"%Y-%m-%d (%a)")

    # --- Render ---
    clear

    # Header
    echo ""
    echo "  ${C_accent}${B}  Sangha Dashboard${R}"
    echo "  ${SEP}"
    echo ""
    echo "  ${C_highlight}${B}  ${time_str}${R}"
    echo "  ${C_fg}  ${date_str}${R}"
    echo ""
    echo "  ${SEP}"

    # Tasks
    echo ""
    echo "  ${C_cyan}${B}  Today's Tasks${R}"
    echo ""

    if [ "$task_count" -eq 0 ] 2>/dev/null; then
        echo "  ${C_success}  All clear!${R}"
    else
        echo "$tasks_json" | python3 -c "
import sys, json
tasks = json.load(sys.stdin)
tasks.sort(key=lambda t: t.get('priority', 1), reverse=True)
E = '\033'
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
    if len(name) > 30:
        name = name[:27] + '...'
    pad = ' ' * max(0, 30 - len(name))
    print(f'  ${C_fg}  ○ {name}{pad}{pc}({pl}){R}')
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
    f_bar=$(printf '█%.0s' $(seq 1 $fill 2>/dev/null) 2>/dev/null)
    e_bar=$(printf '░%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null)
    # Handle zero case
    [ "$fill" -eq 0 ] && f_bar=""
    [ "$empty" -eq 0 ] && e_bar=""
    echo "  ${C_success}  [OK] ${completed_count}/${all_total} done${R}  ${C_success}${f_bar}${C_dim}${e_bar}${R}"

    # Footer
    echo ""
    echo "  ${SEP}"
    echo "  ${C_dim}  Refresh: ${INTERVAL}s  |  Theme: ${THM}${R}"
    echo "  ${C_dim}  Ctrl+C: exit${R}"

    sleep $INTERVAL
done
