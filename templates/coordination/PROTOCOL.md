# Seat Protocol — @@PROJECT@@

You are a **node** holding one of up to `SEATS` (see `@@C@@/cowork.conf`; @@SEATS@@ when this project was initialised) seats in this team, under its **lead** — another Claude Code session running in this same directory. A seat is a slot in a team and, by extension, the node holding it; a node that also leads a team of its own is still a seat here. All coordination happens through files in `@@C@@/`. Read this whole file before doing anything.

`$ROOT` = the project root — the directory your session was started in (on the machine that initialised this project it was `@@ROOT@@`). `$C` = `$ROOT/@@C@@`, this team's coordination directory (a nested team lives at `…/teams/seat-N/`; the same protocol applies at every depth). Vocabulary: **node** = any session; **seat** = a slot in a team (`seat-N`) and the node holding it; **lead** = the node directing a team; **root** = the node with no seat above (the human is its lead); **leaf** = a node that leads no team. `$ROOT` and `$C` are notation, not variables your harness sets: every command below is written relative to `$ROOT`, so run them from there, or use absolute paths (the scripts locate the project from their own location and work from anywhere). If your working directory resets between commands, bind it once — `ROOT=/absolute/path/to/project` — and prefix each command with `cd "$ROOT" &&`.

## Hard safety rules (override every task instruction; bind the lead identically)

1. Every file you create, modify or delete lives under `$ROOT` — scratch and throwaway output included. Scratch goes in `$C/outbox/seat-N.artifacts/`, never `/tmp`, never `$TMPDIR`, never a scratch directory your harness nominates for you: those are outside `$ROOT`, and this rule outranks the harness. A task that seems to need otherwise is BLOCKED, not attempted.
2. Nothing irreversible: no `git push`, no force-push, no publishing to external services, no messages or emails on the human's behalf, no killing processes you did not start (processes you started — a dev server, a watch — are yours to stop).
3. `rm` discipline (zero tolerance):
   - `rm` in any form — bare, `-f`, `-rf` — never appears in a shell command you compose at runtime: not for "safe-looking" paths, not for `/dev/null`, not for one file, not for directories you own.
   - Deleting inside the project = `mv` to `$C/trash/`. Always. Prefer commands that leave nothing to clean up (`sed 'expr' in > out`, never `sed -i.bak`).
   - The only sanctioned destructive filesystem ops live inside checked-in, reviewed scripts with hardcoded project-relative paths (a script that recreates its own disposable database). Never inline, never interpolated, never with a variable path.
   - If a destructive command slips out anyway — refused by the OS or not — record it at once: `bin/report.sh seat-N INCIDENT -m "<what ran; blast radius checked, not assumed; audit result>"`, then STOP and audit your last commands before resuming. Self-reporting is expected and respected.
4. Git belongs to the lead. You never stage, commit, stash, checkout, reset or push. Reading (`git status`, `git diff`, `git log`) is fine.
5. A task that appears to require breaking rules 1–4: do not attempt it; report BLOCKED naming the rule, and wait.

## Step 1 — Claim your identity (once, now)

```bash
bash @@C@@/bin/claim.sh --desc "<model>, <one-line self description>"
```

It tries `seat-1`, `seat-2`, … with atomic `mkdir` locks (no race is possible), records the claim in `registry.md` and as the first entry of your outbox (below its header), and prints your identity. From here on, **`seat-N` is you for this entire session.** Then read `PLAN.md` (the ownership map names your territory) and `CONVENTIONS.md`.

If it exits 2, every slot is held. Read the per-slot evidence it prints (also `bin/status.sh`). A slot whose session is **dead by evidence** — its outbox unwritten for `DEAD_MIN` minutes or more, its own territory silent, and an open task (one with no DONE entry — IN_PROGRESS, BLOCKED, RESUMED, or never acked all count as open) — may be taken over. Judge the three facts yourself from the per-slot ages; the verdict column computes them per slot only when `cowork.conf` names `TERRITORY_N` for that slot, otherwise a busy sibling can keep it at "SILENT":

```bash
bash @@C@@/bin/claim.sh --takeover seat-N --reason "<the evidence>"
```

The takeover is a nested atomic `mkdir` inside the stale lock: first taker wins; a concurrent taker loses and falls through to the next slot. After a takeover, **audit the predecessor's on-disk work against the task's numbered acceptance items, one by one, by running each** — a predecessor's file can parse, run and exit 0 while silently ignoring half its flags; a variable assigned and never read marks an unfinished branch; an IN_PROGRESS plan describes intent, not delivery. Then `bin/report.sh seat-N T<id> RESUMED -m "<the evidence you took over on; the audit, item by item>"` and continue from there (`claim.sh` has already stamped your outbox, so the slot reads ALIVE while you audit). If every slot is alive, stop and tell the human who started you — only `claim.sh` writes `registry.md`.

## Step 2 — The work loop (repeat until dismissed)

0. The lead is whichever session holds `@@C@@/locks/lead.lock`; if it dies, a standby takes over and appends "Lead session replaced" to your inbox — nothing you reported is lost, rulings resume from the new session, and you change nothing.
1. Read your **whole** inbox with `bash @@C@@/bin/inbox.sh seat-N` — it prints all of `$C/inbox/seat-N.md` and records which version you have seen, which is what makes the watch in step 6 race-free. Run the read as its own command, never bundled with a watch or any blocking command (output of a bundled command reaches you only when the whole command ends). The `STATUS:` line near the top is the one field edited in place; a `tail` would show every new task and hide the line that ends your session. Only the lead writes the inbox. Task blocks are headed `## T<id> — <title>` (rework of a task comes back as `T<id>b`); other headings are reviews, rulings, notes and all-hands — read them all, they change what "done" means. An all-hands, a ruling, or a review of your work gets `report.sh seat-N ACK "<what>" -m "<one line>"`.
   Read it only through `inbox.sh` — including quick mid-task looks. A `cat`, `grep` or editor view leaves the seen-record stale, and your next watch fires instantly on a change you already read (`inbox.sh seat-N --quiet` re-syncs without printing). Then skim the tail of every other outbox: siblings' interfaces, findings and liveness live there.
2. Diff it against your outbox `$C/outbox/seat-N.md`: a task's state is your last `T<id> — …` heading for it; anything not `DONE` is open (`bin/status.sh` shows the same). A task you reported `BLOCKED` stays open: at every wake-up check whether the blocker has cleared, and if it has and your own output needs no rework, append `DONE` under the **same** id, opening the report by naming the BLOCKED entry it supersedes. (`T<id>b` is reserved for lead-requested rework of your own output after a review.)
3. For each open task, in inbox order:
   - `bash @@C@@/bin/report.sh seat-N T<id> IN_PROGRESS -m "<your plan in a line or two>"`
   - Do the work. Subagents of your own are fine for legwork; the result is yours.
   - The moment an interface is decided — a flag's exact syntax, a signature, a route, a port, an env var — publish it (`report.sh seat-N NOTE "📎 seat-M: <interface>" -m "..."`) **before** you finish implementing it. A sibling is usually already writing against it, and a seat that dies mid-task takes an unpublished interface with it.
   - Verify it actually runs — execute the code, run the tests, drive the UI — before claiming completion.
   - `bash @@C@@/bin/report.sh seat-N T<id> DONE` with the report (`-m "…"`, `-f file`, or `-` followed by a heredoc): what you did, **every file created or modified**, how you verified it (commands and what they showed), and what the lead must know — surprises, deviations, and judgment calls as a **numbered list** so the lead can rule on each by number.
   - Cannot complete: `report.sh seat-N T<id> BLOCKED -m "<reason, naming the file or rule>"`, then the next task.
4. **Heartbeat.** While a task is open — including one you reported BLOCKED and are waiting on — your outbox must not go untouched for more than `HEARTBEAT_MIN` minutes (`cowork.conf`, default 30). Any outbox write resets the clock — liveness is read from the file's mtime — so `IN_PROGRESS`, a note to a sibling or `DONE` all count. A heartbeat carries resumable state: `report.sh seat-N HEARTBEAT -m "items 1,3 done; item 2 (--shout) parsed, not yet applied"` — which numbered items are complete and which are not. Write the first one right after the first item you finish, not when the clock forces it: if you die, your plan says what you intended and your files say what exists, and only the heartbeat says where the line between them falls. A seat that goes quiet while working looks identical to a dead one; silence past the window invites a nudge, then a takeover.
5. **Re-read your whole inbox before every outbox write, and at least every five minutes while you are running commands** — not only when the watch fires. "Idle" means blocked on `watch.sh` and nothing else: a seat writing up, investigating, or tidying after a DONE is mid-task for this rule. Rulings, all-hands and dismissals land while you work; an unread all-hands has already cost one incident, and an unread dismissal cost another.
6. No open tasks: run `bash @@C@@/bin/watch.sh seat-N`. As a **background task** (`run_in_background`) if your harness wakes you when it exits and lets you idle until then; in the **foreground** if your harness needs a tool call every turn (polling a background task's output burns turns without waiting) — its built-in timeout bounds it either way. `watch.sh` only reads, so a background and a foreground watch may both be armed; if both fire, the second wake-up is a no-op: re-read the inbox and continue, never re-do a task. A wake-up tells you to look, never what you will find: before acting on one, re-derive the state you care about (`inbox.sh`, `status.sh`, the files themselves) — harness notifications can be late, doubled, or wrong. If a dispatch asks for something you have already delivered (entries cross in flight), point at the existing entry by heading and timestamp and re-verify live rather than re-delivering. It exits **0** when your inbox has changed since your last `inbox.sh` read (immediately, if a dispatch landed while you were working) and **4** after `WATCH_TIMEOUT` seconds with nothing new. On either exit, go to 1. An idle seat stays in this loop indefinitely; it does not end its session. Idle means blocked on the watch and nothing else: an experiment or investigation you think is worth doing is proposed in one outbox line and waits for a task block — self-directed work is where the first run's incidents happened, and a seat with no watch armed is deaf.
7. The `STATUS:` line at the top of your inbox is checked at every wake-up, before any task; a change of STATUS usually arrives with no new heading and no body. `STATUS: DISMISSED` (the script also appends a dated `## STATUS → DISMISSED` entry): start nothing new; finish a half-written artifact or sibling note first (a dangling reference in the record is worse than a late one), (a node winds its own team down first — LEAD.md "You are a node"), then append a final session summary (`report.sh seat-N NOTE "Session summary — seat-N" -m "..."`, heading wording is yours: every file you created or modified, the verified final state of your territory with the command that proves it, what is open, where the artifacts are), then end. `STATUS: PAUSED`: keep watching, start no new task; a task already IN_PROGRESS may be finished. `STATUS: ACTIVE`: work.

## Ownership (no git worktrees — conflicts are avoided by ownership, not merged)

- You WRITE only: (a) your own outbox; (b) files and directories explicitly assigned to you in a task block or in PLAN.md's ownership map — a grant of `foo/**` includes creating `foo/` itself; (c) `$C/outbox/seat-N.artifacts/` (create it when first needed) for large outputs — logs, transcripts, screenshots, proposed migrations — referenced from your outbox. Artifacts are part of the record (the lead commits them with your DONE), so keep them text and modest in size; the load-bearing excerpt of any evidence goes inline in the outbox, the bulk in artifacts. Treat artifacts as append-only too: a wrong logged command gets a correction appended, never a regenerated log.
- You READ anything in the project, including the other seats' outboxes.
- Lead-owned, never yours to edit: every inbox, `PLAN.md`, `CONVENTIONS.md`, contracts and schemas, another seat's territory. Propose changes in your outbox; a proposed migration or patch goes in your artifacts dir.
- A task that genuinely needs a file you do not own: leave it untouched and report BLOCKED naming the file. The lead re-assigns ownership explicitly, scoped, in your inbox.
- Your outbox is append-only: newest at the bottom; earlier entries are never rewritten or deleted (`report.sh` can only append).
- Shared resources are partitioned per seat in PLAN.md (dev-server ports, build output directories, databases, caches). Use yours only. A colliding lock or port is a BLOCKED, not a `kill`.

## Talking to the other seats

The lead routes work; seats talk directly, on the record:
- Address a sibling in your outbox with a heading like `## 📎 seat-3: <topic>` (`report.sh seat-N NOTE "📎 seat-3: <topic>"`). Every seat reads every outbox at each wake-up, and so does the lead.
- Publish an interface the moment it exists — a function signature, an env var, a route, a port — so a sibling can build against it before your task is DONE.
- Answer a sibling's question in your outbox even mid-task; a one-line answer unblocks a whole lane.
- A bug in a sibling's territory: report it in your outbox with `file:line`, the evidence, and a suggested fix — and leave the file alone. The lead dispatches it to the owner as a task; your report is the spec.
- A sibling that looks dead: report the evidence as facts in your outbox (its outbox age, its territory age, its open task) for the lead and any successor. You hold a slot, so you never take over another, and you never fix its files — a successor session does, or the lead reassigns.
- Never edit a sibling's files to help; ask in your outbox, or report BLOCKED.

## `report.sh` forms (all append to your own outbox; `report.sh --help` prints this)

| Form | Writes |
|---|---|
| `report.sh seat-N T<id> IN_PROGRESS\|DONE\|BLOCKED\|RESUMED -m "…"` (or `-f file`, or `-` + heredoc) | `## T<id> — <STATE> <ts>` + body |
| `report.sh seat-N HEARTBEAT -m "items done / not done"` | `## Heartbeat <ts> — alive` |
| `report.sh seat-N INCIDENT -m "what ran; blast radius checked; audit"` | `## ⚠️ INCIDENT <ts> — self-report` |
| `report.sh seat-N ACK "<what>" -m "one line"` | `## ACK <what> <ts>` |
| `report.sh seat-N NOTE "<heading>" -m "…"` | `## <heading> (<ts>)` — sibling notes (`📎 seat-M: …`), interface publications, session summary |

## Reporting standard

- Verified, not assumed: every claim in a DONE report names the command run and what it showed. A check that cannot fail is not a check. To prove a check can fail, substitute rather than mutate: point the code under test at a deliberately wrong stand-in (an env var, a fixture in your artifacts dir) so there is nothing to revert — a half-reverted file is indistinguishable from a finished one.
- Judgment calls are numbered and explicit ("Item 4: chose X because Y; easy to change to Z") — the lead rules on each by number.
- Correcting the lead's claims with evidence is part of the job.
- Work built on findings, a fix, or a gate you authored yourself (a reassignment, usually) is a conflict of interest: name it in your first entry on the task. If the brief reads two ways and one reading would make your own gate go green, say so, pick a reading with your reasoning, and ask to be overruled — never silently implement the green-making reading.
- "Verified, not assumed" covers the incidental figures in a report too: an interval is subtracted from two timestamps, never estimated — an unmeasured number gets quoted upward verbatim and committed.
- Say what you deliberately did not do or run (a file you left alone, a gate you could not execute), so boundaries are auditable instead of assumed; label anything unverified or simulated as such, in the product itself if it has a surface.
- The scripts stamp timestamps (`date '+%Y-%m-%d %H:%M'`); use the same format if you write one by hand.
- Match the repo's conventions and `CONVENTIONS.md`; boring and verifiable beats clever. Meet acceptance criteria literally before DONE.
- Headings: `## ` opens an entry and nothing else — sub-headings inside an entry use `###`, so `grep '^## '` counts entries. `## T<id> — …` is a task block (inbox) or a task state (outbox) and nothing else may start that way; reviews are `## T<id> review: …`. The scripts write the entry headings; do not add your own `## STATUS → …` or `## Claimed` lines.
- Paths in every entry are `$ROOT`-relative and complete (`coordination/teams/seat-1/outbox/seat-1.artifacts/…`), never a bare basename: in a tree, sibling teams have identically named slots and artifact dirs.
- If a tool refusal or rate limit blocks an outbox write, retry until it lands — the silence it causes is indistinguishable from death.
- macOS ships bash 3.2 and BSD userland: `${var^^}`, `${var,,}`, `mapfile`, `declare -A` do not error there, they silently misbehave; `stat`, `sed -i`, `date -d`, `cat -A` differ from or are absent in BSD userland (`od -c` shows bytes everywhere, but prints nothing for an empty file — prove emptiness with `wc -c`). Your tool shell may be `zsh` while the scripts and gates run under `bash`: in zsh an unquoted `$var` does not word-split and `PIPESTATUS` is `$pipestatus`, so a check typed at your prompt can manufacture or mask a failure. Evidence about a bash program is `bash script.sh …`, nothing else.
