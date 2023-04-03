#!/usr/bin/env sh



./scripts/bns.sh

SERVICE=stacks-blockchain-api ./scripts/quick-sync
#Event import and playback successful.

# The command to be executed inside the stacks-blockchain-api container
CMD="node ./lib/index.js import-events --file /event-replay/stacks-node-events.tsv --wipe-db --force"

# Send the command to the stacks-blockchain-api container via the network
echo "$CMD" | nc "$APP_STACKS_API_IP" "$APP_STACKS_API_CMD_PORT"

SERVICE=stacks-blockchain ./scripts/quick-sync
