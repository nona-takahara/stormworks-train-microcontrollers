#!/bin/bash
# 並べ替えの前後で全行が保存されているか検証する
# 使い方: ./verify_sort.sh <並べ替え前ファイル> <並べ替え後ファイル>

BEFORE="$1"
AFTER="$2"

if [[ -z "$BEFORE" || -z "$AFTER" ]]; then
  echo "Usage: $0 <before> <after>" >&2
  exit 1
fi

missing=0
while IFS= read -r line; do
  # 空行とコメント行はスキップ
  [[ -z "${line// }" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  if ! grep -qF "$line" "$AFTER"; then
    echo "MISSING: $line"
    missing=$((missing + 1))
  fi
done < "$BEFORE"

total=$(grep -c . "$BEFORE")
echo "---"
echo "Checked $total non-empty lines from $BEFORE"
if [[ $missing -eq 0 ]]; then
  echo "OK: all lines present in $AFTER"
else
  echo "WARNING: $missing line(s) not found in $AFTER"
  exit 1
fi
