param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('work', 'personal')]
    [string]$Account,

    [switch]$CheckOnly,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs
)

$ErrorActionPreference = 'Stop'

switch ($Account) {
    'work' {
        $accountLabel = 'WORK'
        $accountEmail = 'tamura.k@t-sss.co.jp'
        $accountHome = Join-Path -Path $env:USERPROFILE -ChildPath '.codex-work'
    }
    'personal' {
        $accountLabel = 'PERSONAL'
        $accountEmail = 'densontamra@gmail.com'
        # Share history and resume state with the desktop app.
        # Keep Work isolated under .codex-work.
        $accountHome = Join-Path -Path $env:USERPROFILE -ChildPath '.codex'
    }
}

if ([string]::IsNullOrWhiteSpace($accountHome)) {
    throw ('Failed to resolve CODEX_HOME for account: {0}' -f $Account)
}

# Codex validates CODEX_HOME before login and will not create a missing root.
# Create only the selected account home before exporting the variable.
if (-not (Test-Path -LiteralPath $accountHome)) {
    New-Item -ItemType Directory -Path $accountHome -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $accountHome -PathType Container)) {
    throw ('Failed to create CODEX_HOME: {0}' -f $accountHome)
}

$hadPreviousCodexHome = Test-Path Env:CODEX_HOME
$previousCodexHome = $env:CODEX_HOME
$env:CODEX_HOME = $accountHome
$credentialOverride = 'cli_auth_credentials_store="file"'

# A CLI launched from Codex Desktop inherits the parent task's managed
# permission profile and can reject even local reads with approval_policy=never
# and sandbox=read-only. Clear nested-session markers while this isolated CLI
# runs, then restore the parent environment when it exits.
$nestedCodexEnvNames = @(
    'CODEX_APP_TOOLS_PIPE_PATH',
    'CODEX_CI',
    'CODEX_INTERNAL_ORIGINATOR_OVERRIDE',
    'CODEX_SESSION_ID',
    'CODEX_THREAD_ID'
)
$previousNestedCodexEnv = @{}
foreach ($name in $nestedCodexEnvNames) {
    $envPath = 'Env:{0}' -f $name
    if (Test-Path -LiteralPath $envPath) {
        $previousNestedCodexEnv[$name] = (Get-Item -LiteralPath $envPath).Value
        Remove-Item -LiteralPath $envPath
    }
}

function Get-CodexAuthEmail {
    param([string]$CodexHome)

    $authPath = Join-Path $CodexHome 'auth.json'
    if (-not (Test-Path -LiteralPath $authPath)) {
        return $null
    }

    try {
        $auth = Get-Content -LiteralPath $authPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $idToken = $null
        if ($auth.tokens -and $auth.tokens.id_token) {
            $idToken = $auth.tokens.id_token
        }
        elseif ($auth.id_token) {
            $idToken = $auth.id_token
        }

        if (-not $idToken) {
            return $null
        }

        $parts = $idToken.Split('.')
        if ($parts.Count -lt 2) {
            return $null
        }

        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }

        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $claims = $json | ConvertFrom-Json
        return $claims.email
    }
    catch {
        return $null
    }
}

function Test-ExpectedAccount {
    $actualEmail = Get-CodexAuthEmail -CodexHome $accountHome
    if (-not $actualEmail) {
        return [pscustomobject]@{ IsMatch = $false; Email = $null; Reason = 'missing' }
    }
    if ($actualEmail -ne $accountEmail) {
        return [pscustomobject]@{ IsMatch = $false; Email = $actualEmail; Reason = 'mismatch' }
    }
    return [pscustomobject]@{ IsMatch = $true; Email = $actualEmail; Reason = 'ok' }
}

function Write-AccountHeader {
    param([string]$Color)

    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor $Color
    Write-Host (' CODEX {0}: {1}' -f $accountLabel, $accountEmail) -ForegroundColor $Color
    Write-Host (' CODEX_HOME: {0}' -f $accountHome) -ForegroundColor DarkGray
    Write-Host ('=' * 68) -ForegroundColor $Color
    Write-Host ''
}

try {
    $state = Test-ExpectedAccount
    if ($CheckOnly) {
        if ($state.IsMatch) {
            Write-AccountHeader -Color Green
            return
        }

        if ($state.Reason -eq 'mismatch') {
            Write-Host ('Account mismatch: expected {0}, found {1}' -f $accountEmail, $state.Email) -ForegroundColor Red
            return
        }

        Write-Host ('No file-based login found for {0} in {1}' -f $accountEmail, $accountHome) -ForegroundColor Red
        return
    }

    if (-not $state.IsMatch) {
        Write-AccountHeader -Color Yellow
        if ($state.Reason -eq 'mismatch') {
            Write-Warning ('Wrong account in this isolated profile: {0}' -f $state.Email)
        }
        else {
            Write-Warning 'This isolated profile is not signed in yet.'
        }

        $loginLabel = if ($Account -eq 'work') { 'browser' } else { 'device-code' }
        Write-Host ('A {0} login will start. Use the exact account shown above.' -f $loginLabel) -ForegroundColor Cyan
        Write-Host 'The desktop app and its personal login will not be changed.' -ForegroundColor Cyan
        $answer = Read-Host ('Continue with {0} login? [Y/n]' -f $loginLabel)
        if ($answer -match '^(n|no)$') {
            return
        }

        if ($state.Reason -eq 'mismatch') {
            & codex logout -c $credentialOverride
            if ($LASTEXITCODE -ne 0) {
                throw 'Failed to clear the wrong login from the isolated profile.'
            }
        }

        if ($Account -eq 'work') {
            Write-Host 'If the browser is signed in personally, choose the company account in the browser.' -ForegroundColor Cyan
            & codex login -c $credentialOverride
            if ($LASTEXITCODE -ne 0) {
                throw 'Codex browser login failed.'
            }
        }
        else {
            & codex login --device-auth -c $credentialOverride
            if ($LASTEXITCODE -ne 0) {
                Write-Warning 'Device-code login failed or is disabled.'
                $fallback = Read-Host 'Try the standard browser login instead? [Y/n]'
                if ($fallback -match '^(n|no)$') {
                    return
                }

                & codex login -c $credentialOverride
                if ($LASTEXITCODE -ne 0) {
                    throw 'Both Codex login methods failed.'
                }
            }
        }

        $state = Test-ExpectedAccount
        if (-not $state.IsMatch) {
            $found = if ($state.Email) { $state.Email } else { 'unknown account' }
            Write-Host ('Login rejected: expected {0}, found {1}. Start again and choose the correct account.' -f $accountEmail, $found) -ForegroundColor Red
            return
        }
    }

    Write-AccountHeader -Color $(if ($Account -eq 'work') { 'Cyan' } else { 'Green' })
    & codex -c $credentialOverride @CodexArgs
}
finally {
    foreach ($name in $nestedCodexEnvNames) {
        $envPath = 'Env:{0}' -f $name
        if ($previousNestedCodexEnv.ContainsKey($name)) {
            Set-Item -LiteralPath $envPath -Value $previousNestedCodexEnv[$name]
        }
        else {
            Remove-Item -LiteralPath $envPath -ErrorAction SilentlyContinue
        }
    }

    if ($hadPreviousCodexHome) {
        $env:CODEX_HOME = $previousCodexHome
    }
    else {
        Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    }
}
