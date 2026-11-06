---
name: hero-demo
description: README ヒーロー画像（editor.png / simulator.png）を「現場の装置画面らしい産業用 HMI」に保つための標準ワークフロー。ショーケース demo（Docs/samples/atlas-dashboard-demo.json）の組み立て技法（Button を矩形 / LED / KPI タイルに使う・全 Widget 種別を 1 画面に同居させる）と、ヘッドレス撮影でヒーローを差し替える手順。新しい Widget 種別を足したら必ずこの demo に代表インスタンスを加えて撮り直す。
origin: hmi-platform
---

# ヒーローデモ（HMI ショーケース）運用

README の冒頭ヒーロー（`Docs/screenshots/editor.gif` / `simulator.png`）は、本プラットフォームで「実際にどんな HMI が作れるか」を一目で伝える顔。単機能のサンプルではなく、**産業用ライン監視ダッシュボード風のリッチな 1 画面**を撮って載せる。そのショーケースの正本が **`Docs/samples/atlas-dashboard-demo.json`**。

## 適用タイミング（When to Use）

- README ヒーローを本物らしい HMI 画面にしたい / 古びたので作り直したい時。
- **新しい Widget 種別を追加した直後**（Phase 横展開テンプレ完了時）。→ 後述「Widget が増えたらデモを育てる」を必ず実施。
- スタイル属性（色 / フォント / ボーダー / 配置 等）を拡張し、ショーケースで見せたくなった時。

## ヒーローの正本とゴール

| 項目 | 値 |
|---|---|
| ショーケース JSON | `Docs/samples/atlas-dashboard-demo.json` |
| キャンバス | 800 × 600（Simulator/Runtime の `canvasWidth/Height`。ウィンドウは 1024×768 で centerIn） |
| ヒーロー出力 | `Docs/screenshots/editor.gif`（Editor で組み上げる GIF。`scripts/web/build-hero-gif.py`）/ `Docs/screenshots/simulator.png`（Simulator に読込） |
| 使う型 | 現行の全 Widget 種別（**Button / Label / NumericField / Trend / Meter / SimpleButton**。種別が増えたら追従） |

ゴールは「警報バナー + 生産の数値 + 設備の状態 + 操作 + トレンド + メーター」が同居した、**現場の装置画面に見える**密度の高い画面。

**見た目の方針（2026-11-05 ユーザー指摘で変更）**：原色の KPI タイル・大きな角丸・丸いバッジのような Web ダッシュボード風は「AI が作ったデモ」に見えるので使わない。ISA-101（High Performance HMI）の考え方に寄せる。

- 地とパネルは灰色（地 `#d9dbde` / パネル `#eceef0` / 枠 `#a9aeb5`）、角丸は 2px 程度。
- 色は異常のときだけ使う（注意 `#d99a00` / 警報 `#c62828`）。正常の印は灰色（`#8a9099`）。
- ボタンも灰色（`#c9cdd2` + 濃い文字）。START を緑、STOP を赤に塗らない。
- 例外：SimpleButton の ON 表示の緑の印は Widget 側で決まっているので、そのまま使う。
- 文字は値を黒く大きく、項目名と単位を灰色で小さく。単位を必ず付ける。
- Trend / Meter は軸や数値の文字色が暗い背景用に固定されているので、地は濃いグレー（`#2f3338`）にする。Trend は `yMin`/`yMax` と `sampleMs` を付ける（値が一定でも Simulator で線が出る）。
- 組み立ては `scratchpad` などに置いた Python で JSON を生成すると、座標の調整と範囲チェックが楽。

## 組み立て技法

パネルや区切り線のような図形の Widget は無いが、**Button を「描画プリミティブ」として流用**すると盤面が作れる。すべて既存の Schema フィールド（`Shared/Schema/include/hmi/schema/WidgetData.h`）だけで表現する＝新モジュール依存ゼロ。

| 見せたい要素 | 作り方 |
|---|---|
| パネル / カード | 大きめ Button、`text:""`・淡色 `backgroundColor`・`borderWidth:1`・`radius:2` |
| 区切り線 | 高さ 2px の Button（薄いグレー、`radius:0`） |
| 状態の印 | 小さい正方形 Button（`width=height`、`radius:0`）。正常は灰色、注意は黄 `#d99a00`、警報は赤 `#c62828`。正常を緑で塗らない |
| 数値の一覧 | パネル（灰色の Button）の上に、項目名 **Label**（灰色・小）＋ 値 **Label**（黒・太字・`hAlign:"right"`）＋ 単位 **Label**（灰色・小）を 1 行ずつ並べる |
| バナー / ヘッダ | 横長 Button（濃いグレー `#454a51`・白太字・`hAlign:"left"`）。警報は白地に赤枠のバナーにする |
| ステータス行のテキスト | **Label**（透明背景でパネルの上に重ねる。`hAlign:"right"` で値を右寄せ） |
| 操作 | **Button** ＋ `actions`（`setVariable`/`toggleVariable`）。トグルは `checkable:true`＋`bindings`(checked↔変数) |
| 設定値入力 | **NumericField** ＋ `bindings`(value↔変数)。`variables` に対応する変数を定義 |

技法のコツ：
- **重ね順 = 配列順**（後の要素が前面）。タイル本体 Button → その上にキャプション/数値 Label の順で並べる。
- **テキストは Label、図形と対話要素は Button** に役割分担すると意味が通り、Label のショーケースにもなる（旧版は全部 Button だった）。
- 色は上の「見た目の方針」のパレットで統一する。
- 800×600 に収め、外周マージン ~20px。`python3 -c` で `x+width<=800 / y+height<=600` を一括チェックしてから撮る。

## Widget が増えたらデモを育てる（最重要・ユーザー要望 2026-06-17）

> **新しい Widget 種別を追加したら、このショーケース demo に「その種別の代表インスタンス」を 1 つ以上足し、ヒーローを撮り直す。** デモは機能の鏡。種別が増えたのにヒーローが古いままだと「何が作れるか」を正しく見せられない。

手順（Widget 横展開テンプレの仕上げに組み込む）：

1. 新種別（例：Trend / Gauge / Toggle）を `atlas-dashboard-demo.json` に**盤面の文脈に合う形で**追加する（例：Trend は下段の大きいパネルに折れ線、Gauge は円形メータとして空きスペースに）。レイアウトを詰め直して密度と余白のバランスを保つ。
2. 必要なら `variables` と `bindings` を足してライブ感を出す（既存 `output` / `targetRate` のように）。
3. ヒーローを撮り直す（次節）。
4. README のヒーロー直下キャプションに新種別を 1 語追記（「ボタン / ラベル / 数値入力 / …」）。
5. [kaizen-close](../kaizen-close/SKILL.md) で完了。

## ヒーローの撮影（ヘッドレス）

Qt ビルド済みが前提。撮影はアプリ内蔵 `--screenshot`（offscreen）を叩く [screenshot-capture](../screenshot-capture/SKILL.md) と同じ経路。**Editor / Simulator の両方**を同じ JSON で撮る：

```sh
# 前提: Qt 導入（scripts/web/setup.sh ※後述の網要件）＋ cmake --build build 済み
DEMO=Docs/samples/atlas-dashboard-demo.json
python3 scripts/web/build-hero-gif.py   # editor.gif（README が表示するのはこちら）
scripts/capture-app-screenshot-linux.sh -a simulator -o Docs/screenshots/simulator.png -j "$DEMO" -d 900
```

- `-d`（撮影前待機 ms）は Canvas 描画と binding 反映が落ち着くよう 900 前後にする。
- **撮影後は必ず Read ツールで両 PNG を目視**：黒画面・崩れ・文字化け □（日本語フォント未導入）・widget の見切れが無いか。demo のラベルは ASCII 中心なので豆腐は出にくいが、フォントは `setup.sh` の `fonts-noto-cjk` で担保する。
- macOS / Windows のウィンドウキャプチャ経路でも撮れる（[screenshot-capture](../screenshot-capture/SKILL.md)）。その場合はアプリを `--open "$DEMO"` で起動してから window キャプチャする。

## ヒーローを GIF にする（デモを組み上げる様子・ユーザー要望 2026-06-19）

README 冒頭のヒーローは静止 PNG（`editor.png`）の代わりに、**Editor でショーケースを段階的に組み上げていくアニメ GIF（`Docs/screenshots/editor.gif`）** にできる。「実際にこのツールで画面を作れる」が一目で伝わる。

- 生成スクリプト：**`scripts/web/build-hero-gif.py`**（Pillow 使用＝`pip install Pillow`）。`atlas-dashboard-demo.json` の `widgets` 配列を前方スライスして「ここまで置いた」中間 JSON を複数作り、各段を `capture-app-screenshot-linux.sh -a editor` で offscreen 撮影 → 1 本の GIF に合成する。
- フレーム区切りは `MILESTONES`（累積 widget 数）で制御。demo の widgets 配列が組み上げ順（地とヘッダ → 警報バナー → 生産 → 設備の状態 → 操作 → トレンド → 温度メーター → 長押し起動）に並んでいることを利用する。**新 Widget を demo 末尾に足したら最終マイルストーン（= 総数）を更新**する。
- 中間フレーム（`Docs/screenshots/hero-frames/`）は再生成可能なので **`.gitignore` 済み**。コミットするのは `editor.gif` のみ。
- 撮り直し：Qt ビルド済み環境で `python3 scripts/web/build-hero-gif.py` を実行 → `editor.gif` を上書き → README キャプションを見直す。

## README 同期

ヒーローを撮り直したら、同じコミットで README のキャプションも見直す（[readme-screenshot-sync](../../rules/readme-screenshot-sync.md) と Stop hook の二段構えで強制される）。ファイル名（`editor.png` / `simulator.png`）はリネームしない（README が相対参照しているため）。

## 網ポリシー要件（Claude Code on the web で撮る場合）

ヒーロー差し替えには Qt ビルドが要る。**Web セッションで Qt を導入するには環境のネットワークが `Full`（または `Custom` + `*.qt.io`）でなければならない**。既定の `Trusted` や qt.io を許可しない allowlist では `download.qt.io` が `host_not_allowed`（HTTP 403）になり `aqtinstall` が「Failed to locate XML data」で失敗し、ビルド・撮影ができない（2026-06-17 実証）。その場合は (a) 環境ポリシーを Full にして再実行、(b) ローカル（macOS / Windows）でビルドして撮影、のいずれか。詳細は [Docs/claude-web-dev.md](../../../Docs/claude-web-dev.md) と CLAUDE.md「Claude Code on the web」。

> 注意：撮影せずに JSON / レイアウトだけ変えてヒーロー PNG を据え置くのは可。だが **PNG を「撮ったことにして」差し替えない**（実際に撮って目視した結果だけをコミットする）。
