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
#   w1 デフォルト   : Commander / Sol / Utility / Codex Work - Main（旧 Status 枠）
#   w2 Extra        : Grok / Antigravity CLI / Claude Work - Extra / Codex Work - Extra
#   w3 🦍 EXECUTION : Supervisor / Reviewer A / Worker A / Worker B（中身は変更なし）
#   w4 🦍 受付      : Loop Inbox Receiver（旧 Status 枠の loop_intake.py watch を移設）
# ※「🦍 EXECUTION」のラベルと4役のペイン名は変更しないこと。
#   loop-inbox/loop_reset_execution.py がこのラベル1つで4役をまとめて探している。
# herdr には並べ替えコマンドが無く、番号は作成順で決まる。新規セッションでは
# この順に作られ、既存セッションでは不足分が末尾に追加される。
$workspacePlan = @(
    'デフォルト',
    'Extra',
    '🦍 EXECUTION',
    '🦍 受付'
    # 2026-09-24 退避：ローカルLLM再構築待ち
    # 'Local LLM'
)
$legacyWorkspaceLabels = @{
    'デフォルト'   = 'CONTROL / ENTRY'
    'Extra'        = 'Extra Agents'
    '🦍 EXECUTION' = 'Review Agents'
}
# 退避中のワークスペース。既存セッションに残っていても、位置による採用・リネームの対象にしない
# （既存環境で Local LLM が w4 にあると、🦍 受付として転用されてしまうため）。
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

function Start-AgentIfMissing {
    param(
        [object]$Pane,
        [string]$Command,
        [string]$DisplayName,
        [string[]]$LiveAgentPaneIds
    )

    if (-not $Pane) {
        throw "Required pane is missing: $DisplayName"
    }
    $identity = Get-PaneIdentity $Pane.pane_id $Command
    if ($identity.state -eq 'matching') {
        Write-Host "Already running (process / role / env verified): $DisplayName" -ForegroundColor DarkGray
        return
    }
    if ($identity.state -ne 'empty') {
        throw "Pane $($Pane.pane_id) is occupied by an unverified session ($DisplayName): $($identity.reason). Stop/restart the correct role before bootstrap."
    }

    Write-Host "Starting: $DisplayName" -ForegroundColor Cyan
    & $herdrExe pane run $Pane.pane_id $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start: $DisplayName"
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
$reception = $workspaces['🦍 受付']
# 2026-09-24 退避：ローカルLLM再構築待ち
# $local  = $workspaces['Local LLM']

# デフォルト: 相談窓口とTask Packet作成。CommanderはSupervisorではない。
# 4枚目は旧 Status 枠。Receiver は 🦍 受付 へ移し、ここは Codex 会社にする（2026-09-24）。
# Codex 会社の2枠は「Codex Work - Main」「Codex Work - Extra」とし、一方が他方の前方一致に
# ならない名前にする（loop-inbox/_common.py の宛先解決がペイン名の前方一致のため）。
Initialize-PaneGrid $control 4
Set-PaneLabels $control @(
    'Commander - Claude Work / Opus 5',
    'Sol - Codex Personal / GPT-5.6 Sol',
    'Utility - Claude Personal',
    'Codex Work - Main'
)

# EXTRA: 4枚目は Local LLM - Extra をやめて Codex 会社にする（2026-09-24）。
Initialize-PaneGrid $extra 4
Set-PaneLabels $extra @(
    'Grok',
    'Antigravity CLI',
    'Claude Work - Extra',
    'Codex Work - Extra'
)

# EXECUTION: 入力はTask Packetのみ。Supervisorは実装・文章生成をせずWorkerへ委譲する。
# MVPは1 Loopずつ処理し、ReviewerはAのみ。Reviewer BやLuna Workerは置かない。
# ラベルは loop-inbox/loop_reset_execution.py の ROLES と一致させること（変更禁止）。
Initialize-PaneGrid $execution 4
Set-PaneLabels $execution @(
    'Supervisor - Claude Work / Opus 5',
    'Reviewer A - Claude Work / Opus 5',
    'Worker A - Gemini 3.8 Flash',
    'Worker B - Claude Work / Sonnet 5'
)

# 🦍 受付: Loop Inbox Receiver の1枠（旧 デフォルト/Status 枠から移設。2026-09-24）
Initialize-PaneGrid $reception 1
Set-PaneLabels $reception @('Loop Inbox Receiver')

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
$loopSupervisor = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT loop-supervisor; Set-Location C:\claude; claude --model opus --name loop-supervisor"
$loopReviewer = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT loop-review-a; Set-Location C:\claude; claude --model opus --name loop-review-a"
$loopWorkerGemini = "Set-Item Env:AGMSG_AGENT loop-worker-gemini; Set-Location C:\claude; & $userRoot\AppData\Local\agy\bin\agy.exe --model gemini-3.8-flash-medium --mode accept-edits --dangerously-skip-permissions"
$loopWorkerSonnet = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT loop-worker-sonnet; Set-Location C:\claude; claude --model sonnet --name loop-worker-sonnet"
# Codex 会社（~/.codex-work）。自動承認フラグ（--approve-for-me）は付けない（常駐枠のため）。
# AGMSG_AGENT: Main は agmsg 登録済みの `codex`（旧 会社Codex）を使う。Extra の `codex-extra` は
# Mac 版と同じ名前だが agmsg 未登録のため、このペインで agmsg を使うとエラーになる（2026-09-24 時点）。
$codexWorkMain = "Set-Item Env:AGMSG_AGENT codex; Set-Location C:\claude; & $codexAccountScript -Account work"
$codexWorkExtra = "Set-Item Env:AGMSG_AGENT codex-extra; Set-Location C:\claude; & $codexAccountScript -Account work"
# 2026-09-24 退避：ローカルLLM再構築待ち
# $localLlm = 'lms server start; lms unload --all; lms load lfm2.5-2.6b --context-length 32768 --yes; Set-Location C:\claude; opencode --model lmstudio/lfm2.5-2.6b'
# $localLlmExtra = 'Set-Location C:\claude; opencode --model lmstudio/lfm2.5-2.6b'

# --- デフォルト ---
Start-AgentIfMissing (Get-PaneByLabel $control 'Commander - Claude Work / Opus 5') $claudeWork 'Commander' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $control 'Sol - Codex Personal / GPT-5.6 Sol') $codexPersonal 'Sol' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $control 'Utility - Claude Personal') $claudePersonal 'Utility' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $control 'Codex Work - Main') $codexWorkMain 'Codex Work - Main' $liveAgentPaneIds

# --- 🦍 受付 ---
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
    if ($watchExit -eq 0) {
        $watchIdentity = (& py -3.13 (Join-Path $workRoot 'loop-inbox\loop_process_identity.py') --pane $statusPane.pane_id --watch) | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or $watchIdentity.state -ne 'matching') {
            throw "Receiver identity mismatch: $($watchIdentity.reason)"
        }
        Write-Host 'Already running (PID / heartbeat / owner / pane verified): Loop Inbox Receiver (watch)' -ForegroundColor DarkGray
    } elseif ((Get-PaneIdentity $statusPane.pane_id).state -ne 'empty') {
        throw "Receiver pane $($statusPane.pane_id) is occupied. Receiver command was not sent."
    } else {
        Write-Host 'Starting: Loop Inbox Receiver (watch)' -ForegroundColor Cyan
        & $herdrExe pane run $statusPane.pane_id "Set-Item Env:LOOP_WATCH_OWNER bootstrap; Set-Location $workRoot; py -3.13 $loopIntakeScript watch --interval 30"
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to start: Loop Inbox Receiver'
        }
    }
}

# --- EXECUTION ---
Start-AgentIfMissing (Get-PaneByLabel $execution 'Supervisor - Claude Work / Opus 5') $loopSupervisor 'Supervisor' $liveAgentPaneIds
if (-not $SkipReview) {
    Start-AgentIfMissing (Get-PaneByLabel $execution 'Reviewer A - Claude Work / Opus 5') $loopReviewer 'Reviewer A' $liveAgentPaneIds
}
Start-AgentIfMissing (Get-PaneByLabel $execution 'Worker A - Gemini 3.8 Flash') $loopWorkerGemini 'Worker A - Gemini 3.8 Flash' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $execution 'Worker B - Claude Work / Sonnet 5') $loopWorkerSonnet 'Worker B - Sonnet 5' $liveAgentPaneIds

# --- EXTRA ---
if (-not $SkipExtra) {
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Grok') $grok 'Grok' $liveAgentPaneIds
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Antigravity CLI') $antigravity 'Antigravity CLI' $liveAgentPaneIds
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Claude Work - Extra') $claudeWorkExtra 'Claude Work - Extra' $liveAgentPaneIds
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Codex Work - Extra') $codexWorkExtra 'Codex Work - Extra' $liveAgentPaneIds
}

# 2026-09-24 退避：ローカルLLM再構築待ち
# if (-not $SkipLocal) {
#     Start-AgentIfMissing (Get-PaneByLabel $local 'Local LLM slot (LFM/Qwen/Gemma/Nemotron)') $localLlm 'Local LLM - LFM 2.5' $liveAgentPaneIds
#     if (-not $SkipExtra) {
#         Start-AgentIfMissing (Get-PaneByLabel $extra 'Local LLM - Extra') $localLlmExtra 'Local LLM - Extra' $liveAgentPaneIds
#     }
# }

& $herdrExe workspace focus $control | Out-Null

if (-not $ConfigureOnly) {
    & $herdrExe
}
