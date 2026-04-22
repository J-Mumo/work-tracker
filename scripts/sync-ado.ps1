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
$adoRepos  = @($config.repositories)

# Support both old (single org) and new (multi-org) config formats
$adoOrgsList = @()
if ($config.ado_orgs) {
    $adoOrgsList = @($config.ado_orgs)
} elseif ($config.ado_org) {
    $adoOrgsList = @(@{ org = $config.ado_org; projects = @($config.ado_projects) })
}

$totalProjects = ($adoOrgsList | ForEach-Object { @($_.projects).Count } | Measure-Object -Sum).Sum
Write-Host "Gathering signals for last $DaysBack days (since $sinceDate)..." -ForegroundColor Cyan
Write-Host "  User: $userEmail" -ForegroundColor Gray
Write-Host "  Repos: $($adoRepos.Count)  |  ADO orgs: $($adoOrgsList.Count)  |  Projects: $totalProjects" -ForegroundColor Gray

$allPRs = @()
$allWIs = @()
$allCommits = @()

# --- Pull Requests (per org x project x repo) ---
Write-Host "`nFetching PRs..." -ForegroundColor Yellow
foreach ($orgEntry in $adoOrgsList) {
    $org = $orgEntry.org
    foreach ($project in @($orgEntry.projects)) {
        foreach ($repo in $adoRepos) {
            Write-Host "  [$org / $project / $($repo.name)]" -ForegroundColor Gray
            try {
                $prs = az repos pr list `
                    --repository $repo.name `
                    --project $project `
                    --organization $org `
                    --creator $userEmail `
                    --status all `
                    --top 1000 `
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
                        org     = $org
                    }
                }
                $allPRs += @($matched)
            } catch {
                Write-Host "    (skipped -- no access or repo not found)" -ForegroundColor DarkYellow
            }
        }
    }
}
Write-Host "  Total PRs: $($allPRs.Count)" -ForegroundColor Green

# --- Work Items (per org x project) ---
Write-Host "`nFetching work items..." -ForegroundColor Yellow
foreach ($orgEntry in $adoOrgsList) {
    $org = $orgEntry.org
    foreach ($project in @($orgEntry.projects)) {
        Write-Host "  [$org / $project]" -ForegroundColor Gray
        try {
            $wiql = "SELECT [System.Id], [System.Title], [System.State], [System.ChangedDate] FROM workitems WHERE [System.AssignedTo] = @Me AND [System.ChangedDate] >= '$sinceDate' ORDER BY [System.ChangedDate] DESC"

            $workItems = az boards query `
                --wiql $wiql `
                --project $project `
                --organization $org `
                --output json 2>$null | ConvertFrom-Json

            $matched = $workItems | ForEach-Object {
                @{
                    type    = "work_item"
                    source  = "WI #$($_.fields.'System.Id')"
                    date    = ([datetime]$_.fields.'System.ChangedDate').ToString("yyyy-MM-dd")
                    snippet = "$($_.fields.'System.Title') [$($_.fields.'System.State')]"
                    project = $project
                    org     = $org
                }
            }
            $allWIs += @($matched)
        } catch {
            Write-Host "    (skipped -- no access)" -ForegroundColor DarkYellow
        }
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
            --pretty=format:"%H<SEP>%ad<SEP>%s" `
            --date=short 2>$null

        if ($gitLog) {
            $matched = ($gitLog -split "`n") | ForEach-Object {
                $parts = $_ -split "<SEP>", 3
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
