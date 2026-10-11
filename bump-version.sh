#!/bin/zsh
# バージョンを上げる。3.0.1 から正式版で、0.0.1 ずつ（例: 3.0.1 → 3.0.2）。
# dist に置くビルドの前に毎回実行する。引数で指定すればその値にする（例: ./bump-version.sh 2.0.0）。
set -euo pipefail
cd "$(dirname "$0")"
cur=$(sed -n 's/.*CFBundleShortVersionString: "\(.*\)"/\1/p' project.yml | head -1)
if [[ $# -ge 1 ]]; then
  new=$1
else
  parts=(${(s:.:)cur})
  new="${parts[1]}.${parts[2]}.$(( parts[3] + 1 ))"
fi
sed -i '' "s/\"$cur\"/\"$new\"/" project.yml
[[ -f CacaoSoundCues/Resources/Info.plist ]] && sed -i '' "s|<string>$cur</string>|<string>$new</string>|" CacaoSoundCues/Resources/Info.plist
month="$(date +%Y) 年 $(( $(date +%m) )) 月"
sed -i '' -E "s/バージョン β?[0-9.]+ ／ [0-9]+ 年 [0-9]+ 月/バージョン $new ／ $month/" manual/CacaoSoundCues-マニュアル.md
month_en="$(LC_ALL=en_US.UTF-8 date +'%B %Y')"
sed -i '' -E "s/^Version β?[0-9.]+ \/ .*/Version $new \/ $month_en/" manual/CacaoSoundCues-Manual-en.md
sed -i '' "s/CacaoSoundCues-[0-9.]*\.dmg/CacaoSoundCues-$new.dmg/" manual/CacaoSoundCues-マニュアル.md manual/CacaoSoundCues-Manual-en.md
echo "$cur → $new"
