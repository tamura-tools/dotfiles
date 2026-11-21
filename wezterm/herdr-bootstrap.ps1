param(
    [switch]$ConfigureOnly,
    # 2026-09-24 退避：ローカルLLM再構築待ち（Local LLM ワークスペースと一緒に停止）
    # [switch]$SkipLocal,
    # 2026-11-17: 対象のワークスペース（EXECUTION / Extra）を廃止したため未使用。
    # 古い呼び出しが引数エラーにならないよう、受け付けるだけにしている。
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

# ===== 構成（2026-11-17 再編）=====
# 起動時に作るワークスペースは「デフォルト」1つ、4面だけ。
#   ┌──────────────────────────────┬──────────────────────────┐
#   │ Commander（会社Claude・メイン）│ Codex Work - Main（会社） │
#   ├──────────────────────────────┼──────────────────────────┤
#   │ Claude Work - Extra（会社2本目）│ Utility（個人Claude）     │
#   └──────────────────────────────┴──────────────────────────┘
#   左下の「Claude Work - Extra」は、Pigeon（pigeon-loop）を都度呼び出すときにも使う。専用の窓口は常駐させない。
# 2026-11-17 に外したもの（必要になったら dotfiles の git 履歴から戻す）:
#   - Extra（Grok / Antigravity CLI / Codex Work - Extra）と 🛠 Work … 使うときだけ F9 ランチャーから起動する
#   - Sol（個人Codex）… 常駐をやめた。F9 の「Codex CLI (個人)」から起動する
#   - 📮 受付 / 🦍 EXECUTION / 🐦 EXECUTION と Loop Inbox Receiver … 🦍ループを外した。
#     Pigeon はループに乗せず、pigeon コマンドを都度実行する
# ※ loop-inbox/loop_reset_execution.py と tests/test_slot_contract.py は、このファイルの旧記述
#   （$loopSupervisor 等・slot 1 / 2 の契約）を前提にしている。🦍ループを再開する場合は旧版を戻すこと。
# ※ Mac 版 herdr-bootstrap.sh はこの再編の対象外（2026-11-17 時点で旧構成のまま）。
# herdr には並べ替えコマンドが無く、番号は作成順で決まる。
$workspacePlan = @(
    'デフォルト'
)
$legacyWorkspaceLabels = @{
    'デフォルト' = 'CONTROL / ENTRY'
}
# 廃止・退避したワークスペース。既存セッションに残っていても、位置による採用・リネームの対象にしない
# （残っていた旧ワークスペースが「デフォルト」として転用されるのを防ぐ）。
# 旧ワークスペース自体はこのスクリプトでは閉じない。消すときは herdr server を止めて保存状態を消す。
$retiredWorkspaceLabels = @(
    'Local LLM',        # 2026-09-24 退避：ローカルLLM再構築待ち
    'Extra',            # 以下 2026-11-17 廃止（旧名も含める）
    'Extra Agents',
    '📮 受付',
    '🦍 受付',
    '🦍 EXECUTION',
    'Review Agents',
    '🐦 EXECUTION',
    '🐦 EXECUTION 2',
    '🛠 Work'
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
$control = $workspaces['デフォルト']

# デフォルト: 4面（左上 → 右上 → 左下 → 右下 の順にラベルを付ける）。
# ラベルは、一方が他方の前方一致にならない名前にする（ペイン名で宛先を探す処理の取り違え防止）。
Initialize-PaneGrid $control 4
Set-PaneLabels $control @(
    'Commander - Claude Work / Opus 5',
    'Codex Work - Main',
    'Claude Work - Extra',
    'Utility - Claude Personal'
)

$liveAgentPaneIds = Get-LiveAgentPaneIds
$userRoot = $env:USERPROFILE

$claudeWork = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT commander; Set-Location C:\claude; claude --model opus --name commander"
# 会社Claude の2本目（旧 Extra ワークスペースの同名ペインと同じ起動コマンド）。Pigeon を呼ぶときもここを使う。
$claudeWorkExtra = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT claude-extra; Set-Location C:\claude; claude --name claude-extra"
$claudePersonal = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude-personal; Set-Item Env:AGMSG_AGENT utility; Set-Location C:\claude; claude --name utility"
# Codex 会社（~/.codex-work）。自動承認フラグ（--approve-for-me）は付けない（常駐枠のため）。
$codexWorkMain = "Set-Item Env:AGMSG_AGENT codex; Set-Location C:\claude; & $codexAccountScript -Account work"

# 4面とも会話用ペイン。何か動いていれば照合せず「使用中」として触らない（-Interactive）。
Start-AgentIfMissing (Get-PaneByLabel $control 'Commander - Claude Work / Opus 5') $claudeWork 'Commander' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $control 'Codex Work - Main') $codexWorkMain 'Codex Work - Main' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $control 'Claude Work - Extra') $claudeWorkExtra 'Claude Work - Extra' $liveAgentPaneIds -Interactive
Start-AgentIfMissing (Get-PaneByLabel $control 'Utility - Claude Personal') $claudePersonal 'Utility' $liveAgentPaneIds -Interactive

& $herdrExe workspace focus $control | Out-Null

if ($script:skippedPanes.Count -gt 0) {
    Write-Warning "Bootstrap finished with $($script:skippedPanes.Count) skipped pane(s):"
    $script:skippedPanes | ForEach-Object { Write-Warning "  - $_" }
    exit 1
}

if (-not $ConfigureOnly) {
    & $herdrExe
}