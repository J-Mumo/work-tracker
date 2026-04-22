# Work Tracker - Setup Script
# Detects user identity and configures the work tracker for first use.
# Supports multiple repositories and ADO projects.

param(
    [string]$ReposFolder,
    [string[]]$Repositories,
    [string]$AdoOrg,
    [string[]]$AdoProjects,
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

# --- ADO org ---
if (-not $AdoOrg) {
    $detectedOrg = $null
    $firstRepoWithPath = $repos | Where-Object { $_.path } | Select-Object -First 1
    if ($firstRepoWithPath) {
        try {
            $remote = git -C $firstRepoWithPath.path remote get-url origin 2>$null
            if ($remote -match "https://([^/]+)") {
                $detectedOrg = "https://$($Matches[1])"
                if ($remote -match "DefaultCollection") {
                    $detectedOrg += "/DefaultCollection"
                }
            }
        } catch {}
    }

    if ($detectedOrg) {
        $useDetected = Read-Host "Detected ADO org '$detectedOrg'. Use this? (Y/n)"
        if ($useDetected -eq "" -or $useDetected -match "^[Yy]") {
            $AdoOrg = $detectedOrg
        }
    }

    if (-not $AdoOrg) {
        $AdoOrg = Read-Host "Enter your ADO organization URL (e.g., https://dev.azure.com/myorg)"
    }
}
Write-Host "  ADO org: $AdoOrg" -ForegroundColor Green

# --- ADO projects (multiple) ---
$projects = @()

if ($AdoProjects) {
    $projects = @($AdoProjects)
} else {
    # Detect from repo remotes
    $detectedProjects = @()
    foreach ($r in $repos) {
        if (-not $r.path) { continue }
        try {
            $remote = git -C $r.path remote get-url origin 2>$null
            $proj = $null
            if ($remote -match "DefaultCollection/([^/]+)/") {
                $proj = $Matches[1]
            } elseif ($remote -match "dev\.azure\.com/[^/]+/([^/]+)/") {
                $proj = $Matches[1]
            }
            if ($proj -and $proj -notin $detectedProjects) {
                $detectedProjects += $proj
            }
        } catch {}
    }

    foreach ($dp in $detectedProjects) {
        $useDetected = Read-Host "Detected ADO project '$dp'. Add it? (Y/n)"
        if ($useDetected -eq "" -or $useDetected -match "^[Yy]") {
            $projects += $dp
        }
    }

    $addMore = "y"
    while ($addMore -match "^[Yy]") {
        $newProj = Read-Host "Enter another ADO project name (or press Enter to skip)"
        if ($newProj -eq "") { break }
        if ($newProj -notin $projects) {
            $projects += $newProj
        }
        $addMore = Read-Host "Add another project? (y/N)"
    }

    if ($projects.Count -eq 0) {
        $fallback = Read-Host "No projects detected. Enter at least one ADO project name"
        $projects += $fallback
    }
}

Write-Host "  ADO projects ($($projects.Count)):" -ForegroundColor Green
foreach ($p in $projects) {
    Write-Host "    - $p" -ForegroundColor Green
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
    ado_org           = $AdoOrg
    ado_projects      = @($projects)
    initial_sync_days = $InitialSyncDays
    workiq_path       = $workiqPath
}

$config | ConvertTo-Json -Depth 4 | Set-Content -Path $configFile -Encoding UTF8
Write-Host "`nConfig written to: $configFile" -ForegroundColor Green

# --- Configure ADO defaults (use first project) ---
Write-Host "`nConfiguring ADO CLI defaults..." -ForegroundColor Yellow
az devops configure --defaults "organization=$AdoOrg" "project=$($projects[0])" 2>$null
Write-Host "  Done (default project: $($projects[0]))" -ForegroundColor Green

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
if ($workiqPath) {
    $mcpDir = Join-Path $PSScriptRoot ".vscode"
    if (-not (Test-Path $mcpDir)) {
        New-Item -ItemType Directory -Path $mcpDir -Force | Out-Null
    }
    $mcpConfig = @{
        servers = @{
            workiq = @{
                type    = "stdio"
                command = $workiqPath
                args    = @("mcp", "--account", $userEmail)
            }
        }
    }
    $mcpConfig | ConvertTo-Json -Depth 4 | Set-Content -Path $mcpFile -Encoding UTF8
    Write-Host "  Updated .vscode/mcp.json with Work IQ MCP server" -ForegroundColor Green
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
Write-Host "  ADO projects: $($projects -join ', ')" -ForegroundColor White
Write-Host "  Initial data: $InitialSyncDays days" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Open this folder in VS Code (or add to workspace)" -ForegroundColor White
Write-Host "  2. Start the Work IQ MCP server from Copilot chat tools" -ForegroundColor White
Write-Host "  3. Ask Copilot: 'What am I updating on?'" -ForegroundColor White
