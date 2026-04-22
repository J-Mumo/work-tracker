# Work Tracker - Setup Script
# Detects user identity and configures the work tracker for first use.
# Supports multiple repositories and ADO projects.

param(
    [string]$ReposFolder,
    [string[]]$Repositories,
    [string]$AdoOrg,
    [string[]]$AdoProjects,
    [hashtable[]]$AdoOrgs,
    [int]$InitialSyncDays = 180
)

$ErrorActionPreference = "Stop"
$configFile = Join-Path $PSScriptRoot "config.json"

Write-Host "=== Work Tracker Setup ===" -ForegroundColor Cyan
Write-Host ""

# --- Detect user email ---
Write-Host "Detecting user identity..." -ForegroundColor Yellow
$userEmail = $null

try {
    $userEmail = az account show --query user.name -o tsv 2>$null
} catch {}

if (-not $userEmail) {
    try {
        $userEmail = git config user.email 2>$null
    } catch {}
}

if (-not $userEmail) {
    $userEmail = Read-Host "Could not detect your email. Please enter it"
}

Write-Host "  User: $userEmail" -ForegroundColor Green

# --- Detect git author name (for commit queries) ---
$gitAuthor = $null
try {
    $gitAuthor = git config user.name 2>$null
} catch {}
if (-not $gitAuthor) {
    $gitAuthor = ($userEmail -split "@")[0]
}
Write-Host "  Git author: $gitAuthor" -ForegroundColor Green

# --- Repositories (scan folder or manual) ---
$repos = @()

# Helper: extract repo name from a git folder
function Get-RepoInfo($repoPath) {
    $name = $null
    try {
        $remote = git -C $repoPath remote get-url origin 2>$null
        if ($remote -match "/_git/([^/]+)$") {
            $name = $Matches[1]
        } elseif ($remote -match "/([^/]+?)(?:\.git)?$") {
            $name = $Matches[1]
        }
    } catch {}
    if (-not $name) { $name = Split-Path $repoPath -Leaf }
    return @{ name = $name; path = $repoPath }
}

if ($Repositories) {
    # Explicit repo names passed as params (no local paths)
    foreach ($r in $Repositories) {
        $repos += @{ name = $r; path = $null }
    }
} else {
    # Detect or ask for repos folder
    if (-not $ReposFolder) {
        # Try to detect: parent of current git repo, or parent of script location
        $detectedFolder = $null
        try {
            $gitRoot = git rev-parse --show-toplevel 2>$null
            if ($gitRoot) {
                $detectedFolder = Split-Path $gitRoot -Parent
            }
        } catch {}

        if (-not $detectedFolder) {
            $detectedFolder = Split-Path $PSScriptRoot -Parent
        }

        if ($detectedFolder -and (Test-Path $detectedFolder)) {
            $useDetected = Read-Host "Use '$detectedFolder' as the folder containing your repos? (Y/n)"
            if ($useDetected -eq "" -or $useDetected -match "^[Yy]") {
                $ReposFolder = $detectedFolder
            }
        }

        if (-not $ReposFolder) {
            $ReposFolder = Read-Host "Enter the folder path that contains your git repositories"
        }
    }

    if (-not (Test-Path $ReposFolder)) {
        Write-Host "Folder not found: $ReposFolder" -ForegroundColor Red
        exit 1
    }

    Write-Host "  Scanning '$ReposFolder' for git repositories..." -ForegroundColor Yellow

    # Scan subfolders for git repos
    $candidates = Get-ChildItem -Path $ReposFolder -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName ".git")
    }

    if ($candidates.Count -eq 0) {
        Write-Host "  No git repositories found in '$ReposFolder'." -ForegroundColor Red
        $manualRepo = Read-Host "Enter a repository name manually"
        $repos += @{ name = $manualRepo; path = $null }
    } else {
        Write-Host "  Found $($candidates.Count) git repositories:" -ForegroundColor Green
        foreach ($c in $candidates) {
            $info = Get-RepoInfo $c.FullName
            Write-Host "    [$($info.name)] $($c.FullName)" -ForegroundColor Gray
        }
        Write-Host ""

        $selectAll = Read-Host "Add all $($candidates.Count) repositories? (Y/n)"
        if ($selectAll -eq "" -or $selectAll -match "^[Yy]") {
            foreach ($c in $candidates) {
                $repos += Get-RepoInfo $c.FullName
            }
        } else {
            foreach ($c in $candidates) {
                $info = Get-RepoInfo $c.FullName
                $include = Read-Host "  Include '$($info.name)'? (Y/n)"
                if ($include -eq "" -or $include -match "^[Yy]") {
                    $repos += $info
                }
            }
        }
    }

    # Option to add more manually
    $addMore = Read-Host "Add any additional repo names not in that folder? (y/N)"
    while ($addMore -match "^[Yy]") {
        $newRepo = Read-Host "  Repository name"
        if ($newRepo -eq "") { break }
        $repos += @{ name = $newRepo; path = $null }
        $addMore = Read-Host "  Add another? (y/N)"
    }
}

Write-Host "  Repositories ($($repos.Count)):" -ForegroundColor Green
foreach ($r in $repos) {
    $pathDisplay = if ($r.path) { $r.path } else { "(no local path)" }
    Write-Host "    - $($r.name)  $pathDisplay" -ForegroundColor Green
}

# --- ADO organizations and projects (multiple orgs supported) ---
$adoOrgsList = @()

if ($AdoOrgs) {
    $adoOrgsList = @($AdoOrgs)
} else {
    # Detect org+project pairs from repo remotes
    $detectedPairs = @{}
    foreach ($r in $repos) {
        if (-not $r.path) { continue }
        try {
            $remote = git -C $r.path remote get-url origin 2>$null
            $org = $null
            $proj = $null

            if ($remote -match "https://([^/]+)") {
                $org = "https://$($Matches[1])"
                if ($remote -match "DefaultCollection") {
                    $org += "/DefaultCollection"
                }
            }
            if ($remote -match "DefaultCollection/([^/]+)/") {
                $proj = $Matches[1]
            } elseif ($remote -match "dev\.azure\.com/[^/]+/([^/]+)/") {
                $proj = $Matches[1]
            }

            if ($org -and $proj) {
                if (-not $detectedPairs.ContainsKey($org)) {
                    $detectedPairs[$org] = @()
                }
                if ($proj -notin $detectedPairs[$org]) {
                    $detectedPairs[$org] += $proj
                }
            }
        } catch {}
    }

    # Present detected org/project pairs
    foreach ($org in $detectedPairs.Keys) {
        $projList = $detectedPairs[$org] -join ", "
        $useDetected = Read-Host "Detected ADO org '$org' with project(s) [$projList]. Add it? (Y/n)"
        if ($useDetected -eq "" -or $useDetected -match "^[Yy]") {
            $adoOrgsList += @{ org = $org; projects = @($detectedPairs[$org]) }
        }
    }

    # Ask for additional orgs (e.g., work items in a different org)
    Write-Host ""
    Write-Host "  TIP: If your work items live in a different ADO org than your PRs," -ForegroundColor DarkYellow
    Write-Host "       add that org here (e.g., https://identitydivision.visualstudio.com)." -ForegroundColor DarkYellow

    $addMore = Read-Host "Add another ADO org? (y/N)"
    while ($addMore -match "^[Yy]") {
        $newOrg = Read-Host "  ADO org URL (e.g., https://identitydivision.visualstudio.com)"
        if ($newOrg -eq "") { break }
        $newProj = Read-Host "  Project name in that org (e.g., Engineering)"
        $extraProjects = @()
        if ($newProj -ne "") { $extraProjects += $newProj }

        $addProj = Read-Host "  Add another project in '$newOrg'? (y/N)"
        while ($addProj -match "^[Yy]") {
            $anotherProj = Read-Host "    Project name"
            if ($anotherProj -ne "") { $extraProjects += $anotherProj }
            $addProj = Read-Host "    Add another? (y/N)"
        }

        if ($extraProjects.Count -gt 0) {
            $adoOrgsList += @{ org = $newOrg; projects = @($extraProjects) }
        }
        $addMore = Read-Host "Add another ADO org? (y/N)"
    }

    if ($adoOrgsList.Count -eq 0) {
        $fallbackOrg = Read-Host "No ADO orgs detected. Enter an org URL"
        $fallbackProj = Read-Host "  Project name in that org"
        $adoOrgsList += @{ org = $fallbackOrg; projects = @($fallbackProj) }
    }
}

Write-Host "  ADO organizations ($($adoOrgsList.Count)):" -ForegroundColor Green
foreach ($entry in $adoOrgsList) {
    Write-Host "    - $($entry.org)  [$($entry.projects -join ', ')]" -ForegroundColor Green
}

# --- Detect workiq ---
$workiqPath = $null
try {
    $workiqPath = (Get-Command workiq -ErrorAction SilentlyContinue).Source
} catch {}

if (-not $workiqPath) {
    try {
        $npmPrefix = npm config get prefix 2>$null
        $candidate = Join-Path $npmPrefix "workiq.cmd"
        if (Test-Path $candidate) {
            $workiqPath = $candidate
        }
    } catch {}
}

if ($workiqPath) {
    Write-Host "  Work IQ CLI: $workiqPath" -ForegroundColor Green
} else {
    Write-Host "  Work IQ CLI: NOT FOUND" -ForegroundColor Red
    Write-Host "    Install with: npm install -g @microsoft/workiq" -ForegroundColor Yellow
    Write-Host "    Then re-run this setup." -ForegroundColor Yellow
}

# --- Write config ---
$config = @{
    user_email        = $userEmail
    git_author        = $gitAuthor
    repos_folder      = $ReposFolder
    repositories      = @($repos | ForEach-Object { @{ name = $_.name; path = $_.path } })
    ado_orgs          = @($adoOrgsList | ForEach-Object { @{ org = $_.org; projects = @($_.projects) } })
    initial_sync_days = $InitialSyncDays
    workiq_path       = $workiqPath
}

$config | ConvertTo-Json -Depth 4 | Set-Content -Path $configFile -Encoding UTF8
Write-Host "`nConfig written to: $configFile" -ForegroundColor Green

# --- Configure ADO defaults (use first org/project) ---
Write-Host "`nConfiguring ADO CLI defaults..." -ForegroundColor Yellow
$firstOrg = $adoOrgsList[0]
az devops configure --defaults "organization=$($firstOrg.org)" "project=$($firstOrg.projects[0])" 2>$null
Write-Host "  Done (default: $($firstOrg.org) / $($firstOrg.projects[0]))" -ForegroundColor Green

# --- Initialize workstreams.json if empty ---
$wsFile = Join-Path $PSScriptRoot "workstreams.json"
if (-not (Test-Path $wsFile)) {
    @{
        owner       = $userEmail
        last_synced = $null
        workstreams = @()
    } | ConvertTo-Json -Depth 3 | Set-Content -Path $wsFile -Encoding UTF8
    Write-Host "  Created empty workstreams.json" -ForegroundColor Green
} else {
    Write-Host "  workstreams.json already exists -- keeping it." -ForegroundColor Yellow
}

# --- Update mcp.json ---
$mcpFile = Join-Path $PSScriptRoot ".vscode" "mcp.json"
$mcpDir = Join-Path $PSScriptRoot ".vscode"
if (-not (Test-Path $mcpDir)) {
    New-Item -ItemType Directory -Path $mcpDir -Force | Out-Null
}
# Only write mcp.json if it doesn't already exist (don't overwrite user customizations)
if (-not (Test-Path $mcpFile)) {
    $mcpConfig = @{
        servers = @{
            workiq = @{
                command = "npx"
                args    = @("-y", "@microsoft/workiq@latest", "mcp")
                tools   = @("*")
            }
        }
    }
    $mcpConfig | ConvertTo-Json -Depth 4 | Set-Content -Path $mcpFile -Encoding UTF8
    Write-Host "  Created .vscode/mcp.json with Work IQ MCP server" -ForegroundColor Green
} else {
    Write-Host "  .vscode/mcp.json already exists -- keeping it." -ForegroundColor Yellow
}

# --- Accept EULA if needed ---
if ($workiqPath) {
    Write-Host "`nAccepting Work IQ EULA..." -ForegroundColor Yellow
    & $workiqPath accept-eula 2>$null
    Write-Host "  Done." -ForegroundColor Green
}

# --- Run initial syncs (6 months by default) ---
Write-Host ""
Write-Host "Running initial sync ($InitialSyncDays days of history)..." -ForegroundColor Cyan

# ADO sync (PRs, work items, commits)
Write-Host "`n--- ADO Signals ---" -ForegroundColor Cyan
$adoSyncScript = Join-Path $PSScriptRoot "scripts" "sync-ado.ps1"
& $adoSyncScript -DaysBack $InitialSyncDays

# Work IQ sync (meetings, emails, chats)
if ($workiqPath) {
    Write-Host "`n--- Work IQ Signals ---" -ForegroundColor Cyan
    $wiqSyncScript = Join-Path $PSScriptRoot "scripts" "sync-workiq.ps1"
    & $wiqSyncScript -DaysBack $InitialSyncDays
} else {
    Write-Host "`nSkipping Work IQ sync (CLI not found)." -ForegroundColor DarkYellow
}

# --- Done ---
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Config summary:" -ForegroundColor White
Write-Host "  User:         $userEmail" -ForegroundColor White
Write-Host "  Repositories: $($repos.Count)" -ForegroundColor White
foreach ($entry in $adoOrgsList) {
    Write-Host "  ADO org:      $($entry.org) [$($entry.projects -join ', ')]" -ForegroundColor White
}
Write-Host "  Initial data: $InitialSyncDays days" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Open this folder in VS Code (or add to workspace)" -ForegroundColor White
Write-Host "  2. Start the Work IQ MCP server from Copilot chat tools" -ForegroundColor White
Write-Host "  3. Ask Copilot: 'What am I updating on?'" -ForegroundColor White
