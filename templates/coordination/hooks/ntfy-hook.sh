#!/usr/bin/env bash
# Phone notifications for Claude Code Stop/Notification hooks via ntfy (https://ntfy.sh).
# The LEAD session (session_id == ~/.claude/lead-session-id) rings a dedicated topic with
# urgent priority so it can carry its own sound; every other session rings the normal topic.
#
# Install (once per machine):
#   cp coordination/hooks/ntfy-hook.sh ~/.claude/hooks/ && chmod +x ~/.claude/hooks/ntfy-hook.sh
#   ~/.claude/settings.json →
#     "hooks": { "Stop":         [{"hooks":[{"type":"command","command":"bash \"$HOME/.claude/hooks/ntfy-hook.sh\" stop"}]}],
#                "Notification": [{"hooks":[{"type":"command","command":"bash \"$HOME/.claude/hooks/ntfy-hook.sh\" notification"}]}] }
#   The lead writes its session id to ~/.claude/lead-session-id at boot.
# Topics come from <cwd>/coordination/cowork.conf (NTFY_TOPIC, NTFY_TOPIC_LEAD) — per project, automatically —
# falling back to ~/.claude/cowork-ntfy.conf, then to nothing (silent).
# Suppression: the lead touches ~/.claude/lead-ring-skip before ending a no-op turn; the next stop is swallowed.
# NTFY_DRYRUN=1 prints instead of publishing.
EVENT="${1:-stop}"
INPUT="$(cat)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
LEAD="$(tr -d '[:space:]' < "$HOME/.claude/lead-session-id" 2>/dev/null)"
NTFY_TOPIC=""; NTFY_TOPIC_LEAD=""; PROJECT_NAME=""
# shellcheck disable=SC1090,SC1091
[ -f "$HOME/.claude/cowork-ntfy.conf" ] && . "$HOME/.claude/cowork-ntfy.conf"
[ -n "$CWD" ] && [ -f "$CWD/coordination/cowork.conf" ] && . "$CWD/coordination/cowork.conf"
[ -z "$NTFY_TOPIC" ] && exit 0
[ -z "$NTFY_TOPIC_LEAD" ] && NTFY_TOPIC_LEAD="$NTFY_TOPIC"
LABEL="${PROJECT_NAME:-cowork}"

publish() { # title priority tags topic message
  if [ -n "${NTFY_DRYRUN:-}" ]; then echo "DRYRUN: [$4] title='$1' prio=$2 tags=$3 msg='$5'"
  else ntfy publish --title "$1" --priority "$2" --tags "$3" "$4" "$5" >/dev/null 2>&1 || true; fi
}
IS_LEAD=""; [ -n "$SID" ] && [ -n "$LEAD" ] && [ "$SID" = "$LEAD" ] && IS_LEAD=1
if [ -n "$IS_LEAD" ] && [ "$EVENT" = stop ] && [ -f "$HOME/.claude/lead-ring-skip" ]; then rm -f "$HOME/.claude/lead-ring-skip"; exit 0; fi
if [ "$EVENT" = notification ]; then
  MSG="$(printf '%s' "$INPUT" | jq -r '.message // "Claude Code needs your attention"' 2>/dev/null)"
  if [ -n "$IS_LEAD" ]; then publish "$LABEL LEAD needs you" urgent "rotating_light" "$NTFY_TOPIC_LEAD" "$MSG"
  else publish "$LABEL seat" high "bell" "$NTFY_TOPIC" "$MSG"; fi
else
  if [ -n "$IS_LEAD" ]; then publish "$LABEL LEAD" urgent "mortar_board" "$NTFY_TOPIC_LEAD" "Lead finished a turn — update ready"
  else publish "$LABEL seat" default "white_check_mark" "$NTFY_TOPIC" "Task finished"; fi
fi
exit 0
