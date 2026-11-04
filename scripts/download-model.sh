#!/bin/bash
# Downloads the open cleanup model once, for languages Apple's on-device model
# doesn't cover (e.g. Polish). Utter itself never downloads anything: it only
# loads the model from the folder below.
#
#   scripts/download-model.sh                     # default model
#   scripts/download-model.sh <hf-repo-id>        # another MLX model
#
# Files go to ~/Library/Application Support/Utter/Models/<model-name>/.
# Delete that folder to remove the model.
set -euo pipefail

REPO="${1:-mlx-community/Qwen3-4B-Instruct-2507-4bit}"
NAME="${REPO##*/}"
DEST="$HOME/Library/Application Support/Utter/Models/$NAME"
BASE="https://huggingface.co/$REPO/resolve/main"

mkdir -p "$DEST"
echo "Downloading $REPO to $DEST"

FILES="$(curl -fsSL "https://huggingface.co/api/models/$REPO" | python3 -c '
import json, sys
for sibling in json.load(sys.stdin)["siblings"]:
    name = sibling["rfilename"]
    if name not in (".gitattributes", "README.md") and "/" not in name:
        print(name)
')"

for file in $FILES; do
  echo "  $file"
  # -C - resumes a partial download.
  curl -fL --retry 3 -C - --progress-bar -o "$DEST/$file" "$BASE/$file"
done

echo "Done. Choose the model in Utter › Settings › Cleanup."
