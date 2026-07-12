# =============================================================================
# PE Daily Research - Windows Task Scheduler entry point
# =============================================================================
# Task Scheduler가 매일 평일 08:45 KST에 호출.
# Claude Code headless로 리서치 리포트 생성 후 Notion에 저장.
# =============================================================================

$ErrorActionPreference = "Stop"

# --- Config ---
$ProjectDir = "$env:USERPROFILE\pe-research"
$PromptFile = "$ProjectDir\prompts\daily-research.md"
$LogDir     = "$ProjectDir\logs"
$LogFile    = "$LogDir\$(Get-Date -Format 'yyyy-MM-dd').log"

# --- Environment ---
# CRITICAL: unset ANTHROPIC_API_KEY → Claude CLI uses subscription OAuth
$env:ANTHROPIC_API_KEY = $null
$env:PATH = "$env:USERPROFILE\.local\bin;$env:APPDATA\npm;C:\Program Files\nodejs;$env:PATH"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Location $ProjectDir

function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

# --- Log header ---
$header = @"
================================================================
PE Daily Research Job
Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') KST
Project dir: $ProjectDir
================================================================
"@
Write-Host $header
Add-Content -Path $LogFile -Value $header

# --- Step 1: 네트워크 대기 (최대 10분) ---
Log "[1/3] 네트워크 연결 확인..."
$networkOk = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        Invoke-WebRequest -Uri "https://api.anthropic.com" -TimeoutSec 5 -UseBasicParsing | Out-Null
        Log "  네트워크 OK"
        $networkOk = $true
        break
    } catch {
        if ($i -eq 10) {
            Log "  ERROR: 10분 대기 후에도 네트워크 미연결. 종료."
            exit 1
        }
        Log "  네트워크 미준비 ($i/10) - 60초 후 재시도"
        Start-Sleep -Seconds 60
    }
}

# --- Step 2: Claude 인증 확인 (최대 3회) ---
Log "[2/3] Claude 인증 확인..."
$authOk = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $authTest = "ping" | claude --print --dangerously-skip-permissions 2>&1
        if ($LASTEXITCODE -eq 0 -and $authTest -notmatch "authentication_error|invalid.*credentials|401|please.*log.*in") {
            Log "  인증 OK (응답: $($authTest.ToString().Substring(0, [Math]::Min(50, $authTest.ToString().Length)))...)"
            $authOk = $true
            break
        }
    } catch {}
    Log "  인증 실패 시도 $attempt/3"
    if ($attempt -lt 3) {
        Log "  3분 대기 후 재시도"
        Start-Sleep -Seconds 180
    }
}
if (-not $authOk) {
    Log "  ERROR: 3회 시도 모두 실패. 'claude login' 실행하여 재로그인 필요."
    exit 2
}

# --- Step 3: 리서치 실행 ---
Log "[3/3] 리서치 실행 시작..."
$startTime = Get-Date

Get-Content $PromptFile | claude `
    --print `
    --dangerously-skip-permissions `
    --mcp-config "$ProjectDir\.mcp.json" `
    --add-dir "$ProjectDir" `
    2>&1 | Tee-Object -FilePath $LogFile -Append

$elapsed = [int]((Get-Date) - $startTime).TotalSeconds
if ($LASTEXITCODE -eq 0) {
    $footer = "`n----------------------------------------------------------------`nSUCCESS. Elapsed: ${elapsed}s`nEnd: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n================================================================"
    Write-Host $footer; Add-Content -Path $LogFile -Value $footer
    exit 0
} else {
    $footer = "`n----------------------------------------------------------------`nFAILURE. Exit code: $LASTEXITCODE. Elapsed: ${elapsed}s`nEnd: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n================================================================"
    Write-Host $footer; Add-Content -Path $LogFile -Value $footer
    exit $LASTEXITCODE
}
