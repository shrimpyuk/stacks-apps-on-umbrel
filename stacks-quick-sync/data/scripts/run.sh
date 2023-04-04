#!/usr/bin/env sh

sleep=10

chown -R "1000:1000" bns-data event-replay stacks-blockchain gotty scripts

cd /app || exit

chmod +x scripts/quick-sync.sh scripts/bns.sh

BNS_IMPORT_DIR="/app/bns-data" USER_ID="1000:1000" ./scripts/bns.sh

SERVICE=stacks-blockchain-api USER_ID="1000:1000" ./scripts/quick-sync.sh
#Event import and playback successful.

SERVICE=stacks-blockchain USER_ID="1000:1000" ./scripts/quick-sync.sh

node ./lib/index.js import-events --file /app/event-replay/stacks-node-events.tsv --wipe-db --force

while true; do
    echo ""
    echo "Quick Sync Complete"
    echo "Uninstall Quick Sync App and Install Stacks Blockchain App"
    echo "sleep $sleep"
    sleep $sleep
done
