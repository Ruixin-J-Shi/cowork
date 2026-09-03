# Why files, and when to reach for something else

*Vocabulary.* The kit's own roles are **lead** (directs a team), **seat** (a slot, and the node holding
it), **node**, **root**, **leaf**. This page still says "master/worker" where it describes other projects'
designs in their own words, and as the generic name for the layout.

The question this kit keeps getting asked: *why a file-based protocol instead of a custom MCP server, or a
messaging standard?* Short answer: files are the **record**; everything else is a **transport**. Keep the
record in files. Add a transport only for the one thing files do badly — waking a session promptly — and
only when polling latency actually hurts.

## What each option is good at

| | Files in the repo (this kit) | Custom MCP server | Claude Code native messaging | A2A / network protocols |
|---|---|---|---|---|
| Infrastructure | none; `mkdir`, `stat`, `cat` | one server process per machine (+ its DB) | none; built into the CLI | each agent runs an HTTP service |
| Durability | git history; survives every session, machine, and vendor | as good as the server's store (SQLite/Git in the best ones); the server itself is a single point of failure | messages are delivered live to a running session; no queue survives the session dying | server-side task objects; whatever store you build |
| Human-auditable | `cat` the outbox; the log *is* the deliverable | only if the server writes Markdown/Git too (`mcp_agent_mail` does) | transcript only | logs you write |
| Wake-up latency | polling: 15 s in this kit (watch scripts), or whatever you set | tool calls are request/response; a "wait for message" tool can long-poll; true push needs MCP channels/notifications, which most clients ignore | immediate: a message to an idle session starts a new turn; `notify_when_idle` gives one-shot idle notices | SSE/webhooks; immediate |
| Enforcement | by discipline: the protocol says who writes what; the scripts refuse malformed writes but cannot stop a `cat >>` | real: the server checks identity and rejects a worker writing an inbox | none beyond per-session permissions | real, at the price of auth infrastructure |
| Works with non-Claude agents / humans | yes — anything that can run bash or edit a file | yes, if the agent speaks MCP | Claude Code only | yes, if the agent implements the protocol |
| Cross-machine | via git or a shared filesystem (pull-based, minutes) | HTTP transport, yes | Remote Control / cloud sessions, yes | yes — that is what it is for |
| Failure mode | a stale mtime; you can always read the files | server down → nobody can coordinate; state possibly stuck in the server | session gone → message gone | network partitions, auth expiry |

## The recommendation

1. **Keep files as the source of truth.** Every mechanism this kit depends on — atomic slot claims,
   append-only outboxes, takeover by evidence, the review gate, the audit trail a successor reads cold —
   works *because* the state is inert bytes on disk that nothing has to be running to read. In the survey
   below, the projects with the best durability stories (`batty`, `mcp_agent_mail`, `codex-claude-code-config`)
   all converge on the same conclusion: Markdown/JSON in git, whatever else sits on top.
2. **Use Claude Code's native cross-session messaging as the wake-up signal when polling hurts.**
   `SendMessage` to a local session starts its next turn immediately, and `notify_when_idle` replaces
   "is it done yet" polling. It costs nothing to add: the lead appends the inbox entry (the record), then
   sends a one-line "inbox updated — T3" to the seat's session (the doorbell). If the message is lost,
   the watch script still fires within 15 s; if the session is dead, the file is still there for the
   successor. Do not move content into messages — a message a dead session never read is not a record.
   Requires the sessions to be visible in `ListAgents` (same machine, or Remote Control).
3. **Write a custom MCP server only if you need enforcement rather than discipline** — for example, a
   fleet of agents you do not control, or workers on models that cannot be trusted to honour "never
   write an inbox". Then make it a *thin* server over this same file layout: tools `claim`, `inbox_read`,
   `outbox_append`, `dispatch`, `status`, `wait_for_inbox` (long-poll up to N seconds). Persistence stays
   in the files; the server adds identity checks and a typed surface. Do not let it become the store.
4. **Skip A2A/ACP/ANP for a same-machine, same-repo team.** They solve discovery, auth and transport between
   separately deployed services. ACP has been folded into A2A; ANP is about cryptographic identity across
   untrusted networks. Reach for A2A when a worker is a service on another host that other organisations
   also call.

Where this kit already goes further than the surveyed projects: dead-session takeover with an audit
obligation, a lead review gate with numbered rulings, and a log designed to be read by a successor with
no context. The survey found detection everywhere (heartbeats, stale-lock expiry) but resumption of a
predecessor's half-finished work nowhere else.

## Existing projects, verified 2026-09-01

Each row was fetched and checked; stars are as displayed that day. Individual-author projects churn —
treat them as design references, not dependencies.

### Files only (no server)

| Project | What it does | Closest to this kit in |
|---|---|---|
| [avivsinai/agent-message-queue](https://github.com/avivsinai/agent-message-queue) (85★) | Maildir-style message bus: `tmp→new→cur` atomic delivery, no daemon; a swarm mode joins Claude Code Agent Teams | atomic file delivery ≈ atomic slot claims |
| [Dicklesworthstone/claude_code_agent_farm](https://github.com/Dicklesworthstone/claude_code_agent_farm) (915★) | N peer agents claim work via `coordination/agent_locks/` JSON; stale locks expire after 2 h | lock directories + stale-lock expiry (no master, no messaging) |
| [aws-samples/sample-claude-code-agent-team](https://github.com/aws-samples/sample-claude-code-agent-team) (55★) | lead orchestrator + up to 12 coding/DevOps/review agents over shared `spec.md/tasks.md/review.md`; a 3-cycle review cap | the only other explicit review gate |
| [am-will/swarms](https://github.com/am-will/swarms) (230★) | one `plan.md` with a `depends_on` task graph; orchestrator runs waves, verifies between them | PLAN.md-driven master/worker |
| [pikehouse/crew](https://github.com/pikehouse/crew) (pre-release) | REPL orchestrator spawns worktree workers; `.crew/state.json` + logs; resumes dead workers via `--resume` | master REPL + N worker CLI sessions |
| [AnastasiyaW/codex-claude-code-config](https://github.com/AnastasiyaW/codex-claude-code-config) (147★) | append-only `handoffs/*.md` read by a SessionStart hook; advisory lock files | append-only handoff logs |
| [primeline-ai/claude-tmux-orchestration](https://github.com/primeline-ai/claude-tmux-orchestration) (39★) | `_orchestrator/inbox/`, append-only `log.jsonl`, per-worker status JSON, `.ready` handshake, heartbeat stall detection; tmux as transport | inbox + append-only log + heartbeats |
| [battysh/batty](https://github.com/battysh/batty) (53★) | git-committed Markdown kanban, OS file locks for claims, Architect → Manager → Engineers; Rust daemon control plane | every state change is a commit |
| [requix/kiro-team](https://github.com/requix/kiro-team) (38★) | tool-gated roles: the lead can read/delegate but not write; builders write; a validator is read-only | review gate by role separation |
| [ianzepp/claude-workers](https://github.com/ianzepp/claude-workers) | `task.json` per worker home + GitHub labels for claims | pure files, no tmux |
| [AvivK5498/The-Claude-Protocol](https://github.com/AvivK5498/The-Claude-Protocol) (346★) | 13 hooks that block bad actions; git-native "beads" tickets; orchestrator never writes code | hook-enforced hard rules |

### MCP servers for coordination

| Project | What it does | Notes |
|---|---|---|
| [Dicklesworthstone/mcp_agent_mail](https://github.com/Dicklesworthstone/mcp_agent_mail) (2.1k★) + [Rust rewrite](https://github.com/Dicklesworthstone/mcp_agent_mail_rust) | "Gmail for coding agents": Streamable-HTTP/stdio MCP, messages archived as Markdown in Git + SQLite, file-reservation leases, a human overseer identity | best persistence/audit story in the MCP set; **poll-only** (`fetch_inbox`), no blocking receive |
| [louislva/claude-peers-mcp](https://github.com/louislva/claude-peers-mcp) (2.2k★) | per-machine broker daemon (SQLite) so Claude Code sessions message each other with ~1 s polling | live-ish messaging; no persistence across restarts; no roles |
| [Martian-Engineering/maniple](https://github.com/Martian-Engineering/maniple) (49★) | manager session drives worker terminals (tmux/iTerm2) via MCP tools; re-adopts orphaned workers after a manager restart | explicit manager/worker; closest MCP control-plane match |
| [michael-abdo/tmux-claude-mcp-server](https://github.com/michael-abdo/tmux-claude-mcp-server) (18★) | one shared MCP server exposes spawn/send/read; Executive → Manager → Specialist access control; `state/instances.json` | real role enforcement; tmux-bound |
| [rinadelph/Agent-MCP](https://github.com/rinadelph/Agent-MCP) (1.3k★) | Admin/Worker over MCP + a RAG knowledge graph as shared memory | workers are short-lived (idle-killed), not long-running sessions |
| [madebyaris/agent-orchestration](https://github.com/madebyaris/agent-orchestration) (15★) | MCP tools over a per-project SQLite: `task_claim`, `memory_set`, a research gate before claiming | task board as MCP |
| [gilbarbara/agent-hub-mcp](https://github.com/gilbarbara/agent-hub-mcp) (32★) | stdio MCP, flat JSON state under `~/.agent-hub`, `send_message`/`sync()` | daemon-free; pull only |
| [AndrewDavidRivers/multi-agent-coordination-mcp](https://github.com/AndrewDavidRivers/multi-agent-coordination-mcp) (7★) | HTTP+SSE coordinator, SQLite, auto file locks on claim, dependency-blocked tasks | closest to semantic task blocking; very early |
| [multiagentcognition/macp](https://github.com/multiagentcognition/macp) (draft) | standard MCP resources + `notifications/resources/updated` to push inbox envelopes mid-turn | the clearest wake-on-message design; unadopted draft spec |
| [dvcrn/mcp-server-subagent](https://github.com/dvcrn/mcp-server-subagent) (15★) | `ask_parent` / `reply_subagent`: bidirectional master↔worker Q&A over MCP | minimal; poll-based |
| [block/agent-task-queue](https://github.com/block/agent-task-queue) (66★) | SQLite FIFO queue as MCP to serialise expensive builds/tests | a contention valve, not coordination |
| [ruvnet/ruflo](https://github.com/ruvnet/ruflo) (70k★, ex-claude-flow) | ~210 MCP tools, queen-led swarm, vector memory | heavyweight framework, not a thin layer |

### tmux / session managers (transport = keystrokes into panes)

[smtg-ai/claude-squad](https://github.com/smtg-ai/claude-squad) (8.4k★, launcher only, no messaging) ·
[dlorenc/multiclaude](https://github.com/dlorenc/multiclaude) (565★, supervisor/workers via tmux + GitHub PRs) ·
[Jedward23/Tmux-Orchestrator](https://github.com/Jedward23/Tmux-Orchestrator) (1.8k★, Orchestrator → PM → Engineer via `send-keys`) ·
[obra/claude-session-driver](https://github.com/obra/claude-session-driver) (107★, controller reads workers' JSONL lifecycle trail) ·
[awslabs/cli-agent-orchestrator](https://github.com/awslabs/cli-agent-orchestrator) (1.2k★, supervisor/worker over tmux + local HTTP; scales to Kubernetes).
Fragile by construction: a pane is a transport with no record and no delivery guarantee.

### Standards

- **A2A** ([a2aproject/A2A](https://github.com/a2aproject/A2A), 25.6k★, Linux Foundation): JSON-RPC over
  HTTP(S) + SSE, Agent Cards for discovery, task objects with state. Peer client/server; built for separately
  deployed services. [Python SDK](https://github.com/a2aproject/a2a-python), [samples](https://github.com/a2aproject/a2a-samples).
- **ACP**: BeeAI's [i-am-bee/acp](https://github.com/i-am-bee/acp) archived Aug 2025 into A2A; AGNTCY's
  [acp-spec](https://github.com/agntcy/acp-spec) archived Apr 2026. Not a live target.
- **ANP** ([AgentNetworkProtocol](https://github.com/agent-network-protocol/AgentNetworkProtocol), 1.4k★):
  decentralised identity (`did:wba`) + encrypted channels for agents across untrusted networks.
- **MCP** ([spec](https://github.com/modelcontextprotocol/modelcontextprotocol)): agent-to-*tool*, not
  agent-to-agent; stdio or Streamable HTTP; client/server, one client per connection. Coordination "over
  MCP" always means a server that both agents call as a tool.
- In-process frameworks (OpenAI Agents SDK handoffs, Google ADK sub-agents, Microsoft Agent Framework /
  Semantic Kernel / AutoGen) assume one process and one runtime loop; they do not span separate CLI sessions.

### Claude Code built-ins (documented at code.claude.com, checked 2026-09-01)

- **Cross-session messaging**: `SendMessage` / `ListAgents` between local sessions (Unix socket), cloud
  sessions and Remote Control; a message to an idle session starts a new turn; `notify_when_idle` gives a
  one-shot idle notice. Plain text; no queue survives a dead receiver.
- **Agent Teams** (experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): a lead spawns named teammates
  with a shared task list under `~/.claude/teams/` and `~/.claude/tasks/`; teammates message directly.
  In-process teammates do not survive `/resume`.
- **Hooks**: `Stop`, `Notification`, `SessionStart`, `TeammateIdle`, `TaskCompleted`…; an async hook can
  re-wake an idle session (`asyncRewake`); hooks see `CLAUDE_CODE_MESSAGING_SOCKET`.
- **MCP channels**: an MCP server started with `--channels` can push messages into a session (CI results,
  alerts). This is the sanctioned "push" path if you ever build the thin server in point 3 above.

### What none of them do

From the survey's gap list: no project pairs a durable, human-auditable log with real-time push in one
system; none combines dead-session detection with safe resumption of a predecessor's partial work; none
enforces a review gate inside the messaging layer; nothing goes multi-machine without heavyweight
infrastructure; and there is no shared wire format — every tool defines its own. The first two are what
this kit's protocol adds on top of plain files.
