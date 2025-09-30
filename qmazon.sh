# Directories
mkdir -p ~/.local/bin
mkdir -p ~/.local/share/qmazon/sessions

# Install ~/.local/bin/qmazon
cat > ~/.local/bin/qmazon <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

INITIAL_PWD="$(pwd)"
MON_START_DELAY="${MON_START_DELAY:-15}"

random_slug() {
  local verbs=(align blaze bridge charge drift focus glide ignite pivot sync)
  local adjectives=(brisk cobalt lucid mellow nimble rapid solid stellar steady vivid)
  local targets=(beacon circuit vector summit horizon engine nexus channel anchor signal)
  local verb="${verbs[RANDOM % ${#verbs[@]}]}"
  local adjective="${adjectives[RANDOM % ${#adjectives[@]}]}"
  local target="${targets[RANDOM % ${#targets[@]}]}"
  printf '%s-%s-%s' "$verb" "$adjective" "$target"
}

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

if [[ -z "$NAME" ]]; then
  NAME="$(random_slug)"
fi

SESSION="qmazon${NAME:+-$NAME}"
BASE="$HOME/.local/share/qmazon/sessions/$SESSION"
LOGDIR="$BASE/logs"
POINTER="$BASE/latest_log"
PATTERN="${PATTERN:-Allow this action.*\\[y/n/t\\]:}"   # change if the prompt differs
MON_DEBOUNCE="${MON_DEBOUNCE:-1}"                       # seconds; prevents double pushes
mkdir -p "$LOGDIR"

CMD_FILE="$BASE/cmd.args"
printf '%s\0' "${CMD[@]}" > "$CMD_FILE"
CMD_PRETTY="$(printf '%q ' "${CMD[@]}")"
CMD_PRETTY="${CMD_PRETTY% }"
PROMPT_MESSAGE="Session $SESSION: press Enter to start ${CMD_PRETTY:-command} in $INITIAL_PWD"

# start tmux server eagerly (faster first launch)
tmux start-server 2>/dev/null || true

# Create/open the main session, window 0 = q
tmux new-session -Ad -s "$SESSION" -n q

# Pane 0.0: start logging before the command runs so the prompt isn't missed
STAMP="$(date +%Y%m%d-%H%M%S)"
LOGFILE="${LOGDIR}/${SESSION}-$(echo "${CMD[*]}" | awk '{print $1}')-${STAMP}.log"
tmux pipe-pane -o -t "${SESSION}:0.0" "cat >> \"$LOGFILE\"" || true
printf '%s\n' "$LOGFILE" > "$POINTER"

START_SCRIPT="/tmp/qmazon-start-${SESSION}.sh"
cat > "$START_SCRIPT" <<'START'
#!/usr/bin/env bash
set -euo pipefail

CMD_ARR=()
while IFS= read -r -d '' token; do
  CMD_ARR+=("$token")
done < "${QMAZON_CMD_FILE:?Missing QMAZON_CMD_FILE}"
WORKDIR="${QMAZON_START_DIR:?Missing QMAZON_START_DIR}"
PROMPT="${QMAZON_PROMPT:-Press Enter to start}"
SESSION_NAME="${QMAZON_SESSION_NAME:-qmazon}"

cmd_text="$(printf '%q ' "${CMD_ARR[@]}")"
cmd_text="${cmd_text% }"

printf '\n%s\n' "$PROMPT"
printf 'Session: %s\n' "$SESSION_NAME"
printf 'Working directory: %s\n' "$WORKDIR"
printf 'Queued command: %s\n' "$cmd_text"
printf 'Press Enter to continue... '
read -r
printf '\n'
cd "$WORKDIR"
exec "${CMD_ARR[@]}"
START
chmod +x "$START_SCRIPT"

# Run the command in the q window with PATH/aliases
printf -v START_CMD 'env QMAZON_START_DIR=%q QMAZON_CMD_FILE=%q QMAZON_PROMPT=%q QMAZON_SESSION_NAME=%q %q' \
  "$INITIAL_PWD" "$CMD_FILE" "$PROMPT_MESSAGE" "$SESSION" "$START_SCRIPT"
tmux respawn-pane -k -t "${SESSION}:0.0" "$START_CMD"

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
START_DELAY="$MON_START_DELAY"
mkdir -p "$BASE"
: > "\$STATE" || true
last=0
printf 'Waiting %ss before monitoring %s\n' "\$START_DELAY" "$LOGFILE"
sleep "\$START_DELAY"
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
tmux new-window -d -t "$SESSION" -n monitor "$MON_SCRIPT"

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

