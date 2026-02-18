#!/bin/sh
# Fix macOS -> Linux .bin/ permissions before running any command
[ -d node_modules/.bin ] && chmod +x node_modules/.bin/* 2>/dev/null
exec /usr/local/bin/pnpm "$@"
