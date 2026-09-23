#!/bin/bash
# herdr-bootstrap.sh — Mac版 Herdr ブートストラップ
# Windows の herdr-bootstrap.ps1 と同じ役割構成。Mac固有の既存差異は維持する。
# WezTerm gui-startup からバックグラウンド実行される。
# 用法: herdr-bootstrap.sh [--configure-only] [--skip-extra] [--skip-review]
#
#   w1 デフォルト   : Commander / Sol / Utility / Codex Work - Main（旧 Status 枠）
#   w2 Extra        : Grok / Antigravity CLI / Claude Work - Extra / Codex Work - Extra
#   w3 🦍 EXECUTION : Supervisor / Reviewer A / Worker A / Worker B（中身は変更なし）
#   w4 🦍 受付      : Loop Inbox Receiver 枠。Mac には loop_intake.py が無いため何も起動しない
#   （2026-09-24 再編。Windows と同じ作成順）
#
# CommanderはSupervisorではない。実行LoopへはTask Packetをpendingへ投入して渡す。
# Supervisorへの直接相談と、Supervisor自身による成果物作成は禁止する。

set -euo pipefail

# ---------- PATH の再構成 ----------
# Dock/Finder から起動した WezTerm の子プロセスは PATH が /usr/bin:/bin:/usr/sbin:/sbin だけになる。
# さらに非対話ログインシェルは ~/.zshrc を読まないため codex(.npm-global) や grok(.grok) も落ちる。
# 対話 zsh と同じ並びをここで明示して、herdr も各AI CLI も必ず解決できるようにする（2026-08-30）。
for _d in "$HOME/.local/bin" "$HOME/.npm-global/bin" "$HOME/.grok/bin" \
          "$HOME/.bun/bin" "$HOME/.cargo/bin" \
          /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin; do
  case ":$PATH:" in
    *":$_d:"*) ;;
    *) [ -d "$_d" ] && PATH="$_d:$PATH" ;;
  esac
done
export PATH
unset _d

if ! command -v herdr >/dev/null 2>&1; then
  echo "Error: herdr が PATH 上に見つからない (PATH=$PATH)" >&2
  exit 1
fi

CONFIGURE_ONLY=false
SKIP_EXTRA=false
SKIP_REVIEW=false
for arg in "$@"; do
  case "$arg" in
    --configure-only) CONFIGURE_ONLY=true ;;
    --skip-extra)     SKIP_EXTRA=true ;;
    --skip-review)    SKIP_REVIEW=true ;;
  esac
done

WORK_ROOT="$HOME/claude"
CODEX_ACCOUNT_SCRIPT="$HOME/dotfiles/wezterm/codex-account.sh"

# ワークスペースは「番号順 = この並び順」で扱う。herdr には並べ替えコマンドが無く、
# 番号は作成順で決まる。新規セッションではこの順に作られ、既存セッションでは
# 不足分が末尾に追加される（順番を正すには herdr server の作り直しが要る）。
# ※「🦍 EXECUTION」のラベルと4役のペイン名は Windows 版と揃え、変更しないこと。
WORKSPACE_PLAN=('デフォルト' 'Extra' '🦍 EXECUTION' '🦍 受付')

legacy_label_for() {
  case "$1" in
    'デフォルト')    echo 'CONTROL / ENTRY' ;;
    'Extra')         echo 'Extra Agents' ;;
    '🦍 EXECUTION')  echo 'Review Agents' ;;
  esac
}

# ---------- サーバー管理 ----------

test_server() {
  herdr status server 2>/dev/null | grep -q 'running'
}

start_server() {
  if test_server; then return; fi
  nohup herdr server >/dev/null 2>&1 &
  for _ in $(seq 1 40); do
    sleep 0.25
    if test_server; then return; fi
  done
  echo 'Error: Herdr server did not start within 10s' >&2
  exit 1
}

# ---------- ワークスペース ----------

ws_labels_in_order() {
  herdr workspace list 2>/dev/null \
    | jq -r '.result.workspaces | sort_by(.number)[] | .label'
}

ws_ids_in_order() {
  herdr workspace list 2>/dev/null \
    | jq -r '.result.workspaces | sort_by(.number)[] | .workspace_id'
}

ws_id_by_label() {
  herdr workspace list 2>/dev/null \
    | jq -r --arg l "$1" '.result.workspaces[] | select(.label==$l) | .workspace_id' \
    | head -1
}

plan_contains() {
  local needle="$1" item
  for item in "${WORKSPACE_PLAN[@]}"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# 計画順にワークスペースを解決する。
#   1. 同じラベルが既にあればそれを使う
#   2. その位置に「計画外のラベル」のワークスペースがあれば採用してリネームする
#      （新規セッションの既定ワークスペースを w1 CORE として拾うため）
#   3. どちらでもなければ新規作成する（既存セッションでは末尾に付く）
resolve_workspace() {
  local index="$1" label="$2" ws_id legacy_label legacy_id candidate_id candidate_label

  ws_id=$(ws_id_by_label "$label")
  if [ -n "$ws_id" ]; then
    echo "$ws_id"
    return
  fi

  # 旧役割名は位置ではなくラベルで移行する。既存環境でReview Agentsが末尾に
  # ある場合もExtra Agentsを誤ってEXECUTIONへ転用しない。
  legacy_label=$(legacy_label_for "$label")
  legacy_id=$(ws_id_by_label "$legacy_label")
  if [ -n "$legacy_id" ]; then
    echo "Renaming workspace: $legacy_label -> $label" >&2
    herdr workspace rename "$legacy_id" "$label" >/dev/null
    echo "$legacy_id"
    return
  fi

  candidate_id=$(ws_ids_in_order | sed -n "$((index + 1))p")
  candidate_label=$(ws_labels_in_order | sed -n "$((index + 1))p")
  if [ -n "$candidate_id" ] && ! plan_contains "$candidate_label"; then
    echo "Renaming workspace: $candidate_label -> $label" >&2
    herdr workspace rename "$candidate_id" "$label" >/dev/null
    echo "$candidate_id"
    return
  fi

  echo "Creating workspace: $label" >&2
  herdr workspace create --label "$label" --cwd "$WORK_ROOT" --no-focus \
    | jq -r '.result.workspace.workspace_id'
}

# ---------- ペイン ----------
# pane_id は "w3:p1" 形式。作成順に採番されるので、番号順に並べれば
# 左上→右上→左下→右下 の並びになる。
sorted_pane_ids() {
  herdr pane list --workspace "$1" 2>/dev/null \
    | jq -r '.result.panes[].pane_id' \
    | sort -t: -k2 -V
}

pane_count() {
  herdr pane list --workspace "$1" 2>/dev/null | jq '.result.panes | length'
}

pane_id_by_label() {
  herdr pane list --workspace "$1" 2>/dev/null \
    | jq -r --arg l "$2" '.result.panes[] | select(.label==$l) | .pane_id' \
    | head -1
}

# 目標枚数までペインを用意する。既に足りていれば何もしない（冪等）。
init_pane_grid() {
  local ws_id="$1" want="$2" p1 p2
  if [ "$want" -eq 4 ] && [ "$(pane_count "$ws_id")" -eq 1 ]; then
    p1=$(sorted_pane_ids "$ws_id" | sed -n 1p)
    p2=$(herdr pane split --pane "$p1" --direction right --no-focus \
      | jq -r '.result.pane.pane_id')
    herdr pane split --pane "$p1" --direction down --no-focus >/dev/null
    herdr pane split --pane "$p2" --direction down --no-focus >/dev/null
  fi

  # 不足分は最後のペインを下に割って埋める
  while [ "$(pane_count "$ws_id")" -lt "$want" ]; do
    herdr pane split --pane "$(sorted_pane_ids "$ws_id" | tail -1)" \
      --direction down --no-focus >/dev/null
  done
}

# ラベルを pane_id 昇順で割り当てる。以降のエージェント起動は
# 並び順ではなくラベルで引く（herdr pane list の返却順は作成順ではない。2026-08-30の学び）。
apply_pane_labels() {
  local ws_id="$1"
  shift
  local i=1 pid
  for label in "$@"; do
    pid=$(sorted_pane_ids "$ws_id" | sed -n "${i}p")
    if [ -n "$pid" ]; then
      herdr pane rename "$pid" "$label" >/dev/null
    fi
    i=$((i + 1))
  done
}

# ---------- エージェント ----------

live_agent_pane_ids() {
  herdr agent list 2>/dev/null \
    | jq -r '.result.agents[].pane_id' 2>/dev/null || true
}

start_agent_if_missing() {
  local pane_id="$1" display_name="$2"
  shift 2
  if [ -z "$pane_id" ]; then
    echo "Required pane is missing: $display_name" >&2
    return 1
  fi
  if echo "$LIVE_PANE_IDS" | grep -qF "$pane_id"; then
    echo "Already running: $display_name"
    return 0
  fi
  echo "Starting: $display_name"
  herdr pane run "$pane_id" "$@"
}

# ---------- メイン ----------

start_server

CONTROL_WS=$(resolve_workspace 0 'デフォルト')
EXTRA_WS=$(resolve_workspace 1 'Extra')
EXECUTION_WS=$(resolve_workspace 2 '🦍 EXECUTION')
RECEPTION_WS=$(resolve_workspace 3 '🦍 受付')

# デフォルト: 相談窓口とTask Packet作成。CommanderはSupervisorではない。
# 4枚目は旧 Status 枠を Codex 会社にする（2026-09-24）。Codex 会社の2枠は
# 「Codex Work - Main」「Codex Work - Extra」とし、一方が他方の前方一致にならない名前にする。
init_pane_grid "$CONTROL_WS" 4
apply_pane_labels "$CONTROL_WS" \
  'Commander - Claude Work / Opus 5' 'Sol - Codex Personal / GPT-5.6 Sol' \
  'Utility - Claude Personal' 'Codex Work - Main'

# EXTRA: 4枚目は旧「Codex - Extra」を Windows と同じ「Codex Work - Extra」に改名（中身は同じ Codex 会社）。
init_pane_grid "$EXTRA_WS" 4
apply_pane_labels "$EXTRA_WS" \
  'Grok' 'Antigravity CLI' 'Claude Work - Extra' 'Codex Work - Extra'

# EXECUTION: 入力はTask Packetのみ。MVPはReviewer Aのみで1 Loopずつ処理する。
init_pane_grid "$EXECUTION_WS" 4
apply_pane_labels "$EXECUTION_WS" \
  'Supervisor - Claude Work / Opus 5' 'Reviewer A - Claude Work / Opus 5' \
  'Worker A - Gemini 3.8 Flash' 'Worker B - Claude Work / Sonnet 5'

# 🦍 受付: Windows と同じ名前の1枠だけ作る。Mac には loop_intake.py が無いため何も起動しない。
init_pane_grid "$RECEPTION_WS" 1
apply_pane_labels "$RECEPTION_WS" 'Loop Inbox Receiver'

LIVE_PANE_IDS=$(live_agent_pane_ids)

# Mac のプロファイル対応は Windows と逆:
#   個人 = 既定の ~/.claude / 会社 = ~/.claude-work
CLAUDE_WORK_DIR="$HOME/.claude-work"

# --- CONTROL / ENTRY ---
start_agent_if_missing "$(pane_id_by_label "$CONTROL_WS" 'Commander - Claude Work / Opus 5')" \
  'Commander' \
  bash -c "export CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=commander; cd $WORK_ROOT && claude --model opus --name commander"

start_agent_if_missing "$(pane_id_by_label "$CONTROL_WS" 'Sol - Codex Personal / GPT-5.6 Sol')" \
  'Sol' \
  bash -c "export AGMSG_AGENT=codex-sol; cd $WORK_ROOT && $CODEX_ACCOUNT_SCRIPT personal"

start_agent_if_missing "$(pane_id_by_label "$CONTROL_WS" 'Utility - Claude Personal')" \
  'Utility' \
  bash -c "unset CLAUDE_CONFIG_DIR; export AGMSG_AGENT=utility; cd $WORK_ROOT && claude --name utility"

# 旧 Status 枠（Shellのまま起動しなかった）を Codex 会社にする（2026-09-24）。
# AGMSG_AGENT は agmsg 登録済みの `codex`（旧 会社Codex）を使う。
start_agent_if_missing "$(pane_id_by_label "$CONTROL_WS" 'Codex Work - Main')" \
  'Codex Work - Main' \
  bash -c "export AGMSG_AGENT=codex; cd $WORK_ROOT && $CODEX_ACCOUNT_SCRIPT work"

# --- EXECUTION ---
start_agent_if_missing "$(pane_id_by_label "$EXECUTION_WS" 'Supervisor - Claude Work / Opus 5')" \
  'Supervisor' \
  bash -c "export CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=loop-supervisor; cd $WORK_ROOT && claude --model opus --name loop-supervisor"

if [ "$SKIP_REVIEW" = false ]; then
  start_agent_if_missing "$(pane_id_by_label "$EXECUTION_WS" 'Reviewer A - Claude Work / Opus 5')" \
    'Reviewer A' \
    bash -c "export CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=loop-review-a; cd $WORK_ROOT && claude --model opus --name loop-review-a"
fi

# Macでも既存のagyを使う。自動承認はONだが、既存の物理deny / guardrailは変更しない。
start_agent_if_missing "$(pane_id_by_label "$EXECUTION_WS" 'Worker A - Gemini 3.8 Flash')" \
  'Worker A - Gemini 3.8 Flash' \
  bash -c "export AGMSG_AGENT=loop-worker-gemini; cd $WORK_ROOT && agy --model gemini-3.8-flash-medium --mode accept-edits --dangerously-skip-permissions"

start_agent_if_missing "$(pane_id_by_label "$EXECUTION_WS" 'Worker B - Claude Work / Sonnet 5')" \
  'Worker B - Sonnet 5' \
  bash -c "export CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=loop-worker-sonnet; cd $WORK_ROOT && claude --model sonnet --name loop-worker-sonnet"

# --- EXTRA（--skip-extra で丸ごと省略できる）---
if [ "$SKIP_EXTRA" = false ]; then
  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Grok')" \
    'Grok' \
    bash -c "cd $WORK_ROOT && grok"

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Antigravity CLI')" \
    'Antigravity CLI' \
    bash -c "cd $WORK_ROOT && agy"

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Claude Work - Extra')" \
    'Claude Work - Extra' \
    bash -c "export CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=claude-extra; cd $WORK_ROOT && claude --model opus --name claude-extra"

  start_agent_if_missing "$(pane_id_by_label "$EXTRA_WS" 'Codex Work - Extra')" \
    'Codex Work - Extra' \
    bash -c "export AGMSG_AGENT=codex-extra; cd $WORK_ROOT && $CODEX_ACCOUNT_SCRIPT work"
fi

herdr workspace focus "$CONTROL_WS" >/dev/null 2>&1 || true

if [ "$CONFIGURE_ONLY" = false ]; then
  exec herdr
fi
