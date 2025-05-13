#!/bin/bash

# build-cache-run-swift.sh
# -------------------------
# Hash-based caching script for compiling and running Swift files.
# Avoids unnecessary recompilation and improves execution speed on repeated runs.
#
# # Version: 1.2.0

if [ -z "$1" ]; then
    echo "Usage: $0 <Swift source file> [args...]"
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "Error: File '$1' not found."
    exit 1
fi

SWIFT_FILE="$1"
BASENAME=$(basename "$SWIFT_FILE" .swift)
EXECUTABLE="./$BASENAME"
ARCH=$(uname -m)  # arm64 or x86_64
HASH_FILE="$SWIFT_FILE.archcache"

CURRENT_HASH=$(md5 -q -s "$(md5 -q "$SWIFT_FILE")_$ARCH")
STORED_HASH=$(cat "$HASH_FILE" 2>/dev/null)

if [ "$CURRENT_HASH" != "$STORED_HASH" ] || [ ! -f "$EXECUTABLE" ]; then
    swiftc "$SWIFT_FILE" -o "$EXECUTABLE" || exit 1
    echo "$CURRENT_HASH" > "$HASH_FILE"
fi

shift
"$EXECUTABLE" "$@"
