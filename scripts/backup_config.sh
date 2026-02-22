#!/bin/bash
# Backup workspace config files to documents/config, then push to GitHub
# This script COPIES files - it never deletes or moves source files

BACKUP_DIR="/home/node/.openclaw/workspace/documents/config"
DATE_STAMP=$(date '+%Y%m%d')
SRC_DIR="/home/node/.openclaw/workspace"
DOCS_DIR="/home/node/.openclaw/workspace/documents"
JARVIS_REPO="shawnduggan/Jarvis"

# Extra files outside the workspace root to backup
EXTRA_FILES=(
  "/home/node/.openclaw/openclaw.json"
  "/home/node/.openclaw/cron/jobs.json"
)

echo "=== Config Backup $(date) ==="

# Backup all .md and .json files from workspace root (dynamic scan)
for file in "$SRC_DIR"/*.md "$SRC_DIR"/*.json; do
  [ -f "$file" ] || continue
  filename=$(basename "$file")
  dst="$BACKUP_DIR/$filename"
  if [ -f "$dst" ]; then
    mv "$dst" "$BACKUP_DIR/$filename.bak-$DATE_STAMP"
  fi
  cp "$file" "$dst"
  echo "✓ Copied: $filename"
done

# Backup extra files from outside workspace
for file in "${EXTRA_FILES[@]}"; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    dst="$BACKUP_DIR/$filename"
    if [ -f "$dst" ]; then
      mv "$dst" "$BACKUP_DIR/$filename.bak-$DATE_STAMP"
    fi
    cp "$file" "$dst"
    echo "✓ Copied: $filename"
  fi
done

# Backup skills folder (all .md files)
SKILLS_DIR="$SRC_DIR/skills"
if [ -d "$SKILLS_DIR" ]; then
  for file in "$SKILLS_DIR"/*.md; do
    [ -f "$file" ] || continue
    filename=$(basename "$file")
    dst="$BACKUP_DIR/$filename"
    if [ -f "$dst" ]; then
      mv "$dst" "$BACKUP_DIR/$filename.bak-$DATE_STAMP"
    fi
    cp "$file" "$dst"
    echo "✓ Copied skill: $filename"
  done
fi

echo "=== Local backup complete ==="

# ─── Offsite push to GitHub ─────────────────────────────────────────
# Push config and documents to the private Jarvis repo using gh api.
# Uses the Git Data API for a single atomic commit (no .git dir needed).
# Note: uses gh --jq and node (not jq) since jq isn't in the container.

if ! command -v gh &>/dev/null; then
  echo "⚠ gh CLI not found — skipping offsite push"
  exit 0
fi

if ! gh auth status &>/dev/null 2>&1; then
  echo "⚠ gh not authenticated — skipping offsite push"
  exit 0
fi

echo "=== Pushing to $JARVIS_REPO ==="

# Temp file to collect tree entries (one JSON object per line)
TREE_FILE=$(mktemp)
trap 'rm -f "$TREE_FILE"' EXIT
FILE_COUNT=0

# Helper: add a file to the tree
add_file() {
  local repo_path="$1"
  local local_path="$2"
  [ -f "$local_path" ] || return

  # Create blob via API (base64 encode, use gh --jq to extract sha)
  local b64
  b64=$(base64 < "$local_path")

  # Write JSON body to temp file to avoid heredoc quoting issues with large base64
  local body_file
  body_file=$(mktemp)
  node -e "process.stdout.write(JSON.stringify({content:process.argv[1],encoding:'base64'}))" "$b64" > "$body_file"

  local sha
  sha=$(gh api "repos/$JARVIS_REPO/git/blobs" --input "$body_file" --jq '.sha' 2>/dev/null)
  rm -f "$body_file"

  if [ -z "$sha" ] || [ "$sha" = "null" ]; then
    echo "  ✗ Failed to create blob for $repo_path"
    return
  fi

  # Append tree entry as JSON line
  node -e "process.stdout.write(JSON.stringify({path:process.argv[1],mode:'100644',type:'blob',sha:process.argv[2]})+'\n')" "$repo_path" "$sha" >> "$TREE_FILE"
  FILE_COUNT=$((FILE_COUNT + 1))
}

# 1) Config files from backup dir (skip .bak-* files, .gitkeep)
echo "  Adding config files..."
for file in "$BACKUP_DIR"/*; do
  [ -f "$file" ] || continue
  filename=$(basename "$file")
  case "$filename" in
    *.bak-*|.gitkeep) continue ;;
  esac
  add_file "config/$filename" "$file"
  echo "    + config/$filename"
done

# Config subdirectories (dynamic scan)
for config_subdir in "$BACKUP_DIR"/*/; do
  [ -d "$config_subdir" ] || continue
  subdir_name=$(basename "$config_subdir")
  while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    case "$filename" in
      .*|.gitkeep) continue ;;
    esac
    rel_path="${file#$BACKUP_DIR/}"
    add_file "config/$rel_path" "$file"
    echo "    + config/$rel_path"
  done < <(find "$config_subdir" -type f -print0)
done

# 2) All documents subdirectories (dynamic scan, skip config to avoid recursion)
for dir in "$DOCS_DIR"/*/; do
  [ -d "$dir" ] || continue
  subdir=$(basename "$dir")
  # Skip config dir (that's already handled above) and hidden dirs
  case "$subdir" in
    config|.*) continue ;;
  esac
  echo "  Adding documents/$subdir..."
  while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    case "$filename" in
      .*|.gitkeep) continue ;;
    esac
    rel_path="${file#$DOCS_DIR/}"
    add_file "documents/$rel_path" "$file"
    echo "    + documents/$rel_path"
  done < <(find "$dir" -type f -print0)
done

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "⚠ No files to push"
  exit 0
fi

echo "  Creating tree with $FILE_COUNT files..."

# Build tree JSON from collected entries and create via API
TREE_BODY=$(node -e "
  const lines = require('fs').readFileSync(process.argv[1],'utf8').trim().split('\n');
  const tree = lines.map(l => JSON.parse(l));
  process.stdout.write(JSON.stringify({tree}));
" "$TREE_FILE")

TREE_SHA=$(echo "$TREE_BODY" | gh api "repos/$JARVIS_REPO/git/trees" --input - --jq '.sha')
if [ -z "$TREE_SHA" ] || [ "$TREE_SHA" = "null" ]; then
  echo "✗ Failed to create tree"
  exit 1
fi

# Get current HEAD sha
HEAD_SHA=$(gh api "repos/$JARVIS_REPO/git/ref/heads/main" --jq '.object.sha')

# Create commit
COMMIT_MSG="Backup $(date '+%Y-%m-%d %H:%M')"
COMMIT_BODY=$(node -e "process.stdout.write(JSON.stringify({message:process.argv[1],tree:process.argv[2],parents:[process.argv[3]]}))" "$COMMIT_MSG" "$TREE_SHA" "$HEAD_SHA")

COMMIT_SHA=$(echo "$COMMIT_BODY" | gh api "repos/$JARVIS_REPO/git/commits" --input - --jq '.sha')
if [ -z "$COMMIT_SHA" ] || [ "$COMMIT_SHA" = "null" ]; then
  echo "✗ Failed to create commit"
  exit 1
fi

# Update main ref
node -e "process.stdout.write(JSON.stringify({sha:process.argv[1]}))" "$COMMIT_SHA" | \
  gh api "repos/$JARVIS_REPO/git/refs/heads/main" -X PATCH --input - >/dev/null

echo "=== Pushed to $JARVIS_REPO ($FILE_COUNT files) ==="
