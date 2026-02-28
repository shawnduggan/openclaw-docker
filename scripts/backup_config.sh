#!/bin/bash
# Push workspace config and documents to GitHub for versioned backup
# Uses Git Data API for atomic commits (no .git dir needed)

JARVIS_REPO="shawnduggan/Jarvis"
SRC_DIR="/home/node/.openclaw/workspace"
DOCS_DIR="/home/node/.openclaw/workspace/documents"

# Extra files outside the workspace root to backup
EXTRA_FILES=(
  "/home/node/.openclaw/openclaw.json"
)

echo "=== GitHub Backup $(date) ==="

if ! command -v gh &>/dev/null; then
  echo "⚠ gh CLI not found — aborting"
  exit 1
fi

if ! gh auth status &>/dev/null 2>&1; then
  echo "⚠ gh not authenticated — aborting"
  exit 1
fi

# Temp file to collect tree entries (one JSON object per line)
TREE_FILE=$(mktemp)
trap 'rm -f "$TREE_FILE"' EXIT
FILE_COUNT=0

# Helper: add a file to the tree
add_file() {
  local repo_path="$1"
  local local_path="$2"
  [ -f "$local_path" ] || return

  # Create blob via API (base64 encode)
  local b64
  b64=$(base64 < "$local_path")

  # Write JSON body to temp file
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

# 1) Config files from workspace root (*.md, *.json)
echo "  Adding workspace config files..."
for file in "$SRC_DIR"/*.md "$SRC_DIR"/*.json; do
  [ -f "$file" ] || continue
  filename=$(basename "$file")
  add_file "config/$filename" "$file"
  echo "    + config/$filename"
done

# 2) Extra files (openclaw.json from repo root)
for file in "${EXTRA_FILES[@]}"; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    add_file "config/$filename" "$file"
    echo "    + config/$filename"
  fi
done

# 3) All documents subdirectories
for dir in "$DOCS_DIR"/*/; do
  [ -d "$dir" ] || continue
  subdir=$(basename "$dir")
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

# 4) Memory folder (daily notes, research, lessons)
MEMORY_DIR="$SRC_DIR/memory"
if [ -d "$MEMORY_DIR" ]; then
  echo "  Adding memory..."
  while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    case "$filename" in
      .*|.gitkeep) continue ;;
    esac
    rel_path="${file#$SRC_DIR/}"
    add_file "$rel_path" "$file"
    echo "    + $rel_path"
  done < <(find "$MEMORY_DIR" -type f -name "*.md" -print0)
fi

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "⚠ No files to push"
  exit 0
fi

echo "  Creating tree with $FILE_COUNT files..."

# Build tree JSON and create via API
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
