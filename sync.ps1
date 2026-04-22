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
Write-Host "`nStep 3/3: Merging signals into workstreams..." -ForegroundColor Yellow

# Backup current workstreams before any changes
$backupFile = Join-Path $root "workstreams.backup.json"
Copy-Item $wsFile $backupFile -Force -ErrorAction SilentlyContinue

$currentWorkstreams = Get-Content $wsFile -Raw -ErrorAction SilentlyContinue
if (-not $currentWorkstreams) {
    $currentWorkstreams = "{`"owner`": `"$($config.user_email)`", `"last_synced`": null, `"workstreams`": []}"
}

$syncRules = Get-Content $syncPromptFile -Raw
$today = Get-Date -Format 'yyyy-MM-dd'
$mergeSteps = @()

# Build merge batches from ADO signals
if (Test-Path $adoInput) {
    $adoData = Get-Content $adoInput -Raw | ConvertFrom-Json
    $prSignals = @($adoData.signals.pull_requests)
    $wiSignals = @($adoData.signals.work_items)
    $commitSignals = @($adoData.signals.commits)

    if ($prSignals.Count -gt 0) {
        $mergeSteps += @{
            label = "ADO Pull Requests ($($prSignals.Count))"
            data  = ($prSignals | ConvertTo-Json -Depth 4 -Compress)
        }
    }
    if ($wiSignals.Count -gt 0) {
        $mergeSteps += @{
            label = "ADO Work Items ($($wiSignals.Count))"
            data  = ($wiSignals | ConvertTo-Json -Depth 4 -Compress)
        }
    }
    if ($commitSignals.Count -gt 0) {
        $mergeSteps += @{
            label = "Git Commits ($($commitSignals.Count))"
            data  = ($commitSignals | ConvertTo-Json -Depth 4 -Compress)
        }
    }
}

# Build merge batches from Work IQ signals (one per signal)
if (Test-Path $wiqInput) {
    $wiqData = Get-Content $wiqInput -Raw | ConvertFrom-Json
    foreach ($signal in @($wiqData.signals)) {
        $mergeSteps += @{
            label = "Work IQ: $($signal.type) ($($signal.period))"
            data  = ($signal | ConvertTo-Json -Depth 4 -Compress)
        }
    }
}

if ($mergeSteps.Count -eq 0) {
    Write-Host "  No signals to merge." -ForegroundColor DarkYellow
    exit 0
}

Write-Host "  Processing $($mergeSteps.Count) signal batches..." -ForegroundColor Gray

# Helper function to send a merge chunk and get updated workstreams
function Invoke-MergeChunk {
    param($WorkiqPath, $CurrentWS, $SignalData, $Rules, $Owner, $Today)

    $prompt = @"
You are a work-tracking agent. Update the workstreams JSON below by merging in the new signals.

Rules (summary):
- Match signals to existing workstreams by topic, keywords, service names, or incident IDs
- Create new workstreams for unmatched signals
- Update last_updated and append to evidence for matches
- Status: active (7 days), cooling (7-14 days), dormant (older)
- Keep evidence snippets to 1-2 sentences
- Never delete workstreams

Current workstreams:
$CurrentWS

New signals to merge:
$SignalData

Return ONLY the updated JSON (with owner "$Owner" and last_synced "$Today"). No markdown fences, no explanation.
"@

    $response = & $WorkiqPath ask -q $prompt 2>$null
    return $response
}

$stepNum = 0
$failedSteps = @()

foreach ($step in $mergeSteps) {
    $stepNum++
    Write-Host "  [$stepNum/$($mergeSteps.Count)] $($step.label)..." -ForegroundColor Gray -NoNewline

    try {
        $response = Invoke-MergeChunk `
            -WorkiqPath $workiqPath `
            -CurrentWS $currentWorkstreams `
            -SignalData $step.data `
            -Rules $syncRules `
            -Owner $config.user_email `
            -Today $today

        if (-not $response) {
            Write-Host " no response" -ForegroundColor DarkYellow
            $failedSteps += $step.label
            continue
        }

        $responseText = ($response -join "`n").Trim()

        # Extract JSON if wrapped in markdown fences
        if ($responseText -match '(?s)```(?:json)?\s*(\{.+\})\s*```') {
            $responseText = $Matches[1]
        }

        # Validate JSON
        $parsed = $responseText | ConvertFrom-Json
        if ($null -eq $parsed.workstreams) {
            throw "Missing 'workstreams' field"
        }

        # Update current workstreams for next iteration
        $currentWorkstreams = $responseText
        Write-Host " ok ($(@($parsed.workstreams).Count) workstreams)" -ForegroundColor Green

    } catch {
        Write-Host " error: $($_.Exception.Message)" -ForegroundColor DarkYellow
        $failedSteps += $step.label
        # Save failed response for debugging
        if ($responseText) {
            $responseText | Set-Content -Path (Join-Path $root "last-merge-response-step$stepNum.txt") -Encoding UTF8
        }
        # Continue with unchanged workstreams for next step
    }
}

# Write final result
$currentWorkstreams | Set-Content -Path $wsFile -Encoding UTF8

# Parse final state for summary
try {
    $final = $currentWorkstreams | ConvertFrom-Json
    $wsCount = @($final.workstreams).Count
    $activeCount = @($final.workstreams | Where-Object { $_.status -eq "active" }).Count
    $coolingCount = @($final.workstreams | Where-Object { $_.status -eq "cooling" }).Count
    $dormantCount = @($final.workstreams | Where-Object { $_.status -eq "dormant" }).Count
} catch {
    $wsCount = "?"
    $activeCount = "?"
    $coolingCount = "?"
    $dormantCount = "?"
}

Write-Host ""
Write-Host "=== Sync Complete ===" -ForegroundColor Cyan
Write-Host "  Total workstreams: $wsCount" -ForegroundColor White
Write-Host "  Active: $activeCount  |  Cooling: $coolingCount  |  Dormant: $dormantCount" -ForegroundColor White
Write-Host "  Backup: workstreams.backup.json" -ForegroundColor Gray

if ($failedSteps.Count -gt 0) {
    Write-Host "  Warning: $($failedSteps.Count) batch(es) failed to merge:" -ForegroundColor DarkYellow
    foreach ($f in $failedSteps) {
        Write-Host "    - $f" -ForegroundColor DarkYellow
    }
    Write-Host "  Re-run sync or merge manually in Copilot chat." -ForegroundColor DarkYellow
}
