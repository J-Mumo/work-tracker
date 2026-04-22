# Work Tracker Agent Instructions

This folder is a personal work-tracking system. It maintains a persistent memory of active workstreams in `workstreams.json`.

## Key Files

| File | Purpose |
|------|---------|
| `workstreams.json` | Persistent workstream memory -- read and update this |
| `prompts/sync.md` | Instructions for merging new signals into workstreams |
| `prompts/query.md` | Instructions for answering "what am I updating on?" |
| `last-merge-input.json` | Latest collected signals (ADO + Work IQ) |
| `last-sync-input.json` | Latest ADO signals only |

## When the user asks about their work

If the user asks any of:
- "What am I updating on?"
- "What am I working on?"
- "What should I update on in standup?"
- "Draft a status update"
- "What workstreams have gone quiet?"

Then:
1. Read `workstreams.json`
2. Follow the instructions in `prompts/query.md`
3. If Work IQ MCP is available, also fetch recent meeting/chat/email context to enrich the response

## When the user asks to sync or update workstreams

If the user asks any of:
- "Sync my work"
- "Update my workstreams"
- "Merge signals into workstreams"

Then:
1. Read `last-merge-input.json` (or `last-sync-input.json` if merge input is missing)
2. Read `workstreams.json`
3. Follow the instructions in `prompts/sync.md`
4. Write the updated content back to `workstreams.json`

## When the user asks for a weekly status

If the user asks for a weekly or periodic status update:
1. Read `workstreams.json`
2. Filter to workstreams updated in the relevant period
3. Produce a concise summary suitable for email or Teams message

## Work IQ MCP

If the Work IQ MCP server is available, use it to enrich responses with live meeting, email, and chat context. Always combine Work IQ signals with the persistent workstream memory in `workstreams.json` -- do not rely on Work IQ alone, as it does not maintain state across sessions.
