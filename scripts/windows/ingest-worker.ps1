# =============================================================================
# Brain Vault Ingest Worker - Windows
# =============================================================================
# 큐(pending/*.json)를 스캔해 Obsidian vault에 ingest.
# Task Scheduler: 평일 09:30/14:00/21:00 + 로그인 시 즉시 실행.
# =============================================================================

$ErrorActionPreference = "Stop"

$ProjectDir  = "$env:USERPROFILE\pe-research"
$QueueDir    = "$ProjectDir\ingest-queue"
$PendingDir  = "$QueueDir\pending"
$DoneDir     = "$QueueDir\done"
$FailedDir   = "$QueueDir\failed"
$PromptTmpl  = "$ProjectDir\prompts\ingest-daily.md"
# Windows Obsidian vault 경로 — 실제 경로로 수정 필요
$VaultDir    = "$env:USERPROFILE\Documents\Brain"
$LogDir      = "$ProjectDir\logs"
$LogFile     = "$LogDir\ingest-$(Get-Date -Format 'yyyy-MM-dd').log"

$env:ANTHROPIC_API_KEY = $null
$env:PATH = "$env:USERPROFILE\.local\bin;$env:APPDATA\npm;C:\Program Files\nodejs;$env:PATH"

New-Item -ItemType Directory -Force -Path $LogDir, $PendingDir, $DoneDir, $FailedDir | Out-Null
Set-Location $ProjectDir

function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

$header = @"
================================================================
Brain Vault Ingest Worker
Start: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') KST
Queue: $PendingDir
Vault: $VaultDir
================================================================
"@
Write-Host $header; Add-Content -Path $LogFile -Value $header

# --- 큐 확인 ---
$pendingFiles = Get-ChildItem "$PendingDir\*.json" -ErrorAction SilentlyContinue
if (-not $pendingFiles) { Log "큐 비어있음. 종료."; exit 0 }
$pendingCount = $pendingFiles.Count
Log "처리 대기: $pendingCount 건"

# --- 네트워크 확인 ---
Log "[1/4] 네트워크 연결 확인..."
for ($i = 1; $i -le 10; $i++) {
    try {
        Invoke-WebRequest -Uri "https://api.anthropic.com" -TimeoutSec 5 -UseBasicParsing | Out-Null
        Log "  네트워크 OK"; break
    } catch {
        if ($i -eq 10) { Log "  ERROR: 네트워크 미연결. 종료(큐 보존)."; exit 1 }
        Log "  네트워크 미준비 ($i/10) - 60초 후 재시도"
        Start-Sleep -Seconds 60
    }
}

# --- Vault 접근 확인 ---
Log "[2/4] Vault 접근 확인..."
if (-not (Test-Path $VaultDir)) { Log "  ERROR: vault 경로 없음. `$VaultDir 확인 필요."; exit 2 }
$testFile = "$VaultDir\.write-test-$$"
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
if (-not $authOk) { Log "  ERROR: 인증 실패. 종료(큐 보존)."; exit 4 }

# --- 큐 처리 ---
Log "[4/4] 큐 처리 시작..."
$processed = 0; $success = 0; $failed = 0

foreach ($qFile in $pendingFiles) {
    $processed++
    Log "  [$processed/$pendingCount] $($qFile.Name) 처리 중..."

    $itemLog  = "$LogDir\ingest-item-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$($qFile.Name).log"
    $combined = New-TemporaryFile

    try {
        $promptContent = Get-Content $PromptTmpl -Raw
        $jsonContent   = Get-Content $qFile.FullName -Raw
        "$promptContent`n``````json`n$jsonContent`n``````" | Out-File $combined -Encoding utf8

        Get-Content $combined | claude `
            --print `
            --dangerously-skip-permissions `
            --mcp-config "$ProjectDir\.mcp.json" `
            --add-dir "$ProjectDir" `
            --add-dir "$VaultDir" `
            2>&1 | Out-File $itemLog -Encoding utf8

        $itemLogContent = Get-Content $itemLog -Raw
        if ($itemLogContent -match "status=success|status=already_ingested") {
            Move-Item $qFile.FullName "$DoneDir\" -Force
            $success++
            Log "    ✓ 성공 → done/"
        } else {
            Move-Item $qFile.FullName "$FailedDir\" -Force
            $failed++
            Log "    ✗ 마커 누락 → failed/"
        }
    } catch {
        Move-Item $qFile.FullName "$FailedDir\" -Force -ErrorAction SilentlyContinue
        $failed++
        Log "    ✗ 오류: $_"
    } finally {
        Remove-Item $combined -ErrorAction SilentlyContinue
    }
}

$footer = "`n----------------------------------------------------------------`n처리 완료: $processed건 (성공 $success / 실패 $failed)`nEnd: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n================================================================"
Write-Host $footer; Add-Content -Path $LogFile -Value $footer

exit $(if ($failed -gt 0) { 1 } else { 0 })
