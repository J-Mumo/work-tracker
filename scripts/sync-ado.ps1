# Work Tracker - ADO Sync Script
# Pulls PRs, work items, and commits for the current user
# Supports multiple repositories and ADO projects from config.json
# Output: JSON fragments to feed into the sync prompt

param(
    [int]$DaysBack,
    [string]$OutputDir = "$PSScriptRoot\.."
)

$ErrorActionPreference = "Stop"
$configFile = Join-Path $OutputDir "config.json"
$outputFile = Join-Path $OutputDir "last-sync-input.json"

# --- Load config ---
if (-not (Test-Path $configFile)) {
    Write-Host "No config.json found. Run setup.ps1 first." -ForegroundColor Red
    exit 1
}

$config = Get-Content $configFile -Raw | ConvertFrom-Json

if (-not $DaysBack) {
    $DaysBack = if ($config.initial_sync_days) { $config.initial_sync_days } else { 7 }
}

$sinceDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-dd")
$gitAuthor = $config.git_author
$userEmail = $config.user_email
$adoOrg    = $config.ado_org
$adoRepos  = @($config.repositories)
$adoProjects = @($config.ado_projects)

Write-Host "Gathering signals for last $DaysBack days (since $sinceDate)..." -ForegroundColor Cyan
Write-Host "  User: $userEmail" -ForegroundColor Gray
Write-Host "  Repos: $($adoRepos.Count)  |  Projects: $($adoProjects.Count)" -ForegroundColor Gray

$allPRs = @()
$allWIs = @()
$allCommits = @()

# --- Pull Requests (per project x repo) ---
Write-Host "`nFetching PRs..." -ForegroundColor Yellow
foreach ($project in $adoProjects) {
    foreach ($repo in $adoRepos) {
        Write-Host "  [$project / $($repo.name)]" -ForegroundColor Gray
        try {
            $prs = az repos pr list `
                --repository $repo.name `
                --project $project `
                --organization $adoOrg `
                --creator $userEmail `
                --status all `
                --output json 2>$null | ConvertFrom-Json

            $matched = $prs | Where-Object {
                [datetime]$_.creationDate -ge [datetime]$sinceDate
            } | ForEach-Object {
                @{
                    type    = "pull_request"
                    source  = "PR #$($_.pullRequestId)"
                    date    = ([datetime]$_.creationDate).ToString("yyyy-MM-dd")
                    snippet = "$($_.title) [$($_.status)]"
                    url     = "$($_.repository.webUrl)/pullrequest/$($_.pullRequestId)"
                    project = $project
                    repo    = $repo.name
                }
            }
            $allPRs += @($matched)
        } catch {
            Write-Host "    (skipped -- no access or repo not found)" -ForegroundColor DarkYellow
        }
    }
}
Write-Host "  Total PRs: $($allPRs.Count)" -ForegroundColor Green

# --- Work Items (per project) ---
Write-Host "`nFetching work items..." -ForegroundColor Yellow
foreach ($project in $adoProjects) {
    Write-Host "  [$project]" -ForegroundColor Gray
    try {
        $wiql = "SELECT [System.Id], [System.Title], [System.State], [System.ChangedDate] FROM workitems WHERE [System.AssignedTo] = @Me AND [System.ChangedDate] >= '$sinceDate' ORDER BY [System.ChangedDate] DESC"

        $workItems = az boards query `
            --wiql $wiql `
            --project $project `
            --organization $adoOrg `
            --output json 2>$null | ConvertFrom-Json

        $matched = $workItems | ForEach-Object {
            @{
                type    = "work_item"
                source  = "WI #$($_.fields.'System.Id')"
                date    = ([datetime]$_.fields.'System.ChangedDate').ToString("yyyy-MM-dd")
                snippet = "$($_.fields.'System.Title') [$($_.fields.'System.State')]"
                project = $project
            }
        }
        $allWIs += @($matched)
    } catch {
        Write-Host "    (skipped -- no access)" -ForegroundColor DarkYellow
    }
}
Write-Host "  Total work items: $($allWIs.Count)" -ForegroundColor Green

# --- Git Commits (per repo with local path) ---
Write-Host "`nFetching commits..." -ForegroundColor Yellow
foreach ($repo in $adoRepos) {
    if (-not $repo.path) {
        Write-Host "  [$($repo.name)] (no local path -- skipping commits)" -ForegroundColor DarkYellow
        continue
    }
    Write-Host "  [$($repo.name)]" -ForegroundColor Gray
    try {
        $gitLog = git -C $repo.path log `
            --author="$gitAuthor" `
            --since="$sinceDate" `
            --pretty=format:"%H|%ad|%s" `
            --date=short 2>$null

        if ($gitLog) {
            $matched = ($gitLog -split "`n") | ForEach-Object {
                $parts = $_ -split "\|", 3
                if ($parts.Count -eq 3) {
                    @{
                        type   = "commit"
                        source = $parts[0].Substring(0, 7)
                        date   = $parts[1]
                        snippet = $parts[2]
                        repo   = $repo.name
                    }
                }
            }
            $allCommits += @($matched)
        }
    } catch {
        Write-Host "    (skipped -- git error)" -ForegroundColor DarkYellow
    }
}
Write-Host "  Total commits: $($allCommits.Count)" -ForegroundColor Green

# --- Combine & Output ---
$output = @{
    collected_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    days_back    = $DaysBack
    repositories = @($adoRepos | ForEach-Object { $_.name })
    projects     = @($adoProjects)
    signals      = @{
        pull_requests = @($allPRs)
        work_items    = @($allWIs)
        commits       = @($allCommits)
    }
}

$output | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile -Encoding UTF8
Write-Host "`nOutput written to: $outputFile" -ForegroundColor Green
Write-Host "  PRs: $($allPRs.Count)  |  Work Items: $($allWIs.Count)  |  Commits: $($allCommits.Count)" -ForegroundColor Cyan
