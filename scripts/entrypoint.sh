#!/bin/sh
# Fix ownership of directories that Docker bind/volume mounts may create as root
for dir in /home/node/.config /home/node/.config/gh; do
  if [ -d "$dir" ]; then
    [ "$(stat -c '%u' "$dir")" != "$(id -u)" ] && sudo chown node:node "$dir"
  else
    mkdir -p "$dir"
  fi
done

exec "$@"
