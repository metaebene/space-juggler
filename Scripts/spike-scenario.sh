#!/bin/zsh
# Runs the broker spike without a person at the device (docs/spike.md): start on demand, front beats background,
# handover to a newer broker, crash and restart of the newest. Seizes any attached SpaceMouse for about 20 s.
# Usage: Scripts/spike-scenario.sh [scratch-dir]
set -u
cd "${0:A:h}/.."
swift build --product space-juggler-cli >/dev/null 2>&1 || { echo "build failed"; exit 1; }
spike="$(swift build --show-bin-path)/space-juggler-cli"
export SPACE_JUGGLER_HOME="${1:-$(mktemp -d)}"
mkdir -p "$SPACE_JUGGLER_HOME"
rm -f "$SPACE_JUGGLER_HOME"/{broker.log,newest.json}
front="$(lsappinfo info -only bundleid "$(lsappinfo front)" | sed -n 's/.*"\(.*\)"/\1/p')"
echo "SPACE_JUGGLER_HOME=$SPACE_JUGGLER_HOME, frontmost app: $front"

step() { echo; echo "== $*"; }
show_status() { "$spike" status | python3 -c 'import json,sys; s=json.load(sys.stdin); print("broker v%d pid %d, front %s" % (s["version"], s["processID"], s["frontmostApp"])); [print("  device", d["name"], d["id"], d["state"]) for d in s["devices"]]; [print("  client", c["name"], "HOLDS" if c["holds"] else "-") for c in s["clients"]]'; }

step "1. Stagehand (background) starts alone: it has to start broker v1"
"$spike" client --name Stagehand --background --version 1 --seconds 22 --quiet > "$SPACE_JUGGLER_HOME/stagehand.log" &
sleep 2; show_status

step "2. Kugelblitz claims the frontmost app ($front): front beats background"
"$spike" client --name Kugelblitz --app "$front" --version 1 --seconds 20 --quiet > "$SPACE_JUGGLER_HOME/kugelblitz.log" &
sleep 1.5; show_status

step "3. Space Glider brings broker v2: v1 hands over, everyone reconnects"
"$spike" client --name Glider --app com.apple.Safari --version 2 --seconds 18 --quiet > "$SPACE_JUGGLER_HOME/glider.log" &
sleep 3; show_status

step "4. Broker crashes (kill -9): a client restarts the newest broker (v2), even Stagehand's own is v1"
kill -9 "$("$spike" status | python3 -c 'import json,sys; print(json.load(sys.stdin)["processID"])')"
sleep 3; show_status

step "5. Kugelblitz quits: the background claim gets the SpaceMouse again"
pkill -f "space-juggler-cli client --name Kugelblitz"
sleep 1; show_status

wait
step "Clients"
cat "$SPACE_JUGGLER_HOME"/stagehand.log "$SPACE_JUGGLER_HOME"/kugelblitz.log "$SPACE_JUGGLER_HOME"/glider.log | sort -n
step "Broker log"
cut -d" " -f2- "$SPACE_JUGGLER_HOME/broker.log"
