# Work Tracker Skill

A personal work-tracking agent that maintains persistent memory of your active workstreams. It combines meeting context (via Work IQ MCP), Azure DevOps signals (PRs, work items), and git commits to help you answer "what am I working on?" at any moment.

## Prerequisites

- **Work IQ MCP** server running (configured in `.vscode/mcp.json` or user settings)
- **workstreams.json** in the work-tracker folder (created by `setup.ps1`)
- **Azure CLI** with DevOps extension (for ADO sync)

## First-Time Setup

If `workstreams.json` does not exist or is empty, guide the user through setup:

1. Run `.\setup.ps1` in the work-tracker folder -- it interactively detects identity, repos, and ADO orgs
2. Run `.\sync.ps1` to collect initial signals from ADO and Work IQ
3. Ask the user: "Merge the signals from last-merge-input.json into workstreams.json using the sync prompt in prompts/sync.md"

## Key Files

| File | Purpose |
|------|---------|
| `workstreams.json` | Persistent workstream memory -- always read this first |
| `prompts/sync.md` | Instructions for merging new signals into workstreams |
| `prompts/query.md` | Instructions for "what am I updating on?" |
| `prompts/impact.md` | Instructions for generating Connect-ready impact summaries |
| `sync.ps1` | Collects ADO + Work IQ signals into `last-merge-input.json` |
| `last-merge-input.json` | Latest collected signals (ready for merge) |
| `AGENTS.md` | Detailed agent routing instructions |

## How to Handle Requests

### Standup / Status Updates

Triggers: "what am I updating on?", "standup updates", "what am I working on?", "draft a status update"

1. Read `workstreams.json`
2. Read `prompts/query.md` and follow its instructions
3. If Work IQ MCP is available, query for recent meeting/chat context to enrich the response
4. Produce a concise summary of active workstreams with suggested talking points

### Weekly Status Report

Triggers: "weekly status", "draft a weekly status report", "what did I do this week?"

1. Read `workstreams.json`
2. Filter to workstreams updated in the last 7 days
3. If Work IQ MCP is available, query: "What did I discuss in meetings this week?"
4. Produce a concise summary suitable for email or Teams message, grouped by workstream

### Sync / Update Workstreams

Triggers: "sync my work", "update my workstreams", "merge signals"

1. Tell the user to run `.\sync.ps1` first (collects ADO + Work IQ signals)
2. Read `last-merge-input.json` and `workstreams.json`
3. Follow `prompts/sync.md` to merge signals into workstreams
4. Write the updated content back to `workstreams.json`

### Impact / Connect Prep

Triggers: "what's my impact?", "draft my Connect impact summary", "prepare for Connects", "measure my impact"

1. Read `workstreams.json`
2. Read `prompts/impact.md` and follow its instructions
3. For workstreams with `document_urls`, query Work IQ MCP with `fileUrls` to extract real metrics from PIR docs, design docs, and analyses
4. For workstreams without `document_urls`, query Work IQ to auto-discover related SharePoint/OneDrive documents and extract metrics
5. If Work IQ MCP is available, also query for ICM counts, customer escalations, and team feedback
6. Produce a Connect-ready impact summary following Microsoft's "Delivered X, resulted in Y for Z" framework
7. For workstreams with `impact: null`, draft statements and ask the user to confirm
8. For workstreams with existing impact, check if metrics can be strengthened with document data

### Update Impact

Triggers: "update the impact for [workstream]", "add impact: [description]", "the config merge PR reduced ICMs by X"

1. Read `workstreams.json`
2. Update the `impact` field for the specified workstream
3. Write back to `workstreams.json`

### Link Document to Workstream

Triggers: "link this doc to [workstream]", "here's the PIR for [workstream]", "add this document", "extract impact from this doc"

1. Read `workstreams.json`
2. Add the URL to `document_urls` for the matching workstream
3. Query Work IQ MCP with `fileUrls` parameter to extract metrics (ICM counts, customer numbers, severity, TTD/TTM, etc.)
4. Show extracted metrics and offer to update the `impact` field
5. Write back to `workstreams.json`

If the user doesn't specify a workstream, use document content to match automatically.

### Stale Work Check

Triggers: "what workstreams have gone quiet?", "what's stale?", "anything I've forgotten?"

1. Read `workstreams.json`
2. List workstreams with no evidence in the last 14 days
3. Ask the user if each is still active or should be marked dormant

## Work IQ MCP Integration

When the Work IQ MCP server is available, use it to enrich ALL responses:
- Query recent meetings, emails, and chats for context
- Cross-reference workstream topics with live M365 data
- Pull ICM data for impact measurement

Always combine Work IQ signals with `workstreams.json` -- do not rely on Work IQ alone, as it does not maintain state across sessions.

## Important Rules

- Always read `workstreams.json` FIRST before responding to any request
- Do not invent metrics or evidence -- only use what exists in workstreams or live signals
- Do not overwrite `impact` fields during sync -- impact is user-curated
- Keep responses concise -- standup prep is a quick glance, not a report
- When merging signals, follow `prompts/sync.md` exactly for the schema and matching rules
