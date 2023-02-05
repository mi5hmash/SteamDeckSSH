#!/bin/bash

declare -r TOOL_NAME="SteamDeckSSH"

## Don't Sleep (Keep the display on)
systemd-inhibit "./$TOOL_NAME.sh" --who="$TOOL_NAME" --why="Prevent conecction lost issues." --what="sleep:shutdown"