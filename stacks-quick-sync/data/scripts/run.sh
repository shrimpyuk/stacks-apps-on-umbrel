#!/usr/bin/env sh

sleep=10

echo ""
echo ""
echo "*********************************"
echo "   Beginning Stacks Quick Sync"
echo "*********************************"
echo ""
echo ""

chown -R "1000:1000" bns-data event-replay stacks-blockchain gotty scripts

cd /app || exit

chmod +x scripts/quick-sync.sh scripts/bns.sh

# Download Stacks 1.0 BNS Data not sure this is even necessary when importing event-replay from Hiro
BNS_IMPORT_DIR="/app/bns-data" USER_ID="1000:1000" ./scripts/bns.sh

# Download stacks blockchain api data
SERVICE=stacks-blockchain-api USER_ID="1000:1000" ./scripts/quick-sync.sh

echo "Extracting API event-replay...."
gzip -dc event-replay/mainnet-stacks-blockchain-api-latest.gz >event-replay/stacks-node-events.tsv
echo ""
echo "Done extracting API event-replay"
echo ""

if [ -f "/app/event-replay/stacks-node-events.tsv" ]; then
  # get the size of the local file
  local_size=$(stat -c%s "/app/event-replay/stacks-node-events.tsv")

  # check if the size is greater than 13GB
  if [ "$local_size" -lt 13771387596 ]; then
    echo "Extracted file size is less than 13GB. Extracting again"
    gzip -dc event-replay/mainnet-stacks-blockchain-api-latest.gz >event-replay/stacks-node-events.tsv
  else
    echo "Extracted file size is greater than or equal to 13GB."
  fi
else
  echo "Extracted file not found."
  gzip -dc event-replay/mainnet-stacks-blockchain-api-latest.gz >event-replay/stacks-node-events.tsv
fi

# Download stacks blockchain data
SERVICE=stacks-blockchain USER_ID="1000:1000" ./scripts/quick-sync.sh

# check if the downloaded file exists and if its size is greater than 40GB as no Content-Length header given from archive
if [ -f "/app/stacks-blockchain/mainnet-stacks-blockchain-latest.tar.gz" ]; then
  # get the size of the local file
  local_size=$(stat -c%s "/app/stacks-blockchain/mainnet-stacks-blockchain-latest.tar.gz")

  # check if the size is greater than 40GB
  if [ "$local_size" -lt 42949672960 ]; then
    echo "Downloaded file size is less than 40GB. Re-running quick-sync.sh"
    SERVICE=stacks-blockchain USER_ID="1000:1000" ./scripts/quick-sync.sh
  else
    echo "Downloaded file size is greater than or equal to 40GB."
  fi
else
  echo "Downloaded file not found."
fi

echo "Extracting Stacks Blockchain Data 93GB+ ...."
tar -xzf "stacks-blockchain/mainnet-stacks-blockchain-latest.tar.gz" -C "stacks-blockchain" --checkpoint=.1000 --checkpoint-action='ttyout=Extracting %T (%d/sec)\r' &&
    rm stacks-blockchain/mainnet-stacks-blockchain-latest.tar.gz
echo ""
echo "Done extracting Stacks Blockchain Data"

echo ""
echo "Setting Stacks Blockchain dir ownership"
echo "chown -R 1000:1000 stacks-blockchain"
chown -R "1000:1000" stacks-blockchain
echo "Done"

echo ""
echo "Running event-replay"
pkill node
node ./lib/index.js import-events --file /app/event-replay/stacks-node-events.tsv --wipe-db --force >> /app/gotty/output.log 2>&1 &

# Wait for the "Event import and playback successful" or "import-events process failed" message
while true; do
  sleep 10
  if grep -q "Event import and playback successful" /app/gotty/output.log; then
    echo "Event import and playback successful"
    break
  elif grep -q "import-events process failed" /app/gotty/output.log; then
    echo "import-events process failed, trying again..."
    # Kill the previous node process
    pkill node
    # Try running the node command again
    node ./lib/index.js import-events --file /app/event-replay/stacks-node-events.tsv --wipe-db --force
  fi
done

while true; do
  echo ""
  echo "Quick Sync Complete"
  echo "Uninstall Quick Sync App and Install Stacks Blockchain App"
  sleep $sleep
done
