# Work Tracker

A lightweight AI agent that tracks your active workstreams by combining
meeting context (via Work IQ), Azure DevOps signals (PRs, work items),
and git commits into a persistent memory store.

Built for engineers whose work context lives primarily in meetings,
standups, and livesite/ops activity -- not just in PRs and tickets.

## Prerequisites

- **Microsoft 365 Copilot license** (required for Work IQ)
- **Work IQ CLI**: `npm install -g @microsoft/workiq`
- **Azure CLI** with DevOps extension: `az extension add --name azure-devops`
- **VS Code** with GitHub Copilot extension
- **Git** (for commit history)
- **Node.js 18+** (for Work IQ CLI)

## Quick Start

```powershell
# 1. Clone or copy this folder
# 2. Run setup (interactive -- detects your identity and repo)
.\setup.ps1

# 3. Open in VS Code
code .

# 4. Start Work IQ MCP server
#    In Copilot chat, click the tools icon and start "workiq"

# 5. Collect ADO signals
.\scripts\sync-ado.ps1

# 6. Ask Copilot: "What am I updating on?"
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
| `scripts/sync-ado.ps1` | Collects PRs, work items, commits |
| `.vscode/mcp.json` | VS Code MCP server config for Work IQ |

## Usage

### Before standup
```
"What am I updating on?"
```

### After a meeting or end of day
```powershell
.\scripts\sync-ado.ps1
# Then in Copilot chat:
# "Sync my work updates using Work IQ and the ADO signals in last-sync-input.json"
```

### Weekly status
```
"Draft a weekly status update based on my workstreams"
```

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
