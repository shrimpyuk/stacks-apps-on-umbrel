#!/usr/bin/env sh

sleep=10

echo ""
echo ""
echo "**********************************"
echo "   Beginning Stacks Quick Sync"
echo "**********************************"
echo ""
echo ""

cd /app || exit

chown -R "1000:1000" bns-data event-replay stacks-blockchain gotty scripts

chmod +x scripts/quick-sync.sh scripts/bns.sh

# Download Stacks 1.0 BNS Data not sure this is even necessary when importing archive from Hiro
BNS_IMPORT_DIR="/app/bns-data" USER_ID="1000:1000" ./scripts/bns.sh

# Download stacks blockchain api data via postgres dump
SERVICE=postgres USER_ID="1000:1000" IMPORT=true ./scripts/quick-sync.sh

# Download stacks blockchain data
SERVICE=stacks-blockchain USER_ID="1000:1000" ./scripts/quick-sync.sh

chown -R "1000:1000" /app/db

while true; do
  echo ""
  echo "Quick Sync Complete"
  echo "Uninstall Quick Sync App and Install Stacks Blockchain App"
  sleep $sleep
done
