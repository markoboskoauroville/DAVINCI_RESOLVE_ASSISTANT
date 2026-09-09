#!/bin/sh
# install.sh — put the DaVinci Resolve Assistant's scripts into Resolve, then check.
#
#   ~/Developer/resolve-scripts/install.sh
#
# Copies Toggle HD UHD.py, Previous Page.py and Create Timeline.py into Resolve's Scripts/Utility
# folder (Workspace > Scripts > Utility inside Resolve; Resolve reads the folder
# every time the menu opens, no restart needed) and runs check.py.

set -e
HERE=$(cd "$(dirname "$0")" && pwd)
UTILITY="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"
PYTHON="$HOME/.pyenv/versions/3.10.14/bin/python3"
[ -x "$PYTHON" ] || PYTHON=python3

mkdir -p "$UTILITY"
for name in "Toggle HD UHD.py" "Previous Page.py" "Create Timeline.py"; do
    cp "$HERE/$name" "$UTILITY/$name"
    echo "installed  $name"
done
echo
exec "$PYTHON" "$HERE/check.py"
