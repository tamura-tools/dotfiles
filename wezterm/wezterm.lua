-- ===================================================================
-- 編集ルール (重要)
-- ===================================================================
-- 1. Palette の色指定は 6桁 RGB HEX (#RRGGBB) のみ対応。
--    8桁 RGBA HEX (#00FFFF33 等) は WezTerm がパースエラーになる。
-- 2. このファイルを壊すと WezTerm 自体が起動不能になる。
--    編集前に必ずファイル内容確認 + 構文チェックを行うこと。
-- ===================================================================

local wezterm = require 'wezterm'
local act = wezterm.action
local mux = wezterm.mux
local config = {}

-- OS判定
local is_windows = wezterm.target_triple:find('windows') ~= nil

-- Herdr はAIプロセスの実体を保持し、複数のWezTermウィンドウから同じ
-- defaultセッションへ接続する。PATHが古いWezTermでも動くよう実体を明示する。
local herdr_exe, herdr_bootstrap
if is_windows then
  herdr_exe = wezterm.home_dir .. '\\AppData\\Local\\Programs\\Herdr\\bin\\herdr.exe'
  herdr_bootstrap = wezterm.home_dir .. '\\dotfiles\\wezterm\\herdr-bootstrap.ps1'
else
  -- macOS: Dock/Finder から起動した WezTerm の PATH は /usr/bin:/bin:/usr/sbin:/sbin だけで、
  -- Homebrew の bin が入らない。gui-startup から呼ぶ子プロセスが `herdr` を解決できず
  -- ブートストラップが無言で落ちるため、実体パスを探して使う（2026-08-30）。
  herdr_exe = 'herdr'
  for _, candidate in ipairs {
    '/opt/homebrew/bin/herdr',                 -- Apple Silicon の Homebrew
    '/usr/local/bin/herdr',                    -- Intel の Homebrew
    wezterm.home_dir .. '/.local/bin/herdr',
  } do
    local f = io.open(candidate, 'r')
    if f then
      f:close()
      herdr_exe = candidate
      break
    end
  end
  herdr_bootstrap = wezterm.home_dir .. '/dotfiles/wezterm/herdr-bootstrap.sh'
end

-- macOS で WezTerm が直接起動する子プロセスに渡す PATH。
-- 非対話ログインシェルは ~/.zshrc を読まないため codex(.npm-global) や grok(.grok) が落ちる。
-- 対話 zsh と同じ並びをここで明示する。
local mac_path_prefix =
  'export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.grok/bin:'
  .. '/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:$PATH"; '

-- ローカルLLM(LM Studio)の起動コマンド生成。lms は %USERPROFILE%\.lmstudio\bin にあり、
-- PATHが古いセッションでも動くよう明示追加する。model は `lms ls --json` の modelKey。
-- ※ 2026-09-24: ローカルLLMは再構築予定のため F9 から外した（下の archived_launcher_apps を参照）。
--    再構築時の土台として関数は残している。
local function lms_chat(model)
  return '$env:PATH = "$HOME\\.lmstudio\\bin;$env:PATH"; lms chat ' .. model
end

-- ローカルLLMをエージェントとして使う（opencode + LM Studio のOpenAI互換サーバー）。
-- lms chat はファイル読み書きツールを持たないので、ファイルを触らせたいときはこちらを使う。
-- プロバイダ定義は ~/.config/opencode/opencode.json の provider.lmstudio 側にある。
-- ★ ここにモデルを追加したら opencode.json の provider.lmstudio.models にも同じ modelKey を
--    必ず登録する。未登録のまま --model で渡すと、警告なく既定モデル（"model" キーの
--    Nemotron）にフォールバックし、ランチャーがロードした側と食い違って無反応になる（2026-08-05 遭遇）。
-- コンテキスト長はJITロードだと 8192 に落ちて opencode のシステムプロンプトが溢れるため、
-- 毎回 unload → 明示ロードでコンテキストを確保する（9B級のロードで10秒前後）。
local function lms_agent(model, ctx)
  return '$env:PATH = "$HOME\\.lmstudio\\bin;$env:PATH"; lms server start; lms unload --all; '
    .. 'lms load ' .. model .. ' --context-length ' .. (ctx or 32768) .. ' --yes; '
    .. 'cd C:\\claude; opencode --model lmstudio/' .. model
end

-- ===== F9 ランチャー: アプリ定義 =====
-- 選んだアプリは「新しいタブ」で起動する（2026-09-24 変更）。
--   旧方式は現在ペインへ Ctrl+C x2 → コマンド入力だったが、現在ペインは Herdr の TUI で、
--   Herdr は Ctrl+C をフォーカス中のエージェントへそのまま渡すため、
--   Supervisor / Worker などの作業を中断させてしまう問題があった。
-- アプリを終了するとタブごと閉じる。cmd = '' は新しいタブで空のシェルを開く。
-- 並び順は Windows / Mac で揃える。Claude / Codex のアカウント指定は OS ごとに異なる（統一しない方針）。
local launcher_apps
if is_windows then
  launcher_apps = {
    -- Claude系はアカウント(CLAUDE_CONFIG_DIR)と作業ディレクトリを必ずセットで指定する。
    -- 個人=.claude-personal↔C:\claude / 会社=.claude↔C:\claude。
    { id = 'claude',     label = 'Claude Code',       cmd = 'cd C:\\claude; $env:CLAUDE_CONFIG_DIR = "$HOME\\.claude-personal"; claude' },
    { id = 'claude-work', label = 'Claude Code (会社)', cmd = 'cd C:\\claude; $env:CLAUDE_CONFIG_DIR = "$HOME\\.claude"; claude' },
    -- Codexはデスクトップ既定(~/.codex)と分離し、起動前にメールアドレスまで検証する。
    -- 会社=~/.codex-work / 個人=~/.codex-personal。誤アカウントではCodexを起動しない。
    { id = 'codex',      label = 'Codex CLI (会社 / Auto)', cmd = 'cd C:\\claude; & "$HOME\\dotfiles\\wezterm\\codex-account.ps1" -Account work --approve-for-me' },
    { id = 'codex-personal', label = 'Codex CLI (個人)', cmd = 'cd C:\\claude; & "$HOME\\dotfiles\\wezterm\\codex-account.ps1" -Account personal' },
    { id = 'gemini',     label = 'Gemini CLI',        cmd = 'cd C:\\claude; gemini' },
    -- Antigravity CLI は agy コマンド（%LOCALAPPDATA%\agy\bin）。PATHが古いセッションでも動くよう明示追加
    -- 2026-08-17: 会社アカウント一本化。agy のログイン情報は Windows 資格情報マネージャー（keyring）の
    --   1枠に保存され、USERPROFILE/HOME を差し替えても同じアカウントで認証される（実機確認）。
    --   Codex のような個人/会社の同時併用はできないため、エントリは会社用の1本だけにする。
    { id = 'antigravity', label = 'Antigravity CLI (会社 / Auto)', cmd = '$env:PATH = "$env:LOCALAPPDATA\\agy\\bin;$env:PATH"; cd C:\\claude; agy --mode accept-edits --dangerously-skip-permissions' },
    { id = 'grok',       label = 'Grok Build',         cmd = 'cd C:\\claude; grok' },
    { id = 'lazygit',    label = 'lazygit',           cmd = 'cd $HOME\\dotfiles; lazygit' },
    { id = 'yazi',       label = 'yazi',              cmd = 'yazi' },
    { id = 'dashboard',  label = 'Todoist',            cmd = '& $HOME\\dotfiles\\wezterm\\todoist.ps1' },
    { id = 'calendar',   label = '📅 カレンダー',        cmd = '& $HOME\\dotfiles\\wezterm\\calendar.ps1' },
    { id = 'shell',      label = 'PowerShell',        cmd = '' },
  }
else
  launcher_apps = {
    -- 個人=既定の ~/.claude / 会社=~/.claude-work（Windows とは対応が逆。統一しない方針）
    { id = 'claude',     label = 'Claude Code',       cmd = 'unset CLAUDE_CONFIG_DIR; claude' },
    { id = 'claude-work', label = 'Claude Code (会社)', cmd = 'CLAUDE_CONFIG_DIR=~/.claude-work claude --model opus' },
    -- Codex は herdr-bootstrap.sh と同じ codex-account.sh で会社/個人を切り替える。
    -- 会社=~/.codex-work / 個人=既定の ~/.codex（2026-09-24 実機確認）
    { id = 'codex',      label = 'Codex CLI (会社)',   cmd = 'cd ~/claude && ~/dotfiles/wezterm/codex-account.sh work' },
    { id = 'codex-personal', label = 'Codex CLI (個人)', cmd = 'cd ~/claude && ~/dotfiles/wezterm/codex-account.sh personal' },
    { id = 'gemini',     label = 'Gemini CLI',        cmd = 'cd ~/claude && gemini' },
    -- agy は ~/.local/bin/agy（2026-09-24 実機確認: v1.2.2、ログイン済み）
    { id = 'antigravity', label = 'Antigravity CLI (Auto)', cmd = 'cd ~/claude && agy --mode accept-edits --dangerously-skip-permissions' },
    { id = 'grok',       label = 'Grok Build',         cmd = 'cd ~/claude && grok' },
    { id = 'lazygit',    label = 'lazygit',           cmd = 'cd ~/dotfiles && lazygit' },
    { id = 'yazi',       label = 'yazi',              cmd = 'yazi' },
    { id = 'dashboard',  label = 'Todoist',            cmd = 'bash ~/dotfiles/wezterm/todoist.sh' },
    { id = 'calendar',   label = '📅 カレンダー',        cmd = 'bash ~/dotfiles/wezterm/calendar.sh' },
    { id = 'shell',      label = 'Shell',             cmd = '' },
  }
end

-- ===== F9 から外した項目（退避リスト） =====
-- このテーブルはどこからも参照していない（メニューには表示されない）。
-- 戻すときは、該当行を上の launcher_apps へ移すだけでよい。
-- 各行の archived は退避日、reason は退避理由。
local archived_launcher_apps = {
  -- ▼ Windows
  -- 旧世代モデルを明示指定して起動する枠（既定の opus は最新世代に追随するため別枠にしていた）。
  { os = 'windows', archived = '2026-09-24', reason = 'Opus 4.6 指定はもう使わない',
    id = 'claude-opus46', label = 'Claude Code (Opus 4.6)', cmd = 'cd C:\\claude; $env:CLAUDE_CONFIG_DIR = "$HOME\\.claude-personal"; claude --model claude-opus-4-6' },
  { os = 'windows', archived = '2026-09-24', reason = '未使用',
    id = 'claude-clean', label = 'Claude Code (Clean)', cmd = 'cd C:\\claude; $env:CLAUDE_CONFIG_DIR = "$HOME\\.claude-clean"; claude --model opus --tools default --disable-slash-commands --strict-mcp-config --setting-sources user' },
  { os = 'windows', archived = '2026-09-24', reason = '未使用',
    id = 'claude-work-clean', label = 'Claude Code (会社 Clean)', cmd = 'cd C:\\claude; $env:CLAUDE_CONFIG_DIR = "$HOME\\.claude-work-clean"; claude --model opus --tools default --disable-slash-commands --strict-mcp-config --setting-sources user' },
  -- AI委譲キューはペイン注入ではなく、必要時だけ会社Claudeを非対話起動する。WezTerm常駐には依存しない。
  { os = 'windows', archived = '2026-09-24', reason = '未使用',
    id = 'delegate-queue', label = '📨 AI委譲キュー', cmd = 'cd C:\\claude; ai-delegate watch' },
  -- agmsg 本体はエージェント間連絡で使われている（bootstrap が AGMSG_AGENT を設定）。退避したのは閲覧用の表示画面だけ。
  { os = 'windows', archived = '2026-09-24', reason = '閲覧画面は未使用（agmsg 本体は稼働中）',
    id = 'agmsg-watch', label = '📨 agmsg 未ack一覧', cmd = 'cd C:\\claude; agmsg watch' },
  { os = 'windows', archived = '2026-09-24', reason = 'ほぼ未使用',
    id = 'fugu', label = '🐟 Sakana Fugu', cmd = '$env:CODEX_HOME = "$HOME\\.codex-personal"; cd C:\\claude; doppler run --project sakana-ai --config prd -- codex-fugu' },
  { os = 'windows', archived = '2026-09-24', reason = 'ほぼ未使用',
    id = 'fugu-ultra', label = '🐡 Sakana Fugu Ultra', cmd = '$env:CODEX_HOME = "$HOME\\.codex-personal"; cd C:\\claude; doppler run --project sakana-ai --config prd -- codex-fugu-ultra' },
  -- ローカルLLM (LM Studio) の素のチャット。初回は選択モデルのメモリ読込に時間がかかる（9B級で1分前後、35B-A3Bは更に重い）。
  -- ※ こちらはファイルを読めない（lms chat にツール実行の仕組みがない）。ファイル操作は opencode 側を使う。
  -- modelKey は `lms ls --json` 準拠（2026-08-07 時点: Nemotron / Gemma / Qwen3.6-35B-A3B / LFM）。
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち',
    id = 'lms-nemotron', label = '🤖 LLM: Nemotron 9B (壁打ち・日本語)', cmd = lms_chat('nvidia-nemotron-nano-9b-v2-japanese') },
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち',
    id = 'lms-gemma', label = '🤖 LLM: Gemma 4 E4B (画像可)', cmd = lms_chat('google/gemma-4-e4b') },
  -- Qwen3.6 35B-A3B (Q4_K_M / ~22GB / MoE active~3B)。ローカルコーダー枠。
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち',
    id = 'lms-qwen', label = '🤖 LLM: Qwen3.6 35B-A3B (コーダー)', cmd = lms_chat('qwen/qwen3.6-35b-a3b') },
  -- LFM2.5 2.6B (LiquidAI, Q5_K_M / 1.94GB / 最大128kコンテキスト)。軽作業・高速。
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち',
    id = 'lms-lfm', label = '🤖 LLM: LFM2.5 2.6B (軽作業・高速)', cmd = lms_chat('lfm2.5-2.6b') },
  -- ローカルLLMエージェント（opencode 経由。ファイル読み書き・編集まで可能）。cwd=C:\claude。
  -- opencode.json の provider.lmstudio.models と modelKey を揃えること。
  -- LFM2.5 は tool use 学習済みで、LM Studio の OpenAI 互換APIに read_file 定義を渡すと
  -- 正しく tool_calls を返すことを確認済み（2026-08-05 検証。ロードも約6秒と速い）。
  -- Qwen3.6-35B-A3B は ~22GB のため agent 起動時の load が重い。context は他と同じ 32k 既定。
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち',
    id = 'oc-nemotron', label = '🛠 LLM Agent: Nemotron 9B (壁打ち・ファイル可)', cmd = lms_agent('nvidia-nemotron-nano-9b-v2-japanese') },
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち',
    id = 'oc-gemma', label = '🛠 LLM Agent: Gemma 4 E4B (画像・ファイル可)', cmd = lms_agent('google/gemma-4-e4b') },
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち',
    id = 'oc-qwen', label = '🛠 LLM Agent: Qwen3.6 35B-A3B (コーダー・ファイル可)', cmd = lms_agent('qwen/qwen3.6-35b-a3b') },
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち',
    id = 'oc-lfm', label = '🛠 LLM Agent: LFM2.5 2.6B (軽作業・高速)', cmd = lms_agent('lfm2.5-2.6b') },
  -- Hermes Agent + Wiki プリフェッチ（llm-wiki＋AI作業ログの参照）。推論はLM StudioのLFM2.5のみで課金ゼロ。
  -- hermes.exe は venv 内にありPATH未登録のためフルパスで呼ぶ。設定は %LOCALAPPDATA%\hermes\config.yaml。
  -- 2026-08-12: ローカルLLMのツール往復は遅すぎ（9Bで1問4〜10分）かつ小型モデルはツール選択を誤るため、プリフェッチ方式に変更。
  --   起動時に prefetch_wiki.py が Wiki索引＋直近7日のAI作業ログを wiki-session/AGENTS.md に書き出し、
  --   Hermes が cwd の AGENTS.md として自動注入する。モデルはツールなし（-t none の警告は無害）＋思考オフで応答。
  --   ツール不要になったため高速なLFM2.5を採用（実測96秒/問。Nemotron 9Bは同条件で4〜7分）。
  --   Hermes は最低 64K コンテキストを要求するため --context-length 65536 を維持すること。
  { os = 'windows', archived = '2026-09-24', reason = 'ローカルLLM再構築待ち（LM Studio 依存）',
    id = 'hermes', label = '🪽 Hermes Agent (Wiki・作業ログ参照)', cmd = '$env:PATH = "$HOME\\.lmstudio\\bin;$env:PATH"; lms server start; lms unload --all; '
      .. 'lms load lfm2.5-2.6b --context-length 65536 --ttl 1800 --yes; '
      .. '& "$env:LOCALAPPDATA\\Programs\\Python\\Python313\\python.exe" C:\\claude\\hermes\\prefetch_wiki.py; cd C:\\claude\\hermes\\wiki-session; '
      .. '& "$env:LOCALAPPDATA\\hermes\\hermes-agent\\venv\\Scripts\\hermes.exe" chat --provider lmstudio --model lfm2.5-2.6b --toolsets none --reasoning none' },
  -- ▼ Mac
  { os = 'mac', archived = '2026-09-24', reason = '未使用',
    id = 'claude-clean', label = 'Claude Code (Clean)', cmd = 'CLAUDE_CONFIG_DIR=~/.claude-clean claude --model opus --tools default --disable-slash-commands --strict-mcp-config --setting-sources user' },
  { os = 'mac', archived = '2026-09-24', reason = '未使用',
    id = 'claude-work-clean', label = 'Claude Code (会社 Clean)', cmd = 'CLAUDE_CONFIG_DIR=~/.claude-work-clean claude --model opus --tools default --disable-slash-commands --strict-mcp-config --setting-sources user' },
  -- 旧 Mac の Codex は素の `codex`（アカウント分離なし）だった。2026-09-24 に codex-account.sh 経由へ変更。
  { os = 'mac', archived = '2026-09-24', reason = '会社/個人の2項目に置き換え',
    id = 'codex-plain', label = 'Codex CLI', cmd = 'cd ~/claude && codex' },
}

-- InputSelector用のchoicesを構築
local launcher_choices = {}
for _, app in ipairs(launcher_apps) do
  table.insert(launcher_choices, { id = app.id, label = app.label })
end

-- IDからコマンドを引くテーブル
local launcher_cmds = {}
for _, app in ipairs(launcher_apps) do
  launcher_cmds[app.id] = app.cmd
end

-- 新しいタブでコマンドを起動するアクションを作る（F9 と直接キーの両方から使う）。
-- Windows: powershell -Command（プロファイルは読む＝従来の対話シェルと同じ環境）。終了でタブも閉じる。
-- Mac: zsh -lic（ログイン＋対話で ~/.zshrc を読む＝従来の対話シェルと同じ PATH）。終了でタブも閉じる。
local launcher_cwd = is_windows and 'C:\\claude' or (wezterm.home_dir .. '/claude')
local function spawn_in_new_tab(cmd)
  if not cmd or cmd == '' then
    return act.SpawnCommandInNewTab { cwd = launcher_cwd }
  end
  local args
  if is_windows then
    args = { 'powershell.exe', '-NoLogo', '-Command', cmd }
  else
    args = { '/bin/zsh', '-lic', cmd }
  end
  return act.SpawnCommandInNewTab { args = args, cwd = launcher_cwd }
end

-- ===== レイアウト（2026-09-24 更新: WezTerm は Herdr を表示する箱＋作業用タブ） =====
-- 起動直後は分割せず、唯一のペインで Herdr 本体(TUI)を全画面起動する（1枚目のタブ）。
-- レイアウトもワークスペース切替も Herdr 自身が持つ（サイドバーの spaces をクリック、または Ctrl+Shift+1〜4）。
-- 自分の作業用アプリは F9 で「新しいタブ」に開く。Herdr のタブには何も送らない。
-- ┌──────────┬──────────────────────────────────────────┐
-- │ spaces   │  フォーカス中ワークスペースのエージェント群 │
-- │ デフォルト│  （Herdr が 2x2 等に自動レイアウト）        │
-- │ Extra    │                                          │
-- │ 🦍 EXEC  │  切り替えはサイドバーの spaces をクリック    │
-- │ 🦍 受付  │                                          │
-- └──────────┴──────────────────────────────────────────┘
--   起動時に herdr-bootstrap（-ConfigureOnly / --configure-only）をバックグラウンドで走らせ、
--   サーバー起動→ワークスペース/ペイン構成→エージェント起動まで行う。
--   その完了をペイン側で待ってから herdr TUI クライアントを起動する。
--   Herdrのワークスペース（herdr-bootstrap が構築。Windows / Mac 共通の並び）:
--     w1 デフォルト    : Commander / Sol / Utility / Codex Work - Main（2x2）
--     w2 Extra         : Grok / Antigravity CLI / Claude Work - Extra / Codex Work - Extra（2x2）
--     w3 🦍 EXECUTION  : Supervisor / Reviewer A / Worker A / Worker B（2x2）
--     w4 🦍 受付       : Loop Inbox Receiver（Windows）/ 空き枠（Mac。受付の仕組みは Portable Gorilla 側で検討）
--   ※ w3 のラベル「🦍 EXECUTION」と4役の同居は変更しないこと。
--      loop-inbox/loop_reset_execution.py がこのラベル1つで4役をまとめて探している（2026-09-24 調査）。
--      制御と実行の分離、Worker 追加（w5 以降に置く想定）は🦍ループ本体の別課題。
--   ※ Codex 会社の2枠は「- Main」「- Extra」と先頭が一致しない名前にする
--      （ループの宛先探しがペイン名の前方一致のため、取り違え防止）。
--   ※ Local LLM ワークスペースは 2026-09-24 に廃止（再構築予定）。
--   ※ 相談窓口は Commander。実行は Task Packet を pending へ投入して Supervisor に渡す。
--      Supervisorへ直接相談せず、Supervisor自身も成果物を作らない。
--   ※ Extra を常駐させたくないときは herdr-bootstrap に --skip-extra / -SkipExtra を渡す。
--      Reviewer A を常駐させたくないときは --skip-review / -SkipReview を渡す。
--   ※ ワークスペース番号は herdr の作成順で決まる（並べ替えコマンドが無い）。
--      既存セッションへ後から追加すると末尾に付くため、番号どおりに
--      並べたい場合は herdr server を作り直してから bootstrap を走らせる。
wezterm.on('gui-startup', function(cmd)
  -- Herdrブートストラップ(ConfigureOnly)をバックグラウンドで実行。
  -- 無言で落ちると原因を追えないため、出力は必ずログへ落とす。
  if not cmd then
    if is_windows then
      local log = wezterm.home_dir .. '\\AppData\\Local\\herdr\\bootstrap.log'
      wezterm.background_child_process {
        'powershell.exe', '-ExecutionPolicy', 'Bypass',
        '-Command',
        '& "' .. herdr_bootstrap .. '" -ConfigureOnly *> "' .. log .. '"',
      }
    else
      local log = wezterm.home_dir .. '/.config/herdr/bootstrap.log'
      wezterm.background_child_process {
        '/bin/bash', '-c',
        mac_path_prefix .. 'exec "' .. herdr_bootstrap .. '" --configure-only >"' .. log .. '" 2>&1',
      }
    end
  end

  local tab, pane, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()

  -- 分割しない。ブートストラップでサーバーが上がるのを待ってから Herdr 本体(TUI)を起動。
  if is_windows then
    -- 前回終了時の client socket が残っていても、今回生成された API socket より新しくなるまで待つ。
    pane:send_text('$api = "$env:APPDATA/herdr/herdr.sock"; $client = "$env:APPDATA/herdr/herdr-client.sock"; foreach ($i in 1..120) { $s = (& "' .. herdr_exe .. '" status server 2>$null | Out-String); if ($LASTEXITCODE -eq 0 -and $s -match "status: +running" -and (Test-Path $api) -and (Test-Path $client) -and (Get-Item $client).LastWriteTimeUtc -ge (Get-Item $api).LastWriteTimeUtc) { break }; Start-Sleep -Milliseconds 500 }; & "' .. herdr_exe .. '"\r\n')
  else
    pane:send_text('for _ in $(seq 1 120); do "' .. herdr_exe .. '" status server 2>/dev/null | grep -qE "status:[[:space:]]+running" && break; sleep 0.5; done; exec "' .. herdr_exe .. '"\r')
  end
end)

-- カスタムカラースキーム
config.color_schemes = {
  ['SF Terminal'] = {
    foreground = '#B0E0E6',       -- 淡いシアン（メインテキスト）
    background = '#0A0A12',       -- ほぼ黒（透過で見えなくなる）
    cursor_bg = '#00FFFF',        -- シアン発光カーソル
    cursor_fg = '#0A0A12',
    selection_bg = '#00FFFF',   -- シアンセレクション
    selection_fg = '#FFFFFF',
    ansi = {
      '#1A1A2E',  -- black: 深い紺
      '#FF3366',  -- red: ネオンピンク
      '#00FF88',  -- green: ネオングリーン
      '#FFAA00',  -- yellow: アンバー警告色
      '#00BBFF',  -- blue: スカイブルー
      '#CC44FF',  -- magenta: ネオンパープル
      '#00FFCC',  -- cyan: アクアグリーン
      '#8899AA',  -- white: スチールグレー
    },
    brights = {
      '#334455',  -- bright black: ダークスチール
      '#FF6699',  -- bright red: ホットピンク
      '#33FFAA',  -- bright green: ミントグロー
      '#FFCC33',  -- bright yellow: ゴールド
      '#33DDFF',  -- bright blue: エレクトリックブルー
      '#DD77FF',  -- bright magenta: ラベンダーグロー
      '#33FFDD',  -- bright cyan: ブライトアクア
      '#DDEEFF',  -- bright white: アイスホワイト
    },
  },
  ['Neuromancer'] = {
    foreground = '#00FF9C',       -- 毒々しいターミナルグリーン
    background = '#080814',       -- 漆黒の紺（壁紙と合う）
    cursor_bg = '#FF0055',        -- ネオンピンクカーソル（目立つ）
    cursor_fg = '#080814',
    selection_bg = '#BF00FF',     -- パープルセレクション
    selection_fg = '#FFFFFF',
    ansi = {
      '#12122A',  -- black: 深淵
      '#FF0055',  -- red: ネオンクリムゾン
      '#39FF14',  -- green: 放射性グリーン
      '#FF6600',  -- yellow: 警告オレンジ
      '#0088FF',  -- blue: エレクトリックブルー
      '#BF00FF',  -- magenta: サイバーパープル
      '#00FFD0',  -- cyan: ターコイズグロー
      '#708090',  -- white: スレートグレー
    },
    brights = {
      '#2A2A4A',  -- bright black: ミッドナイト
      '#FF3377',  -- bright red: ホットマゼンタ
      '#7CFF4B',  -- bright green: アシッドグリーン
      '#FFAA00',  -- bright yellow: アンバーグロー
      '#33BBFF',  -- bright blue: スカイネオン
      '#DD44FF',  -- bright magenta: UVパープル
      '#00FFEE',  -- bright cyan: プラズマシアン
      '#C0D0E0',  -- bright white: クロームシルバー
    },
  },
  ['Holo HUD'] = {
    foreground = '#BEEFFF',       -- ホログラム投影光（淡いアイスシアン）
    background = '#020814',       -- 深宇宙ネイビー（スケスケで背景透過推奨）
    cursor_bg = '#00E5FF',        -- ピュアシアンのHUDカーソル
    cursor_fg = '#020814',
    selection_bg = '#0D7FB8',     -- エレクトリックブルー選択
    selection_fg = '#EAF8FF',
    ansi = {
      '#0A1628',  -- black: HUDフレーム深部
      '#FF2D5F',  -- red: アラートレッド（警告ピクト）
      '#00E5A0',  -- green: ステータスOKグロー
      '#FFB84D',  -- yellow: 注意アンバー（HUD警告色）
      '#00AEEF',  -- blue: エレクトリックシアンブルー
      '#7B68EE',  -- magenta: ホログラムバイオレット
      '#00E5FF',  -- cyan: 主力のピュアシアン
      '#C5E8F5',  -- white: スクリーン反射光
    },
    brights = {
      '#1E3A5F',  -- bright black: 艦橋スチールブルー
      '#FF4D7A',  -- bright red: ホットピンク警報
      '#5CFFCC',  -- bright green: ミントグロー
      '#FFDB5C',  -- bright yellow: ゴールド
      '#33D1FF',  -- bright blue: スカイネオンシアン
      '#A594F9',  -- bright magenta: ラベンダーオーラ
      '#66F5FF',  -- bright cyan: プラズマシアン
      '#EAF8FF',  -- bright white: ホログラムホワイト
    },
  },
  ['Claude Light'] = {
    -- claude.ai の実UIに合わせたパレット
    foreground = '#3D3D3A',       -- Claude 本文テキスト（暖かいダーク）
    background = '#FAF9F5',       -- Claude アイボリー（メイン背景）
    cursor_bg = '#D97757',        -- Claude サンセットコーラル（ブランドオレンジ）
    cursor_fg = '#FAF9F5',
    selection_bg = '#E8E5DC',     -- パネル色相当
    selection_fg = '#1F1E1D',
    ansi = {
      '#1F1E1D',  -- black: Claude ニアブラック
      '#C73E3E',  -- red: 落ち着いた朱
      '#6B8E4E',  -- green: セージ
      '#B5873A',  -- yellow: 温かみのあるオーカー
      '#5B7A9E',  -- blue: muted スレートブルー
      '#9B5E8B',  -- magenta: 控えめプラム
      '#3B8580',  -- cyan: muted ティール
      '#5C5A52',  -- white: 読めるウォームグレー（背景と被らない）
    },
    brights = {
      '#87847C',  -- bright black: ミッドグレー
      '#D97757',  -- bright red: Claude サンセットコーラル
      '#7FA85E',  -- bright green
      '#C9974A',  -- bright yellow
      '#6090B8',  -- bright blue
      '#B070A0',  -- bright magenta
      '#5BA29B',  -- bright cyan
      '#1F1E1D',  -- bright white: 最もコントラスト強い色（アイボリー上で可読）
    },
  },
}

config.color_scheme = 'Tokyo Night'
-- ===== 作業場ダーク =====
-- WezTerm はペイン境界の太さを変更できないため、高コントラストの境界色と
-- 非アクティブペインの減光を組み合わせて、仕切りを太く見せる。
config.colors = {
  split = '#7AA2F7',
  cursor_bg = '#00F5FF',
  cursor_fg = '#07111A',
  cursor_border = '#B8FBFF',
  compose_cursor = '#FFB84D',
}
config.inactive_pane_hsb = {
  saturation = 0.70,
  brightness = 0.58,
}
-- アクティブペインだけに現れるカーソルを、入力位置の発光インジケーターとして使う。
config.default_cursor_style = 'BlinkingBlock'
config.cursor_blink_rate = 600
config.cursor_blink_ease_in = 'Constant'
config.cursor_blink_ease_out = 'Constant'
config.animation_fps = 10
config.automatically_reload_config = true
-- 2026-06-22: Grok Build の TUI（旧 WezTerm 分割構成の④ペイン）が背景色でセルを塗りつぶし、壁紙が透けなかったため導入。
-- 現在は Herdr TUI 全体の見た目にも効いている（値の見直しは壁紙の整理時に判断する）。
-- WezTerm はペイン個別の透過を持たないので、色付きセル背景の不透明度を全体で下げて透かす。
-- 副作用: 全ペインの選択範囲/シンタックス・差分ハイライト等の色付き背景も薄くなる（既定背景の通常テキストは無変化）。
config.text_background_opacity = 0.3
config.font = wezterm.font('UDEV Gothic NF')
config.font_size = 12
config.initial_cols = 200
config.initial_rows = 50

-- 壁紙ファイル/ディレクトリ定義 (OS別)
-- Mac は wallpapers/mac/ サブフォルダを使う（Win 側との分離・永続化対象）
local wallpaper_file
local wallpaper_dir
if is_windows then
  wallpaper_file = wezterm.home_dir .. '/dotfiles/wezterm/wallpapers/workshop-brutalist-4k.png'
  wallpaper_dir = wezterm.home_dir .. '\\dotfiles\\wezterm\\wallpapers\\'
else
  -- 既定の壁紙は Windows と同じもの（wallpapers/ 直下の共有ファイルを参照する）。
  -- 差し替え候補の一覧（Cmd+Shift+I）は従来どおり wallpapers/mac/ を見る。
  wallpaper_file = wezterm.home_dir .. '/dotfiles/wezterm/wallpapers/workshop-brutalist-4k.png'
  wallpaper_dir = wezterm.home_dir .. '/dotfiles/wezterm/wallpapers/mac/'
end

-- 壁紙状態の永続化 (Macのみ運用)
-- 状態ファイル: ~/.config/wezterm/wallpaper_state
-- 内容: 1行に壁紙パス、または '_none' = 壁紙なし、未存在/空 = デフォルトにフォールバック
local wallpaper_state_path = wezterm.config_dir .. '/wallpaper_state'

local function read_wallpaper_state()
  local f = io.open(wallpaper_state_path, 'r')
  if not f then return nil end
  local line = f:read('*l')
  f:close()
  if not line or line == '' then return nil end
  if line ~= '_none' then
    -- 保存された壁紙ファイルが削除済みならデフォルトにフォールバック
    local img = io.open(line, 'r')
    if not img then return nil end
    img:close()
  end
  return line
end

local function write_wallpaper_state(path)
  local f = io.open(wallpaper_state_path, 'w')
  if not f then return end
  f:write(path or '')
  f:close()
end

-- OS別設定
if is_windows then
  config.default_prog = { 'powershell.exe' }
  config.default_cwd = 'C:/claude'
  config.background = {
    {
      source = { File = wallpaper_file },
      -- 元画像を暗色に調整済みなので、質感が残る程度の明るさにする。
      hsb = { brightness = 0.45 },
      opacity = 0.9,
      horizontal_align = 'Center',
      vertical_align = 'Middle',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
    },
  }
else
  config.default_cwd = wezterm.home_dir .. '/claude'
  -- 状態ファイルから前回の壁紙を復元（無ければ wallpaper_file がデフォルト）
  local saved_wp = read_wallpaper_state()
  if saved_wp == '_none' then
    config.background = {}
  else
    config.background = {
      {
        source = { File = saved_wp or wallpaper_file },
        -- 元画像を暗色に調整済みなので、質感が残る程度の明るさにする（Windows と同値）。
        hsb = { brightness = 0.45 },
        opacity = 0.9,
        horizontal_align = 'Center',
        vertical_align = 'Middle',
        repeat_x = 'NoRepeat',
        repeat_y = 'NoRepeat',
      },
    }
  end
end

-- モデル指定解除
local env_vars = {
  ANTHROPIC_MODEL = '',
}
if is_windows then
  -- Codex は standalone 実体 (~\.codex\packages\standalone\current\bin) から起動しないと
  -- 補助EXE (codex-resources\codex-windows-sandbox-setup.exe) を絶対パスで解決できない。
  -- ユーザーPATH先頭にも同エントリを追加済み (2026-07-13) だが、WezTerm が起動時の
  -- 古いPATHを保持したまま新ペインを開くケースに備えて設定側でも先頭に付ける。
  local codex_bin = (os.getenv('USERPROFILE') or '') .. '\\.codex\\packages\\standalone\\current\\bin'
  local cur_path = os.getenv('PATH') or ''
  if not cur_path:find(codex_bin, 1, true) then
    env_vars.PATH = codex_bin .. ';' .. cur_path
  end
end
config.set_environment_variables = env_vars

-- ===== プロファイル =====
-- テーマ + 壁紙 + 明るさをセットで切り替え
-- 用途: 個人/会社アカウントの視覚的な区別
local profiles = {
  {
    id = 'workshop',
    label = '🧱 作業場 — Tokyo Night + Brutalist 4K',
    color_scheme = 'Tokyo Night',
    wallpaper = 'workshop-brutalist-4k.png',
    brightness = 0.45,
    window_background_opacity = nil,
  },
  {
    id = 'personal',
    label = '🏠 個人用 — Tokyo Night + 従来の壁紙',
    color_scheme = 'Tokyo Night',
    wallpaper = 'legacy',       -- 変更前の壁紙を残す
    brightness = 0.1,
    window_background_opacity = nil,  -- デフォルト
  },
  {
    id = 'work',
    label = '🏢 会社用 — Claude Light (壁紙なし)',
    color_scheme = 'Claude Light',
    wallpaper = false,          -- 壁紙なし
    brightness = nil,
    window_background_opacity = 1.0,  -- 完全不透明
  },
  {
    id = 'work-dark',
    label = '🏢 会社用(Dark) — Catppuccin + 海',
    color_scheme = 'Catppuccin Mocha',
    wallpaper = 'sea001.jpg',   -- wallpapers/ 内のファイル名
    brightness = 0.07,
    window_background_opacity = nil,
  },
  {
    id = 'sf-terminal',
    label = '🛸 SF Terminal — スケスケHUD',
    color_scheme = 'SF Terminal',
    wallpaper = false,
    brightness = nil,
    window_background_opacity = 0.55,  -- デスクトップが透けて見える
  },
  {
    id = 'neuromancer',
    label = '💀 Neuromancer — サイバーパンク',
    color_scheme = 'Neuromancer',
    wallpaper = 'cyberpunk_matrix.png',
    brightness = 0.12,
    window_background_opacity = nil,
  },
  {
    id = 'holo-hud',
    label = '🛰 Holo HUD — ホログラム司令艦橋',
    color_scheme = 'Holo HUD',
    wallpaper = false,
    brightness = nil,
    window_background_opacity = 0.55,  -- スケスケ（HUDが宙に浮く感じ）
  },
}

-- プロファイルの壁紙パスを解決
local function resolve_wallpaper(profile)
  if profile.wallpaper == true then
    return wallpaper_file
  elseif profile.wallpaper == 'legacy' then
    if is_windows then
      return wezterm.home_dir .. '/dotfiles/wezterm/wallpaper_win.jpg'
    end
    return wezterm.home_dir .. '/dotfiles/wezterm/wallpaper.jpg'
  elseif profile.wallpaper and profile.wallpaper ~= false then
    if is_windows then
      return wezterm.home_dir .. '\\dotfiles\\wezterm\\wallpapers\\' .. profile.wallpaper
    end
    -- Mac は wallpapers/mac/ を優先し、無ければ Windows と共有の wallpapers/ を見る。
    -- （workshop-brutalist-4k.png のように mac/ に複製していないファイルがあるため）
    local mac_path = wezterm.home_dir .. '/dotfiles/wezterm/wallpapers/mac/' .. profile.wallpaper
    local f = io.open(mac_path, 'r')
    if f then
      f:close()
      return mac_path
    end
    return wezterm.home_dir .. '/dotfiles/wezterm/wallpapers/' .. profile.wallpaper
  end
  return nil  -- 壁紙なし
end

-- プロファイルをconfig overridesに適用
local function apply_profile(win, profile)
  local o = win:get_config_overrides() or {}
  o.color_scheme = profile.color_scheme

  local wp = resolve_wallpaper(profile)
  if wp then
    o.background = { {
      source = { File = wp },
      hsb = { brightness = profile.brightness or 0.1 },
      opacity = 0.9,
      horizontal_align = 'Center',
      vertical_align = 'Middle',
      repeat_x = 'NoRepeat',
      repeat_y = 'NoRepeat',
    } }
  else
    o.background = {}
  end

  o.window_background_opacity = profile.window_background_opacity
  win:set_config_overrides(o)
end

-- ===== 一時的な外観変更（セッション限り、再起動で元に戻る） =====
-- ライトテーマ別設定 { brightness, opacity }
-- brightness: 壁紙を白く飛ばす (1.0超え可)
-- opacity: テーマ背景の不透明度 (高い=テーマ色優先、壁紙はうっすら)
local light_default = { brightness = 2.0, opacity = 0.92 }
local light_themes = {
  ['Claude Light']             = light_default,
  ['Tokyo Night Day']         = light_default,
  ['Catppuccin Latte']        = light_default,
  ['Gruvbox Light (Gogh)']    = light_default,
  ['One Half Light (Gogh)']   = light_default,
  ['Solarized Light (Gogh)']  = light_default,
  ['rose-pine-dawn']          = light_default,
  ['Everforest Light (Gogh)'] = light_default,
  ['Ayu Light (Gogh)']        = light_default,
  ['dayfox']                  = light_default,
  ['dawnfox']                 = light_default,
}

local color_schemes = {
  -- Dark
  'Tokyo Night',
  'Tokyo Night Storm',
  'Catppuccin Mocha',
  'Catppuccin Macchiato',
  'Dracula (Gogh)',
  'Gruvbox Dark (Gogh)',
  'Nord',
  'One Half Dark (Gogh)',
  'Solarized Dark (Gogh)',
  'Kanagawa (Gogh)',
  'rose-pine',
  'Everforest Dark (Gogh)',
  'Ayu Dark (Gogh)',
  'nightfox',
  -- SF / Cyberpunk
  'SF Terminal',
  'Neuromancer',
  'Holo HUD',
  -- Light
  'Claude Light',
  'Tokyo Night Day',
  'Catppuccin Latte',
  'Gruvbox Light (Gogh)',
  'One Half Light (Gogh)',
  'Solarized Light (Gogh)',
  'rose-pine-dawn',
  'Everforest Light (Gogh)',
  'Ayu Light (Gogh)',
  'dayfox',
  'dawnfox',
}

local theme_choices = {}
for _, scheme in ipairs(color_schemes) do
  local mark = ''
  if scheme == config.color_scheme then mark = ' (current)' end
  table.insert(theme_choices, { id = scheme, label = scheme .. mark })
end
table.insert(theme_choices, { id = '_reset', label = 'Reset to default' })

local brightness_choices = {
  { id = '0.03', label = 'Very Dark (0.03)' },
  { id = '0.07', label = 'Dark (0.07)' },
  { id = '0.1',  label = 'Default (0.1)' },
  { id = '0.15', label = 'Medium Dark (0.15)' },
  { id = '0.2',  label = 'Medium (0.2)' },
  { id = '0.3',  label = 'Bright (0.3)' },
  { id = '0',    label = 'No wallpaper' },
  { id = '_reset', label = 'Reset to default' },
}

-- ランチャー（F9 / Cmd+Shift+9）共通アクション
-- 選んだアプリを新しいタブで起動する。現在ペイン（Herdr）には何も送らない。
-- 旧方式（2026-09-24 まで）: 現在ペインへ Ctrl+C x2 + Enter を送ってからコマンドを入力していた。
local launcher_action = act.InputSelector {
  title = '  Launch App (新しいタブ)',
  choices = launcher_choices,
  action = wezterm.action_callback(function(window, pane, id, label)
    if not id then return end
    window:perform_action(spawn_in_new_tab(launcher_cmds[id]), pane)
  end),
}

-- キーバインド
config.keys = {
  -- Alt+Enter をターミナルに渡す（Claude Codeの改行用）
  { key = 'Enter', mods = 'ALT', action = act.SendKey { key = 'Enter', mods = 'ALT' } },
  { key = 'd', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'h', mods = 'CTRL', action = act.ActivatePaneDirection 'Left' },
  { key = 'l', mods = 'CTRL', action = act.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL', action = act.ActivatePaneDirection 'Up' },
  { key = 'j', mods = 'CTRL', action = act.ActivatePaneDirection 'Down' },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = true } },
  -- Pane zoom: 現在ペインを一時最大化⇔もう一度で復帰 (Ctrl+Shift+Z)
  { key = 'z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState },
  -- Herdr AI Hub: 同じdefaultセッションを専用WezTermウィンドウで開く。
  -- サーバー側のペイン実体は共有されるため、1枚目のタブの Herdr と別窓の双方から確認できる。
  -- （作業用タブの隣に Herdr を並べて見たいときに使う）
  { key = 'h', mods = 'CTRL|SHIFT', action = act.SpawnCommandInNewWindow {
    args = is_windows and { herdr_exe }
      or { '/bin/bash', '-c', mac_path_prefix .. 'exec "' .. herdr_exe .. '"' },
    cwd = is_windows and 'C:\\claude' or (wezterm.home_dir .. '/claude'),
  } },
  -- Pane repair: ローカルLLM(lms chat等)終了後にConPTYの表示がズレて
  -- 上下ペインが繋がって見える現象向けの復旧ショートカット。
  -- ズームON→OFFを瞬時に往復させ、ペイン境界の再計算・再描画を強制する (Ctrl+Shift+R)
  { key = 'r', mods = 'CTRL|SHIFT', action = act.Multiple { act.TogglePaneZoomState, act.TogglePaneZoomState } },
  -- Pane select: 番号オーバーレイでペインへジャンプ (F8)
  -- ※表示される番号は WezTerm 側の分割順（Herdr 内のペインは対象外）。
  { key = 'F8', mods = 'NONE', action = act.PaneSelect { alphabet = '1234567890', mode = 'Activate' } },
  -- Quick launch: lazygit / Todoist を F9 と同じく新しいタブで起動 (Ctrl+Shift+G / Ctrl+Shift+S)
  -- 旧方式（2026-09-24 まで）は現在ペインへ文字列を送っており、Herdr 表示中は
  -- フォーカス中のエージェントへの入力になってしまうため変更した。
  { key = 'g', mods = 'CTRL|SHIFT', action = spawn_in_new_tab(launcher_cmds['lazygit']) },
  { key = 's', mods = 'CTRL|SHIFT', action = spawn_in_new_tab(launcher_cmds['dashboard']) },
  -- Theme picker: カラースキーム一時切り替え
  -- Win: Ctrl+Shift+F1 / Mac: Cmd+Shift+T (macOS が F1〜F4 を奪うため)
  { key = is_windows and 'F1' or 't', mods = is_windows and 'CTRL|SHIFT' or 'CMD|SHIFT',
    action = act.InputSelector {
      title = 'Color Scheme (session only)',
      choices = theme_choices,
      action = wezterm.action_callback(function(win, _, id)
        if not id then return end
        local o = win:get_config_overrides() or {}
        if id == '_reset' then
          o.color_scheme = nil
          o.background = nil
        else
          o.color_scheme = id
          local lt = light_themes[id]
          if lt then
            -- ライトテーマ: テーマ別の壁紙brightness＋背景opacity
            local f = wallpaper_file
            if o.background and o.background[1] and o.background[1].source then
              f = o.background[1].source.File or f
            end
            o.background = { { source = { File = f }, hsb = { brightness = lt.brightness }, opacity = 0.9, horizontal_align = 'Center', vertical_align = 'Middle', repeat_x = 'NoRepeat', repeat_y = 'NoRepeat' } }
            o.window_background_opacity = lt.opacity
          else
            -- ダークテーマ: デフォルトに戻す
            o.background = nil
            o.window_background_opacity = nil
          end
        end
        win:set_config_overrides(o)
      end),
    },
  },
  -- Background picker: 壁紙の明るさ一時変更
  -- Win: Ctrl+Shift+F2 / Mac: Cmd+Shift+B
  { key = is_windows and 'F2' or 'b', mods = is_windows and 'CTRL|SHIFT' or 'CMD|SHIFT',
    action = act.InputSelector {
      title = 'Wallpaper Brightness (session only)',
      choices = brightness_choices,
      action = wezterm.action_callback(function(win, _, id)
        if not id then return end
        local o = win:get_config_overrides() or {}
        if id == '_reset' then
          o.background = nil
        elseif id == '0' then
          o.background = {}
        else
          local f = wallpaper_file
          if o.background and o.background[1] and o.background[1].source then
            f = o.background[1].source.File or f
          end
          o.background = { { source = { File = f }, hsb = { brightness = tonumber(id) }, opacity = 0.9, horizontal_align = 'Center', vertical_align = 'Middle', repeat_x = 'NoRepeat', repeat_y = 'NoRepeat' } }
        end
        win:set_config_overrides(o)
      end),
    },
  },
  -- Wallpaper picker: 壁紙画像の切り替え
  -- メニューを開くたびにフォルダをスキャンする
  -- Win: Ctrl+Shift+F3 (セッション限り) / Mac: Cmd+Shift+I (状態ファイルに保存して次回起動時も復元)
  { key = is_windows and 'F3' or 'i', mods = is_windows and 'CTRL|SHIFT' or 'CMD|SHIFT',
    action = wezterm.action_callback(function(win, pane)
      local choices = {
        { id = '_none', label = 'No wallpaper' },
        { id = '_reset', label = 'Reset to default' },
      }
      pcall(function()
        for _, ext in ipairs({ '*.jpg', '*.jpeg', '*.png', '*.gif', '*.webp' }) do
          for _, path in ipairs(wezterm.glob(wallpaper_dir .. ext)) do
            local name = path:match('[/\\]([^/\\]+)$') or path
            table.insert(choices, 1, { id = path, label = name })
          end
        end
      end)
      win:perform_action(
        act.InputSelector {
          title = is_windows and 'Wallpaper Image (session only)' or 'Wallpaper Image (persisted)',
          choices = choices,
          action = wezterm.action_callback(function(win2, _, id)
            if not id then return end
            if is_windows then
              -- Win: 従来通り override で一時変更
              local o = win2:get_config_overrides() or {}
              if id == '_reset' then
                o.background = nil
              elseif id == '_none' then
                o.background = {}
              else
                local b = 0.1
                if o.background and o.background[1] and o.background[1].hsb then
                  b = o.background[1].hsb.brightness
                end
                o.background = { { source = { File = id }, hsb = { brightness = b }, opacity = 0.9, horizontal_align = 'Center', vertical_align = 'Middle', repeat_x = 'NoRepeat', repeat_y = 'NoRepeat' } }
              end
              win2:set_config_overrides(o)
            else
              -- Mac: 状態ファイルに保存 → 壁紙系overrideを解除 → reload で即反映
              if id == '_reset' then
                write_wallpaper_state('')
              else
                write_wallpaper_state(id)
              end
              local o = win2:get_config_overrides() or {}
              o.background = nil
              win2:set_config_overrides(o)
              wezterm.reload_configuration()
            end
          end),
        },
        pane
      )
    end),
  },
  -- Profile switcher: テーマ+壁紙セット切り替え
  -- Win: Ctrl+Shift+F4 / Mac: Cmd+Shift+P
  { key = is_windows and 'F4' or 'p', mods = is_windows and 'CTRL|SHIFT' or 'CMD|SHIFT',
    action = act.InputSelector {
      title = '  Profile (テーマ+壁紙セット)',
      choices = (function()
        local c = {}
        for _, p in ipairs(profiles) do
          table.insert(c, { id = p.id, label = p.label })
        end
        table.insert(c, { id = '_reset', label = '↩ Reset to default' })
        return c
      end)(),
      action = wezterm.action_callback(function(win, _, id)
        if not id then return end
        if id == '_reset' then
          local o = win:get_config_overrides() or {}
          o.color_scheme = nil
          o.background = nil
          o.window_background_opacity = nil
          win:set_config_overrides(o)
          return
        end
        for _, p in ipairs(profiles) do
          if p.id == id then
            apply_profile(win, p)
            return
          end
        end
      end),
    },
  },
  -- Herdr workspace switch: Ctrl+Shift+1/2/3/4 で デフォルト / Extra / 🦍 EXECUTION / 🦍 受付 を切替（Win/Mac 共通）
  -- 番号は herdr の作成順（bootstrap の WORKSPACE_PLAN / $workspacePlan の並び）に対応する。
  -- ※ bootstrap の並び替えと herdr server の作り直しが済むまでは、旧構成の順番で動く。
  -- ※ WezTerm 標準の「Ctrl+Shift+数字でタブ切替」を上書きしている。タブ移動は Ctrl+Tab / Ctrl+Shift+Tab を使う。
  { key = '1', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function()
    wezterm.background_child_process { herdr_exe, 'workspace', 'focus', 'w1' }
  end) },
  { key = '2', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function()
    wezterm.background_child_process { herdr_exe, 'workspace', 'focus', 'w2' }
  end) },
  { key = '3', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function()
    wezterm.background_child_process { herdr_exe, 'workspace', 'focus', 'w3' }
  end) },
  { key = '4', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function()
    wezterm.background_child_process { herdr_exe, 'workspace', 'focus', 'w4' }
  end) },
  -- Launcher menu: アプリ切り替え
  -- Win/Mac とも F9。Mac では Mission Control 等に F9 を奪われやすいので
  -- Cmd+Shift+9 も同じメニューに割り当てる（テーマ系の Mac 代替と同じ方針）。
  { key = 'F9', mods = 'NONE', action = launcher_action },
  { key = '9', mods = 'CMD|SHIFT', action = launcher_action },
}

-- ===== AI トークン残量ステータスライン =====
-- 右側に Claude(個/社) のプラン枠使用率（ccusage 近似）と
-- Codex(5h/週) の使用率を表示する。
-- ai_usage.ps1 が $TEMP\wez_ai_status.txt（1行目=UNIX秒, 2行目=本文）を書き、
-- ここではそれを読むだけ（同期 run_child_process はUIが固まるため廃止。2026-07-13）。
-- ファイルが古い（120秒超）ときに background_child_process で ai_usage.ps1 を非同期起動し、次回に備える。
-- 現在の更新元はこの処理だけ（2026-09-24 調査）。旧構成では⑤ペインの ai_usage_pane.ps1（30秒周期）も
-- 更新していたが、今はどこからも起動されていない。
if is_windows then
  local ai_status = ''
  local ai_read_last = 0
  local ai_spawn_last = 0
  local AI_READ_INTERVAL = 10   -- ファイル読み取りの間引き（秒）
  local AI_STALE = 120          -- これより古ければ refresh を非同期起動（秒）
  local temp_dir = os.getenv('TEMP')
  local ai_status_path = temp_dir and (temp_dir .. '\\wez_ai_status.txt') or nil
  wezterm.on('update-status', function(window, pane)
    if not ai_status_path then return end
    local now = os.time()
    if (now - ai_read_last) >= AI_READ_INTERVAL then
      ai_read_last = now
      local ts = nil
      local f = io.open(ai_status_path, 'r')
      if f then
        ts = tonumber(f:read('*l') or '')
        local line = f:read('*l')
        f:close()
        if line and line ~= '' then
          ai_status = line
        end
      end
      -- 古い/無いときだけ非同期で更新起動（多重起動は60秒間隔で抑止）
      if (not ts or (now - ts) > AI_STALE) and (now - ai_spawn_last) >= 60 then
        ai_spawn_last = now
        wezterm.background_child_process({
          'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
          '-File', wezterm.home_dir .. '\\dotfiles\\wezterm\\ai_usage.ps1',
        })
      end
    end
    if ai_status ~= '' then
      window:set_right_status(wezterm.format {
        { Foreground = { Color = '#7aa2f7' } },
        { Text = ' ' .. ai_status .. ' ' },
      })
    end
  end)
end

return config