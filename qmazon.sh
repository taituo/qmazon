# Directories
mkdir -p ~/.local/bin
mkdir -p ~/.local/share/qmazon/sessions

# Install ~/.local/bin/qmazon
cat > ~/.local/bin/qmazon <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# -------- settings --------
# Usage: qmazon [session suffix] [-- command and args...]
#   qmazon                # session: qmazon, command: q
#   qmazon foo            # session: qmazon-foo, command: q
#   qmazon foo -- amq -v  # session: qmazon-foo, command: amq -v
NAME="${1-}"
if [[ "$NAME" == "--" ]]; then NAME=""; shift; fi
CMD=( q )  # default command
if [[ $# -gt 0 ]]; then
  # if there is "--", take the command after it
  while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
  if [[ "${1-}" == "--" ]]; then shift; fi
  if [[ $# -gt 0 ]]; then CMD=( "$@" ); fi
fi

SESSION="qmazon${NAME:+-$NAME}"
BASE="$HOME/.local/share/qmazon/sessions/$SESSION"
LOGDIR="$BASE/logs"
POINTER="$BASE/latest_log"
PATTERN="${PATTERN:-Allow this action.*\\[y/n/t\\]:}"   # change if the prompt differs
MON_DEBOUNCE="${MON_DEBOUNCE:-1}"                       # seconds; prevents double pushes
mkdir -p "$LOGDIR"

# start tmux server eagerly (faster first launch)
tmux start-server 2>/dev/null || true

# Create/open the main session, window 0 = q
tmux new-session -Ad -s "$SESSION" -n q

# Pane 0.0: start logging before the command runs so the prompt isn't missed
STAMP="$(date +%Y%m%d-%H%M%S)"
LOGFILE="${LOGDIR}/${SESSION}-$(echo "${CMD[*]}" | awk '{print $1}')-${STAMP}.log"
tmux pipe-pane -o -t "${SESSION}:0.0" "cat >> \"$LOGFILE\"" || true
printf '%s\n' "$LOGFILE" > "$POINTER"

# Run the command in the q window with PATH/aliases
tmux respawn-pane -k -t "${SESSION}:0.0" "bash -lc '\"${CMD[0]}\" ${CMD[@]:1}'"

# Create and start a background monitor that tails this session log
MON_SCRIPT="/tmp/qmazon-monitor-${SESSION}.sh"
cat > "$MON_SCRIPT" <<MON
#!/usr/bin/env bash
set -euo pipefail
TARGET="${SESSION}:0.0"
LOGFILE="$LOGFILE"
PATTERN="$PATTERN"
DEBOUNCE="$MON_DEBOUNCE"
STATE="$BASE/.last_push"
mkdir -p "$BASE"
: > "\$STATE" || true
last=0
tail -n0 -F "\$LOGFILE" | while IFS= read -r line; do
  printf '%s\n' "\$line" | grep -E "\$PATTERN" >/dev/null || continue
  now=\$(date +%s)
  if [ \$((now-last)) -ge \$DEBOUNCE ]; then
    tmux send-keys -t "\$TARGET" "t" Enter
    last=\$now; echo "\$now" > "\$STATE"
    printf '%s monitor: pushed t\n' "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "\$LOGFILE"
  fi
done
MON
chmod +x "$MON_SCRIPT"
tmux run-shell -b "$MON_SCRIPT &"   # run inside the tmux server background

# (optional) separate log session (quick way to view logs)
LOG_SESSION="${SESSION}-logs"
if ! tmux has-session -t "$LOG_SESSION" 2>/dev/null; then
  tmux new-session -Ad -s "$LOG_SESSION" -n logs "printf 'Following: %s\n' \"$LOGFILE\"; tail -F \"$LOGFILE\""
else
  tmux send-keys -t "${LOG_SESSION}:logs.0" C-c "printf 'Following: %s\n' \"$LOGFILE\"; tail -F \"$LOGFILE\"" C-m
fi

# Keep focus on the main session window 0
tmux select-window -t "${SESSION}:0"
tmux select-pane   -t "${SESSION}:0.0"

# Attach/switch to the session
if [ -z "${TMUX:-}" ]; then
  tmux attach -t "$SESSION"
else
  tmux switch-client -t "$SESSION"
  tmux select-window -t "${SESSION}:0"
fi
EOF

chmod +x ~/.local/bin/qmazon
echo "OK. Launch: qmazon | qmazon foo | qmazon foo -- amq -v"

