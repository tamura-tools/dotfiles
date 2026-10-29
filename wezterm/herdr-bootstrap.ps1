param(
    [switch]$ConfigureOnly,
    # 2026-09-24 退避：ローカルLLM再構築待ち（Local LLM ワークスペースと一緒に停止）
    # [switch]$SkipLocal,
    [switch]$SkipReview,
    [switch]$SkipExtra
)

$ErrorActionPreference = 'Stop'

# herdr.exe のJSON出力はUTF-8。Windows PowerShell 5.1 はネイティブコマンドの出力を
# 既定でcp932として解釈するため、端末タイトルに日本語が入るとJSONが壊れ
# ConvertFrom-Json が「無効なオブジェクト」で失敗する(2026-08-20)。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$herdrExe = Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe'
$codexAccountScript = Join-Path $env:USERPROFILE 'dotfiles\wezterm\codex-account.ps1'
$workRoot = 'C:\claude'

# ワークスペースは「番号順 = この並び順」で扱う（2026-09-24 再編。Windows / Mac 共通）。
#   w1 デフォルト   : Commander / Codex Work - Main / Utility / Sol（2026-10-19 Sol と入替）
#   w2 Extra        : Grok / Antigravity CLI / Claude Work - Extra / Codex Work - Extra
#   w3 📮 受付      : Loop Inbox Receiver / 🦍 Loop Commander / 🐦 Loop Commander / Loop Utility（2026-10-20 4分割）
#   w4 🦍 EXECUTION : Execution Slot 1。Supervisor / Reviewer A / Worker A / Worker B
#   w5 🐦 EXECUTION : Execution Slot 2。4役・ペイン名は w4 と同じ。Pigeon（pigeon-loop）の run はここだけに入る
#   （2026-10-20 並び替え: 受付を EXECUTION の前へ。slot 2 は 🦍 EXECUTION 2 → 🐦 EXECUTION）
#   w6 🛠 Work      : 手動作業用。Claude Work - Desk 1 / Codex Work - Desk 1 / Claude Work - Desk 2 / Codex Work - Desk 2（2026-10-29 追加）
# ※「🦍 EXECUTION」「🐦 EXECUTION」のラベルと4役のペイン名は変更しないこと。
#   loop-inbox/_common.py の SLOTS（slot 1 / slot 2 の契約）と一致させる。Mac 版 herdr-bootstrap.sh も同じ契約。
#   slot 2 の役割名は slot 1 の名前に `-2` を付ける（AGMSG_AGENT / claude --name）。LOOP_SLOT は 1 / 2。
# herdr には並べ替えコマンドが無く、番号は作成順で決まる。新規セッションでは
# この順に作られ、既存セッションでは不足分が末尾に追加される。
$workspacePlan = @(
    'デフォルト',
    'Extra',
    '📮 受付',
    '🦍 EXECUTION',
    '🐦 EXECUTION',
    '🛠 Work'
    # 2026-09-24 退避：ローカルLLM再構築待ち
    # 'Local LLM'
)
$legacyWorkspaceLabels = @{
    'デフォルト'   = 'CONTROL / ENTRY'
    'Extra'        = 'Extra Agents'
    '🦍 EXECUTION' = 'Review Agents'
    '📮 受付'      = '🦍 受付'          # 2026-10-20 受付を4分割
    '🐦 EXECUTION' = '🐦 EXECUTION 2'   # 2026-10-20 slot 2 を Pigeon 優先にしたため改名（旧 🦍 EXECUTION 2 は位置で採用）
}
# 退避中のワークスペース。既存セッションに残っていても、位置による採用・リネームの対象にしない
# （既存環境で Local LLM が w4 にあると、受付として転用されてしまうため）。
$retiredWorkspaceLabels = @(
    'Local LLM'   # 2026-09-24 退避：ローカルLLM再構築待ち
)

function Get-HerdrJson {
    param([string[]]$Arguments)

    $raw = & $herdrExe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Herdr command failed: $($Arguments -join ' ')"
    }
    return ($raw | ConvertFrom-Json)
}

function Test-HerdrServer {
    $result = & $herdrExe status server 2>$null | Out-String
    return ($LASTEXITCODE -eq 0 -and $result -match 'status:\s+running')
}

function Start-HerdrServer {
    if (Test-HerdrServer) {
        return
    }

    Start-Process -FilePath $herdrExe -ArgumentList @('server') -WindowStyle Hidden
    foreach ($attempt in 1..40) {
        Start-Sleep -Milliseconds 250
        if (Test-HerdrServer) {
            return
        }
    }
    throw 'Herdr server did not become ready within 10 seconds.'
}

# ---------- ワークスペース ----------

function Get-WorkspaceList {
    $response = Get-HerdrJson @('workspace', 'list')
    return @($response.result.workspaces) | Sort-Object number
}

# 計画順にワークスペースを解決する。
#   1. 同じラベルが既にあればそれを使う
#   2. その位置に「計画外のラベル」のワークスペースがあれば採用してリネームする
#      （新規セッションの既定ワークスペースを w1 CORE として拾うため）
#   3. どちらでもなければ新規作成する（既存セッションでは末尾に付く）
function Resolve-Workspaces {
    $existing = @(Get-WorkspaceList)
    $resolved = [ordered]@{}

    for ($i = 0; $i -lt $workspacePlan.Count; $i++) {
        $label = $workspacePlan[$i]

        $match = $existing | Where-Object label -eq $label | Select-Object -First 1
        if ($match) {
            $resolved[$label] = $match.workspace_id
            continue
        }

        # 旧役割名は位置ではなくラベルで移行する。既存環境ではReview Agentsが
        # w4にある場合があり、位置採用するとExtra Agentsを誤転用するため。
        $legacyLabel = $legacyWorkspaceLabels[$label]
        $legacy = $existing | Where-Object label -eq $legacyLabel | Select-Object -First 1
        if ($legacy) {
            Write-Host "Renaming workspace: $legacyLabel -> $label" -ForegroundColor Cyan
            & $herdrExe workspace rename $legacy.workspace_id $label | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to rename workspace: $($legacy.workspace_id)"
            }
            $legacy.label = $label
            $resolved[$label] = $legacy.workspace_id
            continue
        }

        $candidate = $existing | Select-Object -Skip $i -First 1
        if ($candidate -and ($workspacePlan -notcontains $candidate.label) -and ($retiredWorkspaceLabels -notcontains $candidate.label)) {
            Write-Host "Renaming workspace: $($candidate.label) -> $label" -ForegroundColor Cyan
            & $herdrExe workspace rename $candidate.workspace_id $label | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to rename workspace: $($candidate.workspace_id)"
            }
            $candidate.label = $label
            $resolved[$label] = $candidate.workspace_id
            continue
        }

        Write-Host "Creating workspace: $label" -ForegroundColor Cyan
        $created = Get-HerdrJson @('workspace', 'create', '--label', $label, '--cwd', $workRoot, '--no-focus')
        $workspaceId = $created.result.workspace.workspace_id
        $resolved[$label] = $workspaceId
        $existing = @($existing) + ([pscustomobject]@{
            workspace_id = $workspaceId
            label        = $label
            number       = 9999
        })
    }

    return $resolved
}

# ---------- ペイン ----------

# pane_id は "w1:p3" 形式。番号は作成順に採番されるため、番号順に並べると
# 左上 → 右上 → 左下 → 右下 になる（下の Initialize-PaneGrid の分割順に対応）。
function Get-SortedPaneIds {
    param([string]$WorkspaceId)

    $response = Get-HerdrJson @('pane', 'list', '--workspace', $WorkspaceId)
    return @(@($response.result.panes) |
        Sort-Object { [int](($_.pane_id -split ':p')[1]) } |
        ForEach-Object pane_id)
}

function Split-HerdrPane {
    param(
        [string]$PaneId,
        [ValidateSet('right', 'down')][string]$Direction
    )

    $response = Get-HerdrJson @('pane', 'split', '--pane', $PaneId, '--direction', $Direction, '--no-focus')
    return $response.result.pane.pane_id
}

# 目標枚数までペインを用意する。既に足りていれば何もしない（冪等）。
function Initialize-PaneGrid {
    param(
        [string]$WorkspaceId,
        [int]$Want = 4
    )

    $ids = @(Get-SortedPaneIds $WorkspaceId)
    if ($ids.Count -eq 1 -and $Want -eq 4) {
        $topLeft = $ids[0]
        $topRight = Split-HerdrPane $topLeft 'right'
        Split-HerdrPane $topLeft 'down' | Out-Null
        Split-HerdrPane $topRight 'down' | Out-Null
    }

    # 不足分は最後のペインを下に割って埋める
    while ((Get-SortedPaneIds $WorkspaceId).Count -lt $Want) {
        $last = @(Get-SortedPaneIds $WorkspaceId)[-1]
        Split-HerdrPane $last 'down' | Out-Null
    }
}

# ラベルを pane_id 昇順で割り当てる。以降のエージェント起動は並び順ではなく
# ラベルで引く（herdr pane list の返却順は作成順ではない。2026-08-30 の学び）。
function Set-PaneLabels {
    param(
        [string]$WorkspaceId,
        [string[]]$Labels
    )

    $ids = @(Get-SortedPaneIds $WorkspaceId)
    for ($i = 0; $i -lt $Labels.Count -and $i -lt $ids.Count; $i++) {
        & $herdrExe pane rename $ids[$i] $Labels[$i] | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to rename pane: $($ids[$i]) -> $($Labels[$i])"
        }
    }
}

function Get-PaneByLabel {
    param(
        [string]$WorkspaceId,
        [string]$Label
    )

    $response = Get-HerdrJson @('pane', 'list', '--workspace', $WorkspaceId)
    return @($response.result.panes) |
        Where-Object label -eq $Label |
        Select-Object -First 1
}

# ---------- エージェント ----------

function Get-LiveAgentPaneIds {
    $response = Get-HerdrJson @('agent', 'list')
    return @($response.result.agents | ForEach-Object pane_id)
}

# 1ペインの不一致・起動失敗では止めず、そのペインだけ飛ばして残りを起動する（2026-10-20）。
# 占有中のペインへコマンドを送らない安全側は変えない。飛ばしたものは最後にまとめて表示し exit 1 にする
# （WezTerm は herdr server の起動だけを待つため、exit 1 でも画面は開く。理由は bootstrap.log に残る）。
$script:skippedPanes = New-Object System.Collections.Generic.List[string]
function Skip-Pane {
    param([string]$Message)
    Write-Warning "Skipped: $Message"
    $script:skippedPanes.Add($Message)
}

function Start-AgentIfMissing {
    param(
        [object]$Pane,
        [string]$Command,
        [string]$DisplayName,
        [string[]]$LiveAgentPaneIds,
        # 会話用ペイン（w1 デフォルト / w2 Extra）。人が手で起動し直すことがあるため、
        # 何か動いていれば照合せず「使用中」として触らない（警告・exit 1 にしない。2026-10-20）
        [switch]$Interactive
    )

    if (-not $Pane) {
        Skip-Pane "Required pane is missing: $DisplayName"
        return
    }
    try {
        $identity = Get-PaneIdentity $Pane.pane_id $Command
    } catch {
        Skip-Pane "$DisplayName ($($Pane.pane_id)): $($_.Exception.Message)"
        return
    }
    if ($identity.state -eq 'matching') {
        Write-Host "Already running (process / role / env verified): $DisplayName" -ForegroundColor DarkGray
        return
    }
    if ($identity.state -ne 'empty' -and $Interactive) {
        Write-Host "In use (not verified, left as is): $DisplayName" -ForegroundColor DarkGray
        return
    }
    if ($identity.state -ne 'empty') {
        Skip-Pane "Pane $($Pane.pane_id) is occupied by an unverified session ($DisplayName): $($identity.reason). Stop/restart the correct role, then re-run bootstrap."
        return
    }

    Write-Host "Starting: $DisplayName" -ForegroundColor Cyan
    & $herdrExe pane run $Pane.pane_id $Command
    if ($LASTEXITCODE -ne 0) {
        Skip-Pane "Failed to start: $DisplayName"
    }
}

function Get-PaneIdentity {
    param([string]$PaneId, [string]$Command = ' ')
    $checker = Join-Path $workRoot 'loop-inbox\loop_process_identity.py'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Command))
    # 環境が読めない場合も occupied。タイトルだけで稼働済みとはしない。
    $raw = & py -3.13 $checker --pane $PaneId --command-b64 $encoded
    if ($LASTEXITCODE -ne 0) { throw "Process identity check failed: $PaneId" }
    return ($raw | ConvertFrom-Json)
}

# ---------- メイン ----------

Start-HerdrServer

$workspaces = Resolve-Workspaces
$control   = $workspaces['デフォルト']
$extra     = $workspaces['Extra']
$execution = $workspaces['🦍 EXECUTION']
$reception = $workspaces['📮 受付']
$execution2 = $workspaces['🐦 EXECUTION']
$desk      = $workspaces['🛠 Work']
# 2026-09-24 退避：ローカルLLM再構築待ち
# $local  = $workspaces['Local LLM']

# デフォルト: 相談窓口とTask Packet作成。CommanderはSupervisorではない。
# 4枚目は旧 Status 枠。Receiver は 受付 へ移し、ここは Codex 会社にする（2026-09-24）。
# Codex 会社の2枠は「Codex Work - Main」「Codex Work - Extra」とし、一方が他方の前方一致に
# ならない名前にする（loop-inbox/_common.py の宛先解決がペイン名の前方一致のため）。
# 2026-10-19: 2枚目と4枚目を入れ替え（Codex Work - Main を右上、Sol を右下）。Sol のモデル表記は削除。
Initialize-PaneGrid $control 4
Set-PaneLabels $control @(
    'Commander - Claude Work / Opus 5',
    'Codex Work - Main',
    'Utility - Claude Personal',
    'Sol - Codex Personal'
)

# EXTRA: 4枚目は Local LLM - Extra をやめて Codex 会社にする（2026-09-24）。
Initialize-PaneGrid $extra 4
Set-PaneLabels $extra @(
    'Grok',
    'Antigravity CLI',
    'Claude Work - Extra',
    'Codex Work - Extra'
)

# 🛠 Work: 手動作業用の会社Claude / 会社Codex 各2枠（2026-10-29）。
# ラベルは「Desk 1」「Desk 2」とし、既存の「- Extra」「- Main」と前方一致で衝突させない（_common.py の宛先解決対策）。
Initialize-PaneGrid $desk 4
Set-PaneLabels $desk @(
    'Claude Work - Desk 1',
    'Codex Work - Desk 1',
    'Claude Work - Desk 2',
    'Codex Work - Desk 2'
)

# EXECUTION: 入力はTask Packetのみ。Supervisorは実装・文章生成をせずWorkerへ委譲する。
# 独立 run を最大2本（Execution Slot 1 = 🦍 EXECUTION / slot 2 = 🐦 EXECUTION）。1 slot = 1 run。ReviewerはAのみ。
# ラベルは loop-inbox/loop_reset_execution.py の ROLES と一致させること（変更禁止。両 slot 共通）。
$executionLabels = @(
    'Supervisor - Claude Work / Opus 5',
    'Reviewer A - Codex Work / GPT-6.1 Sol',
    'Worker A - Gemini 3.8 Flash',
    'Worker B - Claude Work / Sonnet 5'
)
Initialize-PaneGrid $execution 4
Set-PaneLabels $execution $executionLabels
Initialize-PaneGrid $execution2 4
Set-PaneLabels $execution2 $executionLabels

# 📮 受付（2026-10-20 4分割）: Receiver（loop_intake.py watch）と、ループの上り通知の受け手。
# 通知の宛先は loop-inbox/_common.py の DEFAULT_NOTIFY_TARGET（loop-commander）と ITEM_NOTIFY_TARGETS（pigeon-loop → pigeon-commander）。
# Loop Utility は drain・status・run 確認などを人が頼む枠（通知は来ない）。
Initialize-PaneGrid $reception 4
Set-PaneLabels $reception @(
    'Loop Inbox Receiver',
    '🦍 Loop Commander - Claude Work / Opus 5',
    '🐦 Loop Commander - Claude Work / Sonnet 5',
    'Loop Utility - Claude Work / Sonnet 5'
)

# 2026-09-24 退避：ローカルLLM再構築待ち
# # Local LLM: 1枠
# Initialize-PaneGrid $local 1
# Set-PaneLabels $local @('Local LLM slot (LFM/Qwen/Gemma/Nemotron)')

$liveAgentPaneIds = Get-LiveAgentPaneIds
$userRoot = $env:USERPROFILE

$claudeWork = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT commander; Set-Location C:\claude; claude --model opus --name commander"
$claudePersonal = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude-personal; Set-Item Env:AGMSG_AGENT utility; Set-Location C:\claude; claude --name utility"
$codexPersonal = "Set-Item Env:AGMSG_AGENT codex-sol; Set-Location C:\claude; & $codexAccountScript -Account personal"
$claudeWorkExtra = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT claude-extra; Set-Location C:\claude; claude --name claude-extra"
$grok = 'Set-Location C:\claude; grok'
$antigravity = "Set-Location C:\claude; & $userRoot\AppData\Local\agy\bin\agy.exe"
# Execution Slot 1（🦍 EXECUTION）。loop_reset_execution.py がこの4変数を起動コマンドの正本として読む
# Worker A（Gemini / Writer）は staging 方式（loop-inbox/loop_writer.py）。専用 HOME（~/.agents/loop-writer/slot-<n>/home）の
# settings.json / hooks.json で writer_guard.py が全ツールを判定する（明示許可以外 deny、run_command 全面 deny、
# 書き込みは run の writer-out 内の宣言済み成果物だけ）。HOME を差し替えるため LOOP_INBOX_STATE を明示する（2026-09-24）
$loopSupervisor = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:LOOP_SLOT 1; Set-Item Env:AGMSG_AGENT loop-supervisor; Set-Location C:\claude; claude --model opus --name loop-supervisor"
# Reviewer A は会社Codex（~/.codex-work, GPT-6.1 Sol）。Claude の容量を抑えるため 2026-10-15 に Opus から切替。
# codex-account.ps1 は変数を使わず絶対パスで書く（loop_reset_execution.py が未展開の変数を拒否するため）。
# run 単位で `--reviewer-model claude-*` を指定したときだけ $loopReviewerClaude（Claude Work）で起動し、--model を差し替える。
$loopReviewer = "Set-Item Env:LOOP_SLOT 1; Set-Item Env:AGMSG_AGENT loop-review-a; Set-Location C:\claude; & $userRoot\dotfiles\wezterm\codex-account.ps1 -Account work --model gpt-6.1-sol"
$loopReviewerClaude = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:LOOP_SLOT 1; Set-Item Env:AGMSG_AGENT loop-review-a; Set-Location C:\claude; claude --model opus --name loop-review-a"
$loopWorkerGemini = "Set-Item Env:LOOP_SLOT 1; Set-Item Env:AGMSG_AGENT loop-worker-gemini; Set-Item Env:LOOP_INBOX_STATE $userRoot\.agents\loop-inbox; Set-Item Env:USERPROFILE $userRoot\.agents\loop-writer\slot-1\home; Set-Item Env:HOME $userRoot\.agents\loop-writer\slot-1\home; py -3.13 C:\claude\loop-inbox\loop_writer.py ensure-profile --slot 1 --home $userRoot\.agents\loop-writer\slot-1\home; Set-Location C:\claude; & $userRoot\AppData\Local\agy\bin\agy.exe --model gemini-3.8-flash-medium --mode accept-edits --dangerously-skip-permissions"
$loopWorkerSonnet = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:LOOP_SLOT 1; Set-Item Env:AGMSG_AGENT loop-worker-sonnet; Set-Location C:\claude; claude --model sonnet --name loop-worker-sonnet"
# Execution Slot 2（🐦 EXECUTION）。slot 1 と同じコマンドで、役割名に -2・LOOP_SLOT 2（変数名は末尾 2）
$loopSupervisor2 = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:LOOP_SLOT 2; Set-Item Env:AGMSG_AGENT loop-supervisor-2; Set-Location C:\claude; claude --model opus --name loop-supervisor-2"
$loopReviewer2 = "Set-Item Env:LOOP_SLOT 2; Set-Item Env:AGMSG_AGENT loop-review-a-2; Set-Location C:\claude; & $userRoot\dotfiles\wezterm\codex-account.ps1 -Account work --model gpt-6.1-sol"
$loopReviewerClaude2 = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:LOOP_SLOT 2; Set-Item Env:AGMSG_AGENT loop-review-a-2; Set-Location C:\claude; claude --model opus --name loop-review-a-2"
$loopWorkerGemini2 = "Set-Item Env:LOOP_SLOT 2; Set-Item Env:AGMSG_AGENT loop-worker-gemini-2; Set-Item Env:LOOP_INBOX_STATE $userRoot\.agents\loop-inbox; Set-Item Env:USERPROFILE $userRoot\.agents\loop-writer\slot-2\home; Set-Item Env:HOME $userRoot\.agents\loop-writer\slot-2\home; py -3.13 C:\claude\loop-inbox\loop_writer.py ensure-profile --slot 2 --home $userRoot\.agents\loop-writer\slot-2\home; Set-Location C:\claude; & $userRoot\AppData\Local\agy\bin\agy.exe --model gemini-3.8-flash-medium --mode accept-edits --dangerously-skip-permissions"
$loopWorkerSonnet2 = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:LOOP_SLOT 2; Set-Item Env:AGMSG_AGENT loop-worker-sonnet-2; Set-Location C:\claude; claude --model sonnet --name loop-worker-sonnet-2"
# 📮 受付の通知の受け手。起動時に手順書を読ませる（🦍 = 旧記事ループ等の既定、🐦 = Pigeon）
$loopCommander = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT loop-commander; Set-Location C:\claude; claude --model opus --name loop-commander 'Read C:\claude\loop-inbox\LOOP_COMMANDER.md and act as loop-commander. Wait for loop notifications.'"
$pigeonCommander = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT pigeon-commander; Set-Location C:\claude; claude --model sonnet --name pigeon-commander 'Read C:\claude\loop-inbox\PIGEON_COMMANDER.md and act as pigeon-commander. Wait for loop notifications.'"
$loopUtility = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT loop-utility; Set-Location C:\claude; claude --model sonnet --name loop-utility"
# Codex 会社（~/.codex-work）。自動承認フラグ（--approve-for-me）は付けない（常駐枠のため）。
# AGMSG_AGENT: Main は agmsg 登録済みの `codex`（旧 会社Codex）を使う。Extra の `codex-extra` は
# Mac 版と同じ名前だが agmsg 未登録のため、このペインで agmsg を使うとエラーになる（2026-09-24 時点）。
$codexWorkMain = "Set-Item Env:AGMSG_AGENT codex; Set-Location C:\claude; & $codexAccountScript -Account work"
$codexWorkExtra = "Set-Item Env:AGMSG_AGENT codex-extra; Set-Location C:\claude; & $codexAccountScript -Account work"
# 🛠 Work。AGMSG_AGENT は agmsg 未登録（codex-extra と同じ扱い。agmsg を使う場合は登録が必要）
$claudeWorkDesk1 = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT claude-desk-1; Set-Location C:\claude; claude --name claude-desk-1"
$claudeWorkDesk2 = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT claude-desk-2; Set-Location C:\claude; claude --name claude-desk-2"
$codexWorkDesk1 = "Set-Item Env:AGMSG_AGENT codex-desk-1; Set-Location C:\claude; & $codexAccountScript -Account work"
$codexWorkDesk2 = "Set-Item Env:AGMSG_AGENT codex-desk-2; Set-Location C:\claude; & $codexAccountScript -Account work"
# 2026-09-24 退避：ローカルLLM再構築待ち
# $localLlm = 'lms server start; lms unload --all; lms load lfm2.5-2.6b --context-length 32768 --yes; Set-Location C:\claude; opencode --model lmstudio/lfm2.5-2.6b'
# $localLlmExtra = 'Set-Location C:\claude; opencode --model lmstudio/lfm2.5-2.6b'

# --- デフォルト ---
Start-AgentIfMissing (Get-PaneByLabel $control 'Commander - Claude Work / Opus 5') $claudeWork 'Commander' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $control 'Sol - Codex Personal') $codexPersonal 'Sol' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $control 'Utility - Claude Personal') $claudePersonal 'Utility' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $control 'Codex Work - Main') $codexWorkMain 'Codex Work - Main' $liveAgentPaneIds -Interactive

# --- 📮 受付 ---
Start-AgentIfMissing (Get-PaneByLabel $reception '🦍 Loop Commander - Claude Work / Opus 5') $loopCommander '🦍 Loop Commander' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $reception '🐦 Loop Commander - Claude Work / Sonnet 5') $pigeonCommander '🐦 Loop Commander' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $reception 'Loop Utility - Claude Work / Sonnet 5') $loopUtility 'Loop Utility' $liveAgentPaneIds
# Multi-Entry Loop Inbox の Receiver（loop_intake.py watch）を常駐させる（2026-09-03。2026-09-24 に Status 枠から移設）。
# エージェントではないので agent list に出ない。起動済み判定は watch の lock（~/.agents/loop-inbox/watch.lock.json、
# PID + heartbeat）を見る `watch-status`（稼働中なら exit 0）で行う。Herdr の pane process-info は子プロセス（python）を
# foreground に出さないため使えない（2026-09-03 実機確認）。watch 自体も同じ lock で二重起動を拒否する。
$loopIntakeScript = Join-Path $workRoot 'loop-inbox\loop_intake.py'
$statusPane = Get-PaneByLabel $reception 'Loop Inbox Receiver'
if ($statusPane -and (Test-Path $loopIntakeScript)) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & py -3.13 $loopIntakeScript watch-status *> $null
    $watchExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    try {
        if ($watchExit -eq 0) {
            $watchIdentity = (& py -3.13 (Join-Path $workRoot 'loop-inbox\loop_process_identity.py') --pane $statusPane.pane_id --watch) | ConvertFrom-Json
            if ($LASTEXITCODE -ne 0 -or $watchIdentity.state -ne 'matching') {
                Skip-Pane "Receiver identity mismatch: $($watchIdentity.reason)"
            } else {
                Write-Host 'Already running (PID / heartbeat / owner / pane verified): Loop Inbox Receiver (watch)' -ForegroundColor DarkGray
            }
        } elseif ((Get-PaneIdentity $statusPane.pane_id).state -ne 'empty') {
            Skip-Pane "Receiver pane $($statusPane.pane_id) is occupied. Receiver command was not sent."
        } else {
            Write-Host 'Starting: Loop Inbox Receiver (watch)' -ForegroundColor Cyan
            & $herdrExe pane run $statusPane.pane_id "Set-Item Env:LOOP_WATCH_OWNER bootstrap; Set-Location $workRoot; py -3.13 $loopIntakeScript watch --interval 30"
            if ($LASTEXITCODE -ne 0) {
                Skip-Pane 'Failed to start: Loop Inbox Receiver'
            }
        }
    } catch {
        Skip-Pane "Loop Inbox Receiver: $($_.Exception.Message)"
    }
}

# --- EXECUTION ---
Start-AgentIfMissing (Get-PaneByLabel $execution 'Supervisor - Claude Work / Opus 5') $loopSupervisor 'Supervisor' $liveAgentPaneIds
if (-not $SkipReview) {
    Start-AgentIfMissing (Get-PaneByLabel $execution 'Reviewer A - Codex Work / GPT-6.1 Sol') $loopReviewer 'Reviewer A' $liveAgentPaneIds
}
Start-AgentIfMissing (Get-PaneByLabel $execution 'Worker A - Gemini 3.8 Flash') $loopWorkerGemini 'Worker A - Gemini 3.8 Flash' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $execution 'Worker B - Claude Work / Sonnet 5') $loopWorkerSonnet 'Worker B - Sonnet 5' $liveAgentPaneIds

# --- 🐦 EXECUTION（Execution Slot 2）---
Start-AgentIfMissing (Get-PaneByLabel $execution2 'Supervisor - Claude Work / Opus 5') $loopSupervisor2 'Supervisor (slot 2)' $liveAgentPaneIds
if (-not $SkipReview) {
    Start-AgentIfMissing (Get-PaneByLabel $execution2 'Reviewer A - Codex Work / GPT-6.1 Sol') $loopReviewer2 'Reviewer A (slot 2)' $liveAgentPaneIds
}
Start-AgentIfMissing (Get-PaneByLabel $execution2 'Worker A - Gemini 3.8 Flash') $loopWorkerGemini2 'Worker A - Gemini 3.8 Flash (slot 2)' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $execution2 'Worker B - Claude Work / Sonnet 5') $loopWorkerSonnet2 'Worker B - Sonnet 5 (slot 2)' $liveAgentPaneIds

# --- EXTRA ---
if (-not $SkipExtra) {
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Grok') $grok 'Grok' $liveAgentPaneIds -Interactive
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Antigravity CLI') $antigravity 'Antigravity CLI' $liveAgentPaneIds -Interactive
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Claude Work - Extra') $claudeWorkExtra 'Claude Work - Extra' $liveAgentPaneIds -Interactive
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Codex Work - Extra') $codexWorkExtra 'Codex Work - Extra' $liveAgentPaneIds -Interactive
}

# --- 🛠 Work ---
Start-AgentIfMissing (Get-PaneByLabel $desk 'Claude Work - Desk 1') $claudeWorkDesk1 'Claude Work - Desk 1' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $desk 'Codex Work - Desk 1') $codexWorkDesk1 'Codex Work - Desk 1' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $desk 'Claude Work - Desk 2') $claudeWorkDesk2 'Claude Work - Desk 2' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $desk 'Codex Work - Desk 2') $codexWorkDesk2 'Codex Work - Desk 2' $liveAgentPaneIds -Interactive

# 2026-09-24 退避：ローカルLLM再構築待ち
# if (-not $SkipLocal) {
#     Start-AgentIfMissing (Get-PaneByLabel $local 'Local LLM slot (LFM/Qwen/Gemma/Nemotron)') $localLlm 'Local LLM - LFM 2.5' $liveAgentPaneIds
#     if (-not $SkipExtra) {
#         Start-AgentIfMissing (Get-PaneByLabel $extra 'Local LLM - Extra') $localLlmExtra 'Local LLM - Extra' $liveAgentPaneIds
#     }
# }

& $herdrExe workspace focus $control | Out-Null

if ($script:skippedPanes.Count -gt 0) {
    Write-Warning "Bootstrap finished with $($script:skippedPanes.Count) skipped pane(s):"
    $script:skippedPanes | ForEach-Object { Write-Warning "  - $_" }
    exit 1
}

if (-not $ConfigureOnly) {
    & $herdrExe
}
