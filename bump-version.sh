#!/bin/zsh
# バージョンを上げる。ベータ版の間は 0.1.0 ずつ（例: 1.1.0 → 1.2.0）。表示は「β1.2.0」。
# dist に置くビルドの前に毎回実行する。引数で指定すればその値にする（例: ./bump-version.sh 2.0.0）。
set -euo pipefail
cd "$(dirname "$0")"
cur=$(sed -n 's/.*CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml | head -1)
if [[ $# -ge 1 ]]; then
  new=$1
else
  parts=(${(s:.:)cur})
  new="${parts[1]}.$(( parts[2] + 1 )).0"
fi
sed -i '' "s/\"$cur\"/\"$new\"/" project.yml
[[ -f CacaoSoundCues/Resources/Info.plist ]] && sed -i '' "s|<string>$cur</string>|<string>$new</string>|" CacaoSoundCues/Resources/Info.plist
echo "β$cur → β$new"
