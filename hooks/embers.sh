#!/bin/bash
# embers: keep an idle Claude Code session's prompt cache warm.
#
# Runs as a Claude Code Stop hook. When a turn ends, it starts one detached
# timer for the session. If the session's tmux pane stays quiet for the delay
# (58 minutes by default, just inside a one-hour cache lifetime), the timer
# types a one-line ping into the pane. Answering it reads the cache and keeps
# it warm. A turn the ping started counts toward a cap; any other turn resets
# the count, so a session that stays idle goes cold after the cap.
#
# Outside tmux it does nothing.
#
# Settings (environment):
#   EMBERS_DELAY   seconds of quiet before a ping (default 3480)
#   EMBERS_CAP     pings in a row before giving up (default 8)
#   EMBERS_PING    the text typed into the pane
#   EMBERS_STATE   state directory (default ~/.claude/state/embers)
#
# MIT License. See LICENSE.
set -u

DELAY="${EMBERS_DELAY:-3480}"
CAP="${EMBERS_CAP:-8}"
PING="${EMBERS_PING:-keep-warm ping (automatic, from the idle hook): reply with just \"ok\" and take no other action.}"
STATE="${EMBERS_STATE:-$HOME/.claude/state/embers}"

input=$(cat)
pane="${TMUX_PANE:-}"
[ -n "$pane" ] || exit 0
sid=$(printf '%s' "$input" | /usr/bin/env python3 -c 'import json,sys; print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)
[ -n "$sid" ] || exit 0

mkdir -p "$STATE"
f="$STATE/$sid"

# Was the turn that just ended started by our own ping?
if [ -e "$f.pinged" ]; then
  rm -f "$f.pinged"
  count=$(( $(cat "$f.count" 2>/dev/null || echo 0) + 1 ))
else
  count=0
fi
echo "$count" > "$f.count"
[ "$count" -ge "$CAP" ] && exit 0

token="$(date +%s).$$"
echo "$token" > "$f.token"

(
  sleep "$DELAY"
  # A later turn armed its own timer, so this one stands down.
  [ "$(cat "$f.token" 2>/dev/null)" = "$token" ] || exit 0
  # Only a quiet pane is idle: a busy session redraws its pane.
  last=$(tmux display-message -p -t "$pane" '#{window_activity}' 2>/dev/null) || exit 0
  [ -n "$last" ] && [ $(( $(date +%s) - last )) -ge $(( DELAY - 120 )) ] || exit 0
  touch "$f.pinged"
  tmux send-keys -t "$pane" -l "$PING" && tmux send-keys -t "$pane" Enter
) </dev/null >/dev/null 2>&1 &
disown
exit 0
