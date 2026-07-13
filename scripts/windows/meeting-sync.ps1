# =============================================================================
# Meeting Notes Sync - Windows (Notion 회의록 -> Brain Vault)
# =============================================================================
# 매일 1회 fire. checkpoint(state\meeting-sync-state.json) 이후 신규 회의록을
# 조회하여 업무(PE) 관련 항목만 vault에 ingest. 개인 항목은 자동 제외.
# Task Scheduler: 매일 22:30 + 로그인 시 즉시 실행.
# =============================================================================

$ErrorActionPreference = "Stop"

$ProjectDir  = "$env:USERPROFILE\pe-research"
$PromptFile  = "$ProjectDir\prompts\meeting-sync.md"
# Windows Obsidian vault 경로 — ingest-worker.ps1과 동일한 자동 탐지 (첫 번째로 존재하는 경로)
$VaultCandidates = @(
    "$env:USERPROFILE\iCloudDrive\iCloud~md~obsidian\Brain",
    "$env:USERPROFILE\Documents\Brain",
    "$env:USERPROFILE\OneDrive\Documents\Brain"
)
$VaultDir = $VaultCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $VaultDir) { $VaultDir = $VaultCandidates[0] }
$LogDir      = "$ProjectDir\logs"
$LogFile     = "$LogDir\meeting-sync-$(Get-Date -Format 'yyyy-MM-dd').log"

$env:ANTHROPIC_API_KEY = $null
$env:PATH = "$env:USERPROFILE\.local\bin;$env:APPDATA\npm;C:\Program Files\nodejs;$env:PATH"

New-Item -ItemType Directory -Force -Path $LogDir, "$ProjectDir\state" | Out-Null
Set-Location $ProjectDir

function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

$header = @"
================================================================
Meeting Notes Sync
Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Vault: $VaultDir
================================================================
"@
Write-Host $header; Add-Content -Path $LogFile -Value $header

# --- 네트워크 확인 ---
Log "[1/4] 네트워크 연결 확인..."
for ($i = 1; $i -le 10; $i++) {
    try {
        Invoke-WebRequest -Uri "https://api.anthropic.com" -TimeoutSec 5 -UseBasicParsing -Method Head | Out-Null
        Log "  네트워크 OK"; break
    } catch {
        if ($_.Exception.Response) { Log "  네트워크 OK (HTTP 응답 수신)"; break }
        if ($i -eq 10) { Log "  ERROR: 네트워크 미연결. 종료."; exit 1 }
        Log "  네트워크 미준비 ($i/10) - 60초 후 재시도"
        Start-Sleep -Seconds 60
    }
}

# --- Vault 접근 확인 ---
Log "[2/4] Vault 접근 확인..."
if (-not (Test-Path $VaultDir)) { Log "  ERROR: vault 경로 없음. `$VaultDir 확인 필요."; exit 2 }
$testFile = "$VaultDir\.meeting-sync-write-test-$PID"
try { "" | Out-File $testFile; Remove-Item $testFile } catch { Log "  ERROR: vault 쓰기 실패."; exit 3 }
Log "  vault 쓰기 OK"

# --- 인증 확인 ---
Log "[3/4] Claude 인증 확인..."
$authOk = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $authTest = "ping" | claude --print --dangerously-skip-permissions 2>&1
        if ($LASTEXITCODE -eq 0 -and $authTest -notmatch "authentication_error|401") {
            Log "  인증 OK"; $authOk = $true; break
        }
    } catch {}
    Log "  인증 실패 $attempt/3"
    if ($attempt -lt 3) { Start-Sleep -Seconds 180 }
}
if (-not $authOk) { Log "  ERROR: 인증 실패. 종료."; exit 4 }

# --- Claude 헤드리스 실행 ---
Log "[4/4] Claude 헤드리스 실행..."
$runLog = "$LogDir\meeting-sync-item-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$exitCode = 0

try {
    Get-Content $PromptFile -Raw | claude `
        --print `
        --dangerously-skip-permissions `
        --mcp-config "$ProjectDir\.mcp.json" `
        --add-dir "$ProjectDir" `
        --add-dir "$VaultDir" `
        2>&1 | Out-File $runLog -Encoding utf8

    $runLogContent = Get-Content $runLog -Raw
    if ($runLogContent -match "status=success|status=no_new_items") {
        Log "  ✓ 성공 — 로그: $runLog"
        ($runLogContent -split "`n" | Select-String -Pattern "===SYNC_RESULT===" -Context 0,8) | ForEach-Object { Add-Content -Path $LogFile -Value $_.ToString() }
    } else {
        Log "  ✗ 완료 마커 누락 — 로그 확인 필요: $runLog"
        $exitCode = 1
    }
} catch {
    Log "  ✗ 오류: $_"
    $exitCode = 1
}

$footer = "`n----------------------------------------------------------------`nEnd: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n================================================================"
Write-Host $footer; Add-Content -Path $LogFile -Value $footer

exit $exitCode
