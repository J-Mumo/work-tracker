# Work Tracker Adoption Plan

How to make work-tracker easy for other Microsoft engineers to use.

## Priority 1: Reduce Setup Friction

### 1.1 Rewrite scripts in Node.js (cross-platform)
- Replace `setup.ps1`, `sync.ps1`, `sync-ado.ps1`, `sync-workiq.ps1` with Node.js equivalents
- The project already requires Node.js 18+ for Work IQ, so no new dependency
- Use `@azure/identity` + `azure-devops-node-api` instead of shelling out to `az` CLI (removes Azure CLI prerequisite)
- Add a `package.json` with bin entries so `npx work-tracker setup` works

### 1.2 Create an npx-based installer
- `npx work-tracker init` — single command that:
  - Detects identity (from git config or az cli if available)
  - Scans for git repos in parent directory
  - Auto-detects ADO org/project from remotes
  - Creates `config.json` and `workstreams.json`
  - Copies `.vscode/mcp.json` and `AGENTS.md` into place
  - Runs initial ADO sync
- `npx work-tracker sync` — replaces `sync.ps1`

### 1.3 Prerequisite checker
- On `init`, validate: Node.js version, git available, Work IQ accessible
- Print clear fix instructions for any missing prerequisite
- Make Work IQ optional (tool still works with ADO-only signals)

## Priority 2: Work From Any Workspace

### 2.1 Global AGENTS.md support
- Currently `AGENTS.md` only works when work-tracker is the active VS Code workspace
- Option A: Document how to add work-tracker as a folder in a multi-root VS Code workspace
- Option B: Install `AGENTS.md` to `~/.agents/` or a global Copilot instructions location if/when VS Code supports it
- Option C: Create a VS Code extension that registers the agent prompts globally

### 2.2 Decouple data location from workspace
- Store `workstreams.json` and `config.json` in `~/.work-tracker/` instead of the project folder
- Scripts should reference this global path
- The project repo becomes just the template/tooling, not the data store

## Priority 3: Distribution

### 3.1 Publish as internal npm package
- `@microsoft/work-tracker` on internal npm registry
- Users install with: `npm install -g @microsoft/work-tracker && work-tracker init`

### 3.2 Create a VS Code extension (stretch)
- Extension registers MCP servers, agent instructions, and sync commands
- Users install from VS Code marketplace, run setup from command palette
- Status bar shows last sync time and active workstream count

### 3.3 Template repo on GitHub Enterprise
- Provide a "Use this template" repo so teams can fork/clone easily
- Include GitHub Actions or ADO pipeline for automated sync (optional)

## Priority 4: Team Visibility (Optional)

### 4.1 Export commands
- `work-tracker export --format teams` — generates a Teams-ready status message
- `work-tracker export --format email` — generates email-friendly summary
- `work-tracker export --format markdown` — for pasting into wikis

### 4.2 Shared dashboard (future)
- Optional: push `workstreams.json` summaries to a shared SharePoint list or Teams channel
- Manager can see team-level view of active workstreams
- Privacy-first: user controls what gets shared

## Priority 5: Documentation & Onboarding

### 5.1 Improve README with quick-start variants
- "I have 2 minutes" — minimal setup path
- "I want the full experience" — complete setup with Work IQ
- "I'm on Mac/Linux" — cross-platform instructions (blocked on Priority 1)

### 5.2 Add a demo/walkthrough
- Record a short video or GIF showing: setup → first sync → "What am I updating on?"
- Add to README and internal blog post

### 5.3 FAQ / Troubleshooting section
- Common issues: ADO auth failures, Work IQ EULA, multi-org setups
- "It's not picking up my PRs" debugging guide

## Implementation Order

1. **1.1** Node.js rewrite of scripts (biggest unblock for cross-platform)
2. **1.2** npx installer (biggest reduction in setup friction)
3. **2.2** Global data location (lets users work from any workspace)
4. **5.1** README improvements (low effort, high impact)
5. **1.3** Prerequisite checker
6. **3.1** npm package publish
7. **2.1** Global AGENTS.md solution
8. **4.1** Export commands
9. Everything else
