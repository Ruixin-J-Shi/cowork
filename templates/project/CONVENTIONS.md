# House conventions — @@PROJECT@@

Rules that outlive the task they were learned in. The lead adds a line whenever a review or an incident produces a rule; cite the origin (who, which task, when). Seats read this file at boot and after every all-hands.

## Process (seeded from the cowork kit; keep what applies)

1. **Stage explicit paths, never `git add -A`, while any seat is mid-task** — the shared tree always contains someone's WIP. Stage from the DONE report's file list.
2. **Gate commands must propagate failure.** `npm test | grep ...` reports grep's exit code. Run the gate bare; read output separately.
3. **Release verification happens in a clean checkout**, not the shared working tree — WIP can mask or cause failures the commit does not have.
4. **A fixture must never do the work the product is supposed to do.** Drive only what a deployment drives; assert the product created the state.
5. **A check that cannot fail is not a check.** Never swallow errors inside verification code. Name checks by what is measured, not by the story of what should happen.
6. **A regression test must be shown to fail against the unfixed code.** Keep or replay the pre-fix reproduction; the delta is the proof.
7. **Integrity rules are asserted over the full population of decisions**, not the subset a test happened to observe.
8. **Baseline before fix.** When a fix is measured by a delta, record the baseline first and never edit it after.
9. **Never invent data.** A view renders what the source returned; a getter that serves mock content when a fetch fails lets a broken endpoint ship looking healthy. Unverified or simulated behaviour is labelled as such where users see it.
10. **A destructive script driven by an environment variable must be unable to leave its own project** — resolve the path and refuse anything outside the root, or it is one typo from a disaster.
11. **Disposable run output accretes, it is not deleted**: each run writes its own timestamped directory under a gitignored path; the lead prunes to trash at milestones.
12. **`rm` in any form never appears in ad-hoc shell** — see PROTOCOL.md Hard Rule 3; prefer commands that leave nothing to clean up.

## Time

## Ownership & builds

## Testing

- Assert the exit status alongside stdout; a pipeline's status is its last stage's, and `make`'s failure code is make's, not the inner command's.
- Assert the trailing newline: `$(cmd)` strips it, so capture with a sentinel (`out="$(cmd; printf '@%s' "$?")"`) and prove the sentinel is load-bearing with a stub that differs only by the newline.
- Portability: this project's tooling runs on macOS bash 3.2 + BSD userland unless stated otherwise — no `${x^^}`, `mapfile`, associative arrays, `cat -A`, or GNU-only `stat`/`sed -i`/`date -d`. BSD `od -c` prints nothing for an empty file; prove emptiness with `wc -c`.
- Run checks as `bash script.sh`, never typed at a zsh prompt: zsh does not word-split unquoted `$var` and names `PIPESTATUS` differently, so prompt-typed checks can invent or hide a failure.

## Security

- Secrets (API keys, signing keys, credentials) never appear in any inbox, outbox, artifact or commit. They travel by hand (a password manager, AirDrop, USB) or are minted fresh into the environment for one run.
- A harness or script that could reach a live target refuses anything but localhost in code, before its first request — live credentials are usually nearby, and discipline is not a guard.
