#!/bin/bash
# herdr-bootstrap.sh — Mac版 Herdr ブートストラップ
# WezTerm gui-startup からバックグラウンド実行される。
# 用法: herdr-bootstrap.sh [--configure-only]
#
# ===== 構成（2026-11-21 再編。Windows 版の 2026-11-17 再編に合わせた）=====
# 起動時に作るワークスペースは「デフォルト」1つ、4面だけ。
#   ┌──────────────────────────────┬──────────────────────────┐
#   │ おうち（個人Claude）           │ Sol（個人Codex）          │
#   ├──────────────────────────────┼──────────────────────────┤
#   │ T-SSS（会社Claude・メイン）    │ Codex Work - Main（会社） │
#   └──────────────────────────────┴──────────────────────────┘
#   Mac は自宅用なので、4面の中身は Windows と揃えていない（2026-11-01 の配置のまま）。
#     - 上段 = 個人、下段 = 会社（Windows は上段が会社）
#     - Windows の Utility を「おうち」、Commander を「T-SSS」と呼ぶ
#     - Windows 左下の「Claude Work - Extra」は置かず、Sol（個人Codex）を常駐させる
# 2026-11-21 に外したもの（必要になったら dotfiles の git 履歴から戻す）:
#   - Extra（Grok / Antigravity CLI / Claude Work - Extra / Codex Work - Extra）と 🛠 Work
#     … 使うときだけ F9 ランチャーから起動する
#   - 📮 受付 / 🦍 EXECUTION / 🐦 EXECUTION … Windows 側で🦍ループを外したため。
#     Mac は元々 Loop 制御をせず、枠とエージェントを作るだけだった
# herdr には並べ替えコマンドが無く、番号は作成順で決まる。

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
# 全CLIをカラー表示で起動する。古いサーバー環境も各起動時に上書きする。
unset NO_COLOR
export TERM=xterm-256color COLORTERM=truecolor FORCE_COLOR=3 CLICOLOR=1
unset _d

if ! command -v herdr >/dev/null 2>&1; then
  echo "Error: herdr が PATH 上に見つからない (PATH=$PATH)" >&2
  exit 1
fi

CONFIGURE_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --configure-only) CONFIGURE_ONLY=true ;;
    # 2026-11-21: 対象のワークスペース（Extra / EXECUTION）を廃止したため未使用。
    # 古い呼び出しが失敗しないよう、受け付けるだけにしている。
    --skip-extra|--skip-review) ;;
  esac
done

WORK_ROOT="$HOME/claude"
CODEX_ACCOUNT_SCRIPT="$HOME/dotfiles/wezterm/codex-account.sh"

WORKSPACE_PLAN=('デフォルト')

legacy_label_for() {
  case "$1" in
    'デフォルト')    echo 'CONTROL / ENTRY' ;;
  esac
}

# 廃止したワークスペース。既存セッションに残っていても、位置による採用・リネームの対象にしない
# （残っていた旧ワークスペースが「デフォルト」として転用されるのを防ぐ）。
# 旧ワークスペース自体はこのスクリプトでは閉じない。消すときは `herdr workspace close <id>` を使う。
RETIRED_WORKSPACE_LABELS=(
  'Extra' 'Extra Agents'
  '📮 受付' '🦍 受付'
  '🦍 EXECUTION' 'Review Agents'
  '🐦 EXECUTION' '🐦 EXECUTION 2'
  '🛠 Work'
)

# ---------- サーバー管理 ----------

test_server() {
  herdr status server 2>/dev/null | grep -qE '^status:[[:space:]]+running$'
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

retired_contains() {
  local needle="$1" item
  for item in "${RETIRED_WORKSPACE_LABELS[@]}"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# 計画順にワークスペースを解決する。
#   1. 同じラベルが既にあればそれを使う
#   2. その位置に「計画外かつ廃止済みでないラベル」のワークスペースがあれば採用してリネームする
#      （新規セッションの既定ワークスペースを w1 として拾うため）
#   3. どちらでもなければ新規作成する（既存セッションでは末尾に付く）
resolve_workspace() {
  local index="$1" label="$2" ws_id legacy_label legacy_id candidate_id candidate_label

  ws_id=$(ws_id_by_label "$label")
  if [ -n "$ws_id" ]; then
    echo "$ws_id"
    return
  fi

  # 旧役割名は位置ではなくラベルで移行する。
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
  if [ -n "$candidate_id" ] && ! plan_contains "$candidate_label" \
      && ! retired_contains "$candidate_label"; then
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
  herdr pane run "$pane_id" env -u NO_COLOR TERM=xterm-256color COLORTERM=truecolor FORCE_COLOR=3 CLICOLOR=1 "$@"
}

# ---------- メイン ----------

start_server

CONTROL_WS=$(resolve_workspace 0 'デフォルト')

# デフォルト: 4面（左上 → 右上 → 左下 → 右下 の順にラベルを付ける）。
# ラベルは、一方が他方の前方一致にならない名前にする（ペイン名で宛先を探す処理の取り違え防止）。
# 2026-11-01: Mac は自宅用なので上段 = 個人（おうち / Sol）、下段 = 会社（T-SSS / Codex Work - Main）。
init_pane_grid "$CONTROL_WS" 4
apply_pane_labels "$CONTROL_WS" \
  'おうち - Claude Personal' 'Sol - Codex Personal' \
  'T-SSS - Claude Work / Opus 5' 'Codex Work - Main'

LIVE_PANE_IDS=$(live_agent_pane_ids)

# Mac のプロファイル対応は Windows と逆:
#   個人 = 既定の ~/.claude / 会社 = ~/.claude-work
CLAUDE_WORK_DIR="$HOME/.claude-work"

# セッション名・AGMSG_AGENT は Mac 固有の t-sss / ouchi（Windows の commander / utility とは別物）。
start_agent_if_missing "$(pane_id_by_label "$CONTROL_WS" 'T-SSS - Claude Work / Opus 5')" \
  'T-SSS' \
  bash -c "unset NO_COLOR; export FORCE_COLOR=3 COLORTERM=truecolor CLAUDE_CONFIG_DIR=$CLAUDE_WORK_DIR AGMSG_AGENT=t-sss; cd $WORK_ROOT && claude --model opus --name t-sss"

start_agent_if_missing "$(pane_id_by_label "$CONTROL_WS" 'Sol - Codex Personal')" \
  'Sol' \
  bash -c "export AGMSG_AGENT=codex-sol; cd $WORK_ROOT && $CODEX_ACCOUNT_SCRIPT personal"

start_agent_if_missing "$(pane_id_by_label "$CONTROL_WS" 'おうち - Claude Personal')" \
  'おうち' \
  bash -c "unset NO_COLOR CLAUDE_CONFIG_DIR; export FORCE_COLOR=3 COLORTERM=truecolor AGMSG_AGENT=ouchi; cd $WORK_ROOT && claude --name ouchi"

# AGMSG_AGENT は agmsg 登録済みの `codex`（会社Codex）を使う。
start_agent_if_missing "$(pane_id_by_label "$CONTROL_WS" 'Codex Work - Main')" \
  'Codex Work - Main' \
  bash -c "export AGMSG_AGENT=codex; cd $WORK_ROOT && $CODEX_ACCOUNT_SCRIPT work"

herdr workspace focus "$CONTROL_WS" >/dev/null 2>&1 || true

if [ "$CONFIGURE_ONLY" = false ]; then
  exec herdr
fi
