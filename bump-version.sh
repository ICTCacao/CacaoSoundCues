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
month="$(date +%Y) 年 $(( $(date +%m) )) 月"
sed -i '' "s/バージョン β[0-9.]* ／ [0-9]* 年 [0-9]* 月/バージョン β$new ／ $month/" manual/CacaoSoundCues-マニュアル.md
month_en="$(LC_ALL=en_US.UTF-8 date +'%B %Y')"
sed -i '' "s/^Version β[0-9.]* \/ .*/Version β$new \/ $month_en/" manual/CacaoSoundCues-Manual-en.md
sed -i '' "s/CacaoSoundCues-[0-9.]*\.dmg/CacaoSoundCues-$new.dmg/" manual/CacaoSoundCues-マニュアル.md manual/CacaoSoundCues-Manual-en.md
echo "β$cur → β$new"
