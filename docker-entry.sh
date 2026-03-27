#!/bin/sh
set -e

Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
XVFB_PID=$!
sleep 1

cleanup() {
    kill $XVFB_PID 2>/dev/null
    wait $XVFB_PID 2>/dev/null
}
trap cleanup EXIT TERM INT

exec npx electron . --webui --no-sandbox  "$@"
