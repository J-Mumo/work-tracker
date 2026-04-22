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

## When the user asks about impact or Connects

If the user asks any of:
- "Draft my Connect impact summary"
- "What's my impact?"
- "Prepare for Connects"
- "Measure my impact"
- "What impact did I have this half/quarter?"

Then:
1. Read `workstreams.json`
2. Follow the instructions in `prompts/impact.md`
3. If Work IQ MCP is available, fetch additional context about outcomes (ICM trends, team feedback, etc.)
4. Produce a Connect-ready impact summary

## When the user asks to update impact for a workstream

If the user says something like:
- "Update the impact for [workstream]"
- "The config merge PR reduced ICMs by X"
- "Add impact: [description]"

Then:
1. Read `workstreams.json`
2. Update the `impact` field for the specified workstream
3. Write back to `workstreams.json`

## When the user links a document to a workstream

If the user says something like:
- "Link this doc to [workstream]: [URL]"
- "Here's the PIR for [workstream]: [URL]"
- "Add this document: [URL]"
- "Extract impact from this doc: [URL]"

Then:
1. Read `workstreams.json`
2. Add the URL to the `document_urls` array for the matching workstream
3. Query Work IQ MCP with the URL to extract metrics (ICM counts, customer impact, severity, etc.)
4. Show the extracted metrics to the user
5. Offer to update the `impact` field with the real numbers
6. Write back to `workstreams.json`

If the user does not specify a workstream, use the document content and keywords to match to the most likely workstream and confirm with the user.

## Work IQ MCP

If the Work IQ MCP server is available, use it to enrich responses with live meeting, email, and chat context. Always combine Work IQ signals with the persistent workstream memory in `workstreams.json` -- do not rely on Work IQ alone, as it does not maintain state across sessions.
