# =============================================================================
# Genesis PE Daily Research - Windows Task Scheduler entry point
# =============================================================================

$ErrorActionPreference = "Stop"

$ProjectDir = "$env:USERPROFILE\pe-research"
$PromptFile = "$ProjectDir\prompts\genesis-research.md"
$LogDir     = "$ProjectDir\logs"
$LogFile    = "$LogDir\genesis-$(Get-Date -Format 'yyyy-MM-dd').log"

$env:ANTHROPIC_API_KEY = $null
$env:PATH = "$env:USERPROFILE\.local\bin;$env:APPDATA\npm;C:\Program Files\nodejs;$env:PATH"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Set-Location $ProjectDir

function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

$header = @"
================================================================
Genesis PE Daily Research Job
Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') KST
Project dir: $ProjectDir
Prompt: $PromptFile
================================================================
"@
Write-Host $header; Add-Content -Path $LogFile -Value $header

Log "[1/3] 네트워크 연결 확인..."
for ($i = 1; $i -le 10; $i++) {
    try {
        Invoke-WebRequest -Uri "https://api.anthropic.com" -TimeoutSec 5 -UseBasicParsing | Out-Null
        Log "  네트워크 OK"; break
    } catch {
        if ($i -eq 10) { Log "  ERROR: 네트워크 미연결. 종료."; exit 1 }
        Log "  네트워크 미준비 ($i/10) - 60초 후 재시도"
        Start-Sleep -Seconds 60
    }
}

Log "[2/3] Claude 인증 확인..."
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
if (-not $authOk) { Log "  ERROR: 인증 실패. 종료."; exit 2 }

Log "[3/3] Genesis 리서치 실행 시작..."
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
    Write-Host $footer; Add-Content -Path $LogFile -Value $footer; exit 0
} else {
    $footer = "`n----------------------------------------------------------------`nFAILURE. Exit code: $LASTEXITCODE. Elapsed: ${elapsed}s`nEnd: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n================================================================"
    Write-Host $footer; Add-Content -Path $LogFile -Value $footer; exit $LASTEXITCODE
}
