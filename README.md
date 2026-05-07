# Work Tracker

A lightweight AI agent that tracks your active workstreams by combining
meeting context (via Work IQ), Azure DevOps signals (PRs, work items),
and git commits into a persistent memory store.

Built for engineers whose work context lives primarily in meetings,
standups, and livesite/ops activity -- not just in PRs and tickets.

## Prerequisites

- **Microsoft 365 Copilot license** (required for Work IQ)
- **Azure CLI** with DevOps extension: `az extension add --name azure-devops`
- **VS Code** with GitHub Copilot extension
- **Git** (for commit history)
- **Node.js 18+** (for Work IQ)

## Quick Start

1. Clone or copy this folder and open it in VS Code
2. Run setup (interactive — detects your identity, repos, and ADO orgs):
   ```powershell
   .\setup.ps1
   ```
   Alternatively, you can ask Copilot to do it for you:
   ```
   "Set up work tracker"
   ```
   > **Note:** Setup takes approximately **15 minutes** to complete (it scans repos, discovers ADO orgs, and runs an initial sync). Be patient and let it finish — do not cancel early.
3. In Copilot chat, click the **tools icon** (🔧) and start the **workiq** MCP server
4. Ask Copilot: **"Sync my work"** — it will collect ADO signals and merge them
5. Ask Copilot: **"What am I updating on?"**

That's it. Everything else happens through Copilot chat.

## Using Copilot (recommended)

All commands below are typed in **VS Code Copilot chat** (Ctrl+Shift+I or the Copilot sidebar).

### Setup
If `config.json` doesn't exist yet, Copilot will guide you through setup:
```
"Set up work tracker"
```
Or run `.\setup.ps1` in the terminal for the interactive wizard.

### Sync your work
Copilot can run the full sync (collect ADO + Work IQ signals, then merge):
```
"Sync my work"
```
This collects PRs, work items, and commits from ADO, meeting/email/chat context
from Work IQ, and merges everything into `workstreams.json`.

You can also specify a time range:
```
"Sync my work for the last 14 days"
```

### Prepare for Connects / Draft Impact Summary
Connect season? Use these prompts to generate impact statements from your tracked workstreams:
```
"Draft my Connect impact summary"
"Draft my Connect impact summary for this half"
"What impact did I have this quarter?"
"Prepare for Connects"
```
The agent will:
1. Review all workstreams active during the period
2. Query linked documents (PIRs, design docs) and auto-discover related SharePoint/OneDrive files via Work IQ
3. Extract real metrics (ICM counts, customer impact, severity, timelines)
4. Classify each workstream's impact (direct, leveraged, or organizational)
5. Generate Connect-ready statements in the format: **"Delivered [what], which resulted in [outcome] for [who]."**

You can also update impact for a specific workstream:
```
"Update the impact for config merge — the PR reduced ICMs by 50%"
"Add impact: automated tenant rotation cut setup from 60 hours to 30 minutes"
```
Or scope the summary to a time range:
```
"What's my impact since January?"
"Draft impact summary for FY26 H2"
```

### Using terminal scripts directly
If you prefer running scripts manually:
```powershell
# Collect signals and prepare merge input
.\sync.ps1 -DaysBack 7

# Then ask Copilot to complete the merge:
# "Merge the signals from last-merge-input.json into workstreams.json"
```

## How It Works

```
You ask: "What am I updating on?"
          |
          v
+-------------------+    +---------------------+
|  Work IQ MCP      |    |  Workstream Memory   |
|  (live retrieval)  |    |  (workstreams.json)  |
|                   |    |                     |
|  Meetings         |    |  Active threads     |
|  Emails           |    |  Evidence log       |
|  Teams chats      |    |  Status tracking    |
+-------------------+    +---------------------+
          |                        |
          +--------+  +------------+
                   v  v
          +-------------------+
          |  ADO / Git        |
          |  (sync-ado.ps1)   |
          |                   |
          |  PRs, work items  |
          |  commits          |
          +-------------------+
```

1. **Work IQ** retrieves your meeting content, emails, and chats in real time
2. **sync-ado.ps1** collects PRs, work items, and commits from Azure DevOps
3. **workstreams.json** persists your active workstreams across sessions
4. The **sync prompt** merges new signals into existing workstreams
5. The **query prompt** summarizes what you are working on right now

## Files

| File | Purpose |
|------|---------|
| `setup.ps1` | Interactive setup -- configures identity, repo, ADO |
| `config.json` | Generated config (user-specific, gitignored) |
| `workstreams.json` | Persistent workstream memory |
| `last-sync-input.json` | Latest ADO sync output (gitignored) |
| `prompts/sync.md` | Prompt template for updating workstreams |
| `prompts/query.md` | Prompt template for "what am I updating on?" |
| `prompts/impact.md` | Prompt template for Connect-ready impact summaries |
| `scripts/sync-ado.ps1` | Collects PRs, work items, commits |
| `.vscode/mcp.json` | VS Code MCP server config for Work IQ |

## Usage

All usage is through **Copilot chat**. Just type what you need:

### Before standup
```
"What am I updating on?"
"What should I update on in standup?"
```

### Sync after a meeting or end of day
```
"Sync my work"
```
Copilot collects ADO signals and Work IQ context, then merges them into your workstreams automatically.

### Weekly status
```
"Draft a weekly status update based on my workstreams"
```

### Link a document to a workstream
```
"Link this doc to config merge: https://sharepoint.com/..."
"Extract impact from this doc: https://sharepoint.com/..."
```
Work IQ reads the document and extracts ICM counts, customer impact numbers,
and other metrics. You can also skip linking -- the agent will auto-discover
related documents when generating impact.

### Check stale work
```
"What workstreams have gone quiet?"
```

## Customization

- **DaysBack**: `.\scripts\sync-ado.ps1 -DaysBack 14` to look further back
- **Multiple repos**: Run setup again with different repo params, or edit config.json
- **Keywords**: The agent learns keywords from your meetings automatically

## Privacy

- Work IQ uses your delegated identity -- it only sees what you can see
- workstreams.json is local to your machine
- No data leaves your environment unless you share the file
- config.json contains your email and repo path (gitignored)
