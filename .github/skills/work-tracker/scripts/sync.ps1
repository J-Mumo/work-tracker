# Work Tracker - Unified Sync
# Collects all signals (ADO + Work IQ), then merges into workstreams.json
# Run this before standup or at end of day.

param(
    [int]$DaysBack = 7
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$configFile = Join-Path $root "config.json"
$wsFile = Join-Path $root "workstreams.json"
$adoInput = Join-Path $root "last-sync-input.json"
$wiqInput = Join-Path $root "last-workiq-input.json"
$syncPromptFile = Join-Path $root "prompts" "sync.md"

if (-not (Test-Path $configFile)) {
    Write-Host "No config.json found. Run setup.ps1 first." -ForegroundColor Red
    exit 1
}

$config = Get-Content $configFile -Raw | ConvertFrom-Json
$workiqPath = $config.workiq_path

Write-Host "=== Work Tracker Sync ===" -ForegroundColor Cyan
Write-Host "  Looking back $DaysBack days" -ForegroundColor Gray
Write-Host ""

# --- Step 1: Collect ADO signals ---
Write-Host "Step 1/3: Collecting ADO signals..." -ForegroundColor Yellow
$adoScript = Join-Path $root "scripts" "sync-ado.ps1"
& $adoScript -DaysBack $DaysBack

# --- Step 2: Collect Work IQ signals ---
if ($workiqPath -and (Test-Path $workiqPath)) {
    Write-Host "`nStep 2/3: Collecting Work IQ signals..." -ForegroundColor Yellow
    $wiqScript = Join-Path $root "scripts" "sync-workiq.ps1"
    & $wiqScript -DaysBack $DaysBack
} else {
    Write-Host "`nStep 2/3: Skipping Work IQ (CLI not found)." -ForegroundColor DarkYellow
}

# --- Step 3: Merge into workstreams.json (chunked) ---
Write-Host "`nStep 3/3: Preparing merge..." -ForegroundColor Yellow

# Backup current workstreams
$backupFile = Join-Path $root "workstreams.backup.json"
Copy-Item $wsFile $backupFile -Force -ErrorAction SilentlyContinue

# Clean Work IQ signals: strip ANSI codes, URLs, compress whitespace
$cleanedSignals = @()
if (Test-Path $wiqInput) {
    $wiqData = Get-Content $wiqInput -Raw | ConvertFrom-Json
    foreach ($signal in @($wiqData.signals)) {
        $cleaned = $signal.content -replace '\x1b\][^\x07]*\x07', '' `
                                   -replace '\x1b\[[0-9;]*[a-zA-Z]', '' `
                                   -replace '\x1b\\', '' `
                                   -replace 'https?://[^\s\)]+', '' `
                                   -replace '\s{2,}', ' '
        $cleanedSignals += @{
            type    = $signal.type
            period  = $signal.period
            date    = $signal.date
            content = $cleaned.Trim()
        }
    }
}

# Build the merge input file (cleaned, ready for Copilot MCP)
$mergeInput = @{
    collected_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    ado_signals  = @{}
    workiq_signals = @($cleanedSignals)
}

if (Test-Path $adoInput) {
    $adoData = Get-Content $adoInput -Raw | ConvertFrom-Json
    $mergeInput.ado_signals = $adoData.signals
}

$mergeInputFile = Join-Path $root "last-merge-input.json"
$mergeInput | ConvertTo-Json -Depth 5 | Set-Content -Path $mergeInputFile -Encoding UTF8

Write-Host "  Merge input saved to: last-merge-input.json" -ForegroundColor Green
Write-Host "  Backup saved to: workstreams.backup.json" -ForegroundColor Green

# --- Summary ---
$adoCount = @($mergeInput.ado_signals.pull_requests).Count + @($mergeInput.ado_signals.work_items).Count + @($mergeInput.ado_signals.commits).Count
$wiqCount = $cleanedSignals.Count

Write-Host ""
Write-Host "=== Collection Complete ===" -ForegroundColor Cyan
Write-Host "  ADO signals: $adoCount" -ForegroundColor White
Write-Host "  Work IQ signals: $wiqCount" -ForegroundColor White
Write-Host ""
Write-Host "To complete the merge, ask Copilot:" -ForegroundColor White
Write-Host '  "Merge the signals from last-merge-input.json into workstreams.json using the sync prompt in prompts/sync.md"' -ForegroundColor Yellow
