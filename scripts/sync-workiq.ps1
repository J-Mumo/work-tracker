# Work Tracker - Work IQ Sync Script
# Fetches meeting, email, and chat context from Work IQ CLI
# Output: JSON file with meeting history to feed into the sync prompt

param(
    [int]$DaysBack = 7,
    [string]$OutputDir = "$PSScriptRoot\.."
)

$ErrorActionPreference = "Stop"
$configFile = Join-Path $OutputDir "config.json"
$outputFile = Join-Path $OutputDir "last-workiq-input.json"

# --- Load config ---
if (-not (Test-Path $configFile)) {
    Write-Host "No config.json found. Run setup.ps1 first." -ForegroundColor Red
    exit 1
}

$config = Get-Content $configFile -Raw | ConvertFrom-Json
$workiqPath = $config.workiq_path
$userEmail = $config.user_email

if (-not $workiqPath -or -not (Test-Path $workiqPath)) {
    Write-Host "Work IQ CLI not found at '$workiqPath'. Install with: npm install -g @microsoft/workiq" -ForegroundColor Red
    exit 1
}

if (-not $DaysBack) {
    $DaysBack = if ($config.initial_sync_days) { $config.initial_sync_days } else { 7 }
}

$months = [math]::Ceiling($DaysBack / 30)
$weeksLabel = [math]::Ceiling($DaysBack / 7)

Write-Host "Fetching Work IQ signals for last $DaysBack days (~$months months)..." -ForegroundColor Cyan
Write-Host "  User: $userEmail" -ForegroundColor Gray

$allSignals = @()

# --- Meetings ---
Write-Host "`nFetching meeting updates..." -ForegroundColor Yellow

# Break into monthly chunks to avoid overly large responses
for ($i = 0; $i -lt $months; $i++) {
    $chunkEnd = (Get-Date).AddDays(-($i * 30))
    $chunkStart = $chunkEnd.AddDays(-30)
    $monthLabel = $chunkStart.ToString("MMMM yyyy")

    Write-Host "  [$monthLabel]" -ForegroundColor Gray

    $question = "What did I discuss or update on in my meetings during $monthLabel? Focus on my own statements and updates. Include specific topics, action items, and anything I said I was working on. Be concise."

    try {
        $response = & $workiqPath ask -q $question 2>$null
        if ($response) {
            $allSignals += @{
                type   = "meeting_summary"
                period = $monthLabel
                date   = $chunkEnd.ToString("yyyy-MM-dd")
                content = ($response -join "`n")
            }
            Write-Host "    Got response" -ForegroundColor Green
        } else {
            Write-Host "    No data returned" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# --- Emails ---
Write-Host "`nFetching email context..." -ForegroundColor Yellow
try {
    $emailQuestion = "What were the most important emails I sent or received in the last $months months? Focus on action items, decisions, and work commitments I made. Be concise."
    $emailResponse = & $workiqPath ask -q $emailQuestion 2>$null
    if ($emailResponse) {
        $allSignals += @{
            type    = "email_summary"
            period  = "Last $months months"
            date    = (Get-Date).ToString("yyyy-MM-dd")
            content = ($emailResponse -join "`n")
        }
        Write-Host "  Got response" -ForegroundColor Green
    } else {
        Write-Host "  No data returned" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# --- Teams Chats ---
Write-Host "`nFetching Teams chat context..." -ForegroundColor Yellow
try {
    $chatQuestion = "What were the most important Teams messages or chats I was involved in over the last $months months? Focus on decisions, action items, and work topics. Be concise."
    $chatResponse = & $workiqPath ask -q $chatQuestion 2>$null
    if ($chatResponse) {
        $allSignals += @{
            type    = "chat_summary"
            period  = "Last $months months"
            date    = (Get-Date).ToString("yyyy-MM-dd")
            content = ($chatResponse -join "`n")
        }
        Write-Host "  Got response" -ForegroundColor Green
    } else {
        Write-Host "  No data returned" -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# --- Output ---
$output = @{
    collected_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    days_back    = $DaysBack
    signals      = @($allSignals)
}

$output | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile -Encoding UTF8
Write-Host "`nOutput written to: $outputFile" -ForegroundColor Green
Write-Host "  Signals collected: $($allSignals.Count)" -ForegroundColor Cyan
