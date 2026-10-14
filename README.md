# CacaoSoundCues

舞台専用のポン出しソフト（macOS 14 以降・Swift）。Soundplant の「キーを押せば即鳴る」に、
幕間 BGM などの **シーケンシャル再生リスト** を加えたもの。MacBook だけで完結する。

**Windows 版**（Windows 10 / 11）もある（`CacaoSoundCuesWin/`）。キューシート（`.ccsc`）は Mac 版と共通で、
Mac で作ったものを Windows でそのまま開ける（その逆も）。操作は同じで、Mac の Return は Windows では Enter。

このリポジトリは **Simple 版**（Mac・Windows）。**Pro 版**（Mac だけ・無料・MIT）は [CacaoSoundCuesPro](https://github.com/ICTCacao/CacaoSoundCuesPro)。台本連動・台本進行・出力の系統・
バックアップ機との同時運転・MIDI コントロールを足したもの。このリポジトリのソースの中の `#if PRO` が、Pro の機能の差し込み口。

## できること（v0.1）

- 音ファイル（wav / aiff / mp3 / m4a など macOS で再生できるもの）をキーにドラッグして割り当て
- 設定で F キー（F1〜F12）の行とテンキーも表示して割り当てられる（テンキーの数字は上の段の数字と別のキー。
  テンキーの enter は Return と同じ「次の曲へ」）。F キーを単独で使うには macOS の「標準のファンクションキーとして使用」を ON に
- 割り当て済みのキーを別のキーへドラッグして移す（移り先も割り当て済みなら入れ替え）。option（Windows は Ctrl）を押しながらドラッグすると、
  空いているキーへコピー（同じ音を、音量などを変えて別のキーでも使う）
- キーを押すと即再生。鳴っている間にもう一度押すとフェードアウト（0 秒ならカットアウト）
  - 再押しの動作はキーごとに「止める / 頭から / 重ねる / 何もしない」
- 波形の上で、再生範囲（開始・終了）、フェードの長さ、フェードの形（ベジエ曲線）をドラッグで指定、リピート（止めるまで／回数指定）、音量
- フェードイン・フェードアウトは秒で指定（0 = カット）、カーブは 直線 / 等パワー / S字 / カスタム（ベジエ）
- 終了位置に向けた自動フェードアウト
- リスト（幕間 BGM など）: 曲を順番に再生。最後まで行ったら先頭へ、開始／停止を任意のキーに割り当て
  - 鳴らすリストは常に1つ。別のリストを開始すると、鳴っていたリストは停止フェードで止まる
  - **Return** で再生中のリストの次の曲へ（今の曲はその曲のフェードアウトで止まる）。
    どのリストも鳴っていなければ、選んでいるリストを開始
  - 曲を **ダブルクリック**、または **↑↓** で選ぶと、その曲が「次に鳴らす曲」になる（鳴らさない）。Return で鳴る
  - **スペース** でリストの今の曲を途中で終える（その曲のフェードアウトで）。次の曲はタイミング設定どおりに続く
  - スペース・Return・Esc は操作用のキーなので、音やリストは割り当てられない
  - 曲ごとに鳴らし始めるタイミングを設定: 前の曲が終わったとき（間の秒数）／前の曲に重ねる（秒数）／
    Return を押したとき（自動再生しない。リストは待機し、Return で鳴らす。Return から n 秒待って鳴らすこともできる）
- 「前の曲に重ねる」は自動でクロスフェード（前の曲は重ねる長さでフェードアウト、次の曲はフェードイン。自分で設定したフェードが優先）
- 設定（⌘,）で、音を追加したときの最初の設定（フェード・再押しの動作・リストのタイミング・カーブ）を変えられる
- **本番モード**（⇧⌘L）: 編集・ファイル操作・試聴を止め、キー操作と再生だけにする。右側は本番用の表示
  （今の曲と残り時間・次の曲・鳴っているキー）。終了には確認が出る
- **言語の切り替え**（設定 ⌘,）: 日本語／English。ほかの言語は、翻訳用のひな形（英語の JSON）を書き出して
  訳し、`~/Library/Application Support/CacaoSoundCues/Languages/` に置くと選べる（訳の無い言葉は英語）
- Esc で全部の音をすぐ止める（フェードなし。文字入力中でも効く）
- 保存は `.ccsc` パッケージ（`show.json` と `Audio/` に音ファイルのコピー）。フォルダごと持ち運べる
- 前回のキューシートを起動時に自動で開く。再生中・未保存の終了は確認する。スリープ・App Nap を抑止

## 遅延を出さないための作り

- 音はキューシートを開いた時点で全部メモリに展開（出力のサンプルレートに変換済み）。押した瞬間に読み込みは起きない
- `AVAudioEngine` に `AVAudioSourceNode` を 1 つだけつなぎ、その中の自前ミキサー（`CueMixer`、最大 32 音）で
  フェード・再生範囲・リピートをサンプル単位で処理する。音声スレッドではメモリ確保もロック待ちもしない
- 出力デバイスのバッファを 128 フレーム（48kHz で約 2.7ms）に設定
- リストの曲のつなぎ目（間・重ね）も音声スレッド側でサンプル単位で合わせる
- キー入力はアプリが前面のときだけ受ける（アクセシビリティの許可は不要）

## 構成

```
project.yml                     XcodeGen（xcodegen generate で .xcodeproj を作る）
Packages/CacaoSoundCuesCore     データ・ミキサー・デコーダ・保存（UI なし、swift test で検証）
CacaoSoundCues/                 アプリ（SwiftUI）
```

## Windows 版

```
CacaoSoundCuesWin/engine   音声エンジン（Rust。CueMixer の移植。cargo test で Mac 版と同じ動きを確かめる）
CacaoSoundCuesWin/app      アプリ（Tauri 2。画面は TypeScript + Preact、音と保存は Rust）
```

Mac でクロスビルドする（cargo-xwin と llvm が必要）:

```sh
cd CacaoSoundCuesWin/app
PATH="/opt/homebrew/opt/llvm/bin:$PATH" npm run tauri build -- --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis
```

- 音は WASAPI（cpal）で、できるだけ 128 フレームのバッファで鳴らす
- Mac で作った zip を Windows で展開して日本語のファイル名が化けても、ファイル名の先頭の ID で音を見つける
- 本番中は Windows のスリープを抑止する

## 配布用 dmg

```sh
./make-dmg.sh   # dist/CacaoSoundCues.app から dist/CacaoSoundCues-<ver>.dmg を作る
```

dmg を開くと矢印付きの背景に「アプリ → Applications」が並ぶ（CacaoTrans と同じ作り。背景は
`dmg/make-background.swift` で生成）。アドホック署名なので、別の Mac では初回だけ右クリック →「開く」。

## マニュアル

`manual/CacaoSoundCues-マニュアル.md`（日本語・Mac 版）、`manual/CacaoSoundCues-マニュアル-Windows.md`（日本語・Windows 版。Mac 版を元に、インストール・キー表記・メニュー・設定を Windows に合わせたもの）、`manual/CacaoSoundCues-Manual-en.md`（英語）。Marp、白背景のスライド。
`manual/build.sh` で全部の PDF を作り `dist/` にも置く
（要 `brew install marp-cli` と Google Chrome）。画面写真は `manual/img/`。
版を上げると（`./bump-version.sh`）表紙のバージョンと日付、dmg のファイル名も書き換わる（日本語版・英語版とも）。
英語版の画面写真（`img/en-*.png`）は、英語の名前のサンプルを `-language en` で撮る。

画面写真は開発版（Debug）を起動引数で撮る（本物の公演データを写さないよう、作った音のサンプルを使う）:
`-debugOpen <.ccsc のパス> -debugSelectKey <キーコード> -debugSelectStep <番号> -debugSettings YES -debugLineMode volume|pan`
（このときは最近使ったキューシートやアプリの言語の記録を変えない）

## アイコン

`icon/draw-icons.swift` でアプリアイコン（カカオ豆の割れ目が波形）とキューシートの書類アイコンを描く。
描き直したら `icon/AppIcon1024.png` から `AppIcon.appiconset` を、`icon/DocIcon1024.png` から
`Resources/CueSheet.icns` を作り直す。

## ビルド

```sh
xcodegen generate
xcodebuild -project CacaoSoundCues.xcodeproj -scheme CacaoSoundCues -configuration Release -derivedDataPath build build
rm -rf dist/CacaoSoundCues.app && ditto build/Build/Products/Release/CacaoSoundCues.app dist/CacaoSoundCues.app
(cd Packages/CacaoSoundCuesCore && swift test)
```

起動するアプリは `dist/CacaoSoundCues.app`。dist に置くビルドの前に `./bump-version.sh` でバージョンを上げる。3.0.1 から正式版で、0.0.1 ずつ上げる（3.0.1 → 3.0.2）。

## ライセンス

- CacaoSoundCues は **オープンソース**です。コードは **MIT License**（[LICENSE](LICENSE)）。
  学校・劇団などで、自由に使い、改変し、配ってかまいません（著作権表示とライセンス文は残してください）。
- アプリ本体（Contents/Resources）にも LICENSE を同梱している。
- 外部のライブラリは使っていない（macOS の標準フレームワークだけ）。
- 本ソフトウェアは「現状のまま」提供され、本番での動作や結果について保証はありません。
  本番の前に、使う Mac とスピーカーで必ず確かめてください。
