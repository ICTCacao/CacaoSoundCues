#!/bin/zsh
# マニュアル（Marp、日本語版と英語版）を PDF にして manual/ と dist/ に置く。要: brew install marp-cli、Google Chrome
set -euo pipefail
cd "$(dirname "$0")"
for src in "CacaoSoundCues-マニュアル.md" "CacaoSoundCues-Manual-en.md"; do
  pdf="${src%.md}.pdf"
  marp --pdf --allow-local-files "$src" -o "$pdf" < /dev/null
  cp "$pdf" "../dist/$pdf"
  echo "作成: manual/$pdf → dist/$pdf"
done
