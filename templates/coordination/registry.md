# Seat registry

Claim a slot per PROTOCOL.md Step 1 (`bin/claim.sh`). The lock directories in `coordination/locks/` are the source of truth; this file is the human-readable history — append, never rewrite.

- lead: the Claude Code session started in this directory as LEAD — writes inboxes, PLAN.md, resolves conflicts, runs git.
