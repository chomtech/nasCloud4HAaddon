#!/bin/bash
# HA Add-on release script with auto-version bump (nasCloud4HAaddon)

set -euo pipefail

WORKDIR="/opt/ha-addons.workdir"
BRANCH="main"
REMOTE="origin"
CONFIG_FILE="$WORKDIR/nascloud4haaddon/config.yaml"

echo "=== HA Add-on Release ==="

# 1. Auto bump version in config.yaml
if grep -q '^version:' "$CONFIG_FILE"; then
    OLD_VER=$(grep '^version:' "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    BASE=$(echo "$OLD_VER" | cut -d. -f1,2)
    PATCH=$(echo "$OLD_VER" | cut -d. -f3)
    if [[ -z "$PATCH" ]]; then
        NEW_VER="${BASE}.1"
    else
        NEW_VER="${BASE}.$((PATCH+1))"
    fi
    sed -i "s/^version:.*/version: \"$NEW_VER\"/" "$CONFIG_FILE"
    echo "Bumped version: $OLD_VER -> $NEW_VER"
else
    echo "WARN: no version field in $CONFIG_FILE"
fi

# 2. Git commit + push
cd "$WORKDIR"
echo "--- git add ---"
git add .

if git diff --cached --quiet; then
    echo "WARN: no changes to commit."
else
    MSG="Release update $(date +'%Y-%m-%d %H:%M:%S')"
    echo "--- git commit: $MSG ---"
    git commit -m "$MSG"
fi

echo "--- git push $REMOTE $BRANCH ---"
git push "$REMOTE" "$BRANCH"

echo "Release finished successfully."
