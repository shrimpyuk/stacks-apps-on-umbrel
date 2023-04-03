#!/bin/sh

# Test script for wait-for.sh

set -e

# Test variables
TEST_HOST="localhost"
TEST_PORT="12349"
TEST_COMMAND="echo_success"

echo_success() {
    echo "Success"
}

# Start a temporary test server in the background
python3 -m http.server $TEST_PORT &

# Test the script with different options
./wait-for.sh $TEST_HOST:$TEST_PORT
./wait-for.sh $TEST_HOST:$TEST_PORT -t 30
./wait-for.sh -h $TEST_HOST -p $TEST_PORT -t 30
./wait-for.sh --host=$TEST_HOST --port=$TEST_PORT --timeout=30
./wait-for.sh $TEST_HOST:$TEST_PORT -q
./wait-for.sh $TEST_HOST:$TEST_PORT -s -- $TEST_COMMAND
./wait-for.sh $TEST_HOST:$TEST_PORT -t 30 -s -- $TEST_COMMAND

# Test the script with a non-existent host and port
if ./wait-for.sh nonexistent_host:54329 -t 5; then
    exit 1
fi

if ./wait-for.sh $TEST_HOST:54329 -t 5; then
    exit 1
fi

# Kill the temporary test server
kill %1

echo "All tests passed"
