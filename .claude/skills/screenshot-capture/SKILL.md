---
name: screenshot-capture
description: GUI に変化がある PR（Editor / Simulator の見た目が変わる UI 変更・bugfix）の動作証跡スクリーンショットを撮る・PR に埋め込む・README 掲載スクショを同期する手順。macOS（capture-app-window.sh）/ Windows（capture-app-window.ps1）/ Linux・Claude Code on the web（capture-app-screenshot-linux.sh, offscreen + --screenshot）対応、QML Button の自動クリック可否の差も含む。
origin: hmi-platform
---

# 動作証跡スクリーンショット運用

GUI に変化がある PR（MVP Task 2 / 4 / 5 / 8 のような Editor / Simulator の見た目が変わるもの、UI 系の bugfix）には **スクリーンショットを必ず添付する**。Codex / 人間レビュアーの両方が、コードを脳内実行せず「実際にこう見える」を確認できるようにするため。

## 適用タイミング（When to Use）

- Editor / Simulator の見た目が変わる PR を作る時（動作証跡が必須）
- README 掲載の現状スクショ（`editor.png` / `simulator.png`）を更新する時
- 「操作後の状態」（選択枠・インスペクタ編集反映など）をキャプチャしたい時

## 撮影手順（macOS）

対象アプリ（Editor / Simulator）に応じて起動バイナリとプロセス名を切り替える：

```sh
# Editor の変更を撮る場合
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor &
sleep 2
scripts/capture-app-window.sh hmi_editor Docs/screenshots/task-<N>-<短い名>.png
kill %1

# Simulator の変更を撮る場合
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator &
sleep 2
scripts/capture-app-window.sh hmi_simulator Docs/screenshots/task-<N>-<短い名>.png
kill %1
```

両方の見た目が同時に変わるタスク（例：Task 8 で Editor の保存形式と Simulator の表示を同時に検証したい場合）は両方のスクショを撮り、`Docs/screenshots/task-<N>-<短い名>-editor.png` と `-simulator.png` のように suffix を付けて両方コミットする。

- `scripts/capture-app-window.sh` は Swift で `CGWindowListCopyWindowInfo` を呼び対象プロセスのウィンドウ ID を取得し、`screencapture -l<wid>` で当該ウィンドウのみを切り出す（Retina 倍率は自動考慮、アクセシビリティ権限不要、**画面収録権限のみ**が必要）。
- **初回のみ macOS の画面収録権限を Claude Code 親プロセス（Visual Studio Code / ターミナル）に付与する必要がある**。システム設定 > プライバシーとセキュリティ > 画面収録 で対象アプリを ON にし、再起動。
- **AppleScript で Qt QML の Button を自動クリックする手段は事実上ない**（Task 7 で確認）。`tell application "System Events" to click at {x, y}` の CGEvent も、Accessibility の `click button "name" of window 1` も、QML のクリックイベントとして受理されない（座標は正しくても無反応）。FileDialog を介する読込・保存系の動作証跡が必要な場合は、(a) 起動直後の初期状態だけスクショして「ボタンが追加されたこと」を見せる、(b) どうしても「操作後の状態」を撮りたいなら、テスト用に環境変数や CLI 引数で初期 JSON を自動ロードする小機能を当該タスクに含める、のいずれかを選ぶ。最初から無理に automate しようとせず手動補完で済ませる判断もあり。

## 撮影手順（Windows）

Task 25 で `scripts/windows/capture-app-window.ps1`（PowerShell 版）を新設。`PrintWindow(PW_RENDERFULLCONTENT=2)` でウィンドウ単位に切り出すため、他ウィンドウに**隠れていても**対象アプリだけを撮れる（macOS の `screencapture -l<wid>` 相当）。

```powershell
. .\scripts\windows\setup-env.ps1
Start-Process .\build-mingw\hmi_editor.exe   # 起動
Start-Sleep -Seconds 3
.\scripts\windows\capture-app-window.ps1 -ProcessName hmi_editor -Out Docs\screenshots\task-<N>-<短い名>.png
Stop-Process -Name hmi_editor -Force
```

- 出力 PNG は **ウィンドウ枠（タイトルバー込み）** で、右下に数 px の黒縁が残ることがある（`GetWindowRect` と実描画域の差。動作証跡としては問題なし）。
- **Windows では macOS と違い Qt QML の Button を自動クリックできる**。Win32 `mouse_event`（実マウスメッセージ）は QML の `MouseArea` / `clicked` に届くため、`SetWindowPos(hWnd, HWND_TOPMOST, ...)` ＋ `BringWindowToTop` で対象を**最前面に固定**してから対象座標へ `SetCursorPos`→`mouse_event(LDOWN/LUP)` でクリックすれば「操作後の状態」（選択枠が出た状態など）を撮れる。AppleScript の CGEvent が無反応なのと対照的（理由：AppleScript は合成イベント、Win32 は実 OS マウスメッセージ）。
  - 注意：**背景プロセスからの `SetForegroundWindow` は Windows に抑制される**ことがあり、ウィンドウが他に隠れたまま注入クリックすると別ウィンドウに当たる。必ず `HWND_TOPMOST` 固定で前面に出してからクリックする。座標は `GetWindowRect` の左上 ＋ クライアント原点（`ClientToScreen`）＋ QML 上の論理座標から算出する（起動直後で対象が最前面なら `SetForegroundWindow` だけでも通る。Task 26 はこれで `btn001` を実クリックできた）。**クリック座標の簡便な求め方**：先に `capture-app-window.ps1` で撮ったスクショ画像内のピクセル位置 ＝ ウィンドウ原点からのオフセット（`PrintWindow` は物理解像度でキャプチャするため画像 px = `GetWindowRect.Left/Top` からの px オフセットに一致）。
  - **テキスト入力も自動化できる**（Task 26 で確立）。`TextField` を上記方式でクリックしてフォーカスさせた後、`[System.Windows.Forms.SendKeys]::SendWait("^a")`（全選択）→ `SendWait("Run")` でフォーカス中の入力欄に文字を流し込める。これで「選択 → インスペクタで text 編集 → キャンバス即反映」のような**操作後の状態**を Windows 上で完全自動キャプチャできる（IME 経由が必要な日本語は不安定なので、動作証跡用の入力は ASCII にする）。macOS で AppleScript が QML を操作できないのと対照的。
  - **クリック前にウィンドウを `(0,0)` へ移動する**（Task 46 で確立）。ウィンドウが画面右寄りにあると `GetWindowRect.Left + オフセット` が**画面外**になり、`SetCursorPos` が画面端へクランプされて**別の場所をクリック**する（クリックが「効かない」ように見える）。`SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_SHOWWINDOW)` で移動 + 最前面化してからクリックすれば確実。
  - **同一プロセスの別ウィンドウ（ColorDialog / ポップアップ等）も操作・撮影できる**（Task 46 で確立）。`Process.MainWindowHandle` はメインウィンドウしか返さないが、`EnumWindows` + `GetWindowThreadProcessId` + `GetWindowText` で **pid とタイトル（例 "色を選択"）から hwnd を特定**でき、その hwnd に対して上記クリック注入や `PrintWindow` 単体キャプチャがそのまま使える（ダイアログ表示の有無も hwnd の有無で判定できる）。
  - **マウスホイール注入で ScrollView をスクロールした状態も撮れる**（Task 46 で確立）。カーソルを対象領域へ `SetCursorPos` した後 `mouse_event(MOUSEEVENTF_WHEEL=0x0800, 0, 0, -120, 0)` を必要ノッチ分送る（インスペクタ下方のセクションを見せる証跡で使用）。
  - **GUI 自動操作の PowerShell は一時 .ps1 ファイルに書いて実行する**。本ツールのシェルは呼び出しごとに新規で `Add-Type` の型が消える（同名再定義もエラー）ため、複数ステップの操作は 1 スクリプトにまとめる。日本語を含む .ps1 は **UTF-8 with BOM** で保存（PS5.1 の cp932 誤認はスクリプト全般の罠）。アプリ起動前に `setup-env.ps1` の dot-source を忘れない（PATH に Qt が無いと exe が黙って即終了し `MainWindowHandle=0` になる）。

## 撮影手順（Linux / Claude Code on the web — ヘッドレス）

ウィンドウシステムの無いリモート環境（Web セッション）/ CI では、外部キャプチャの代わりに
**アプリ内蔵の `--screenshot` フラグ**を使う。`-platform offscreen` で起動し、
`QQuickWindow::grabWindow()`（`Editor/src/ScreenshotGrabber.h` / `Simulator/src/ScreenshotGrabber.h`）で
オフスクリーン描画結果を PNG に書き出して自動終了する。**Xvfb も X11/Wayland も不要**。

```sh
# 前提: scripts/web/setup.sh で Qt 導入済み + cmake --build build 済み（Docs/claude-web-dev.md）
scripts/capture-app-screenshot-linux.sh -a editor    -o Docs/screenshots/task-<N>-<短い名>.png
scripts/capture-app-screenshot-linux.sh -a simulator -o Docs/screenshots/task-<N>-<短い名>.png -j Docs/samples/web-gui-demo.json
```

- `-a editor|simulator|runtime`（既定 editor）/ `-o <out.png>` / `-j <json>`（起動時 `--open`、任意）/ `-d <ms>`（撮影前待機、既定 700）。
- 撮影後は **必ず Read ツールで PNG を目視**（黒画面・崩れ・□ 文字化けが無いか）。日本語ラベルは `setup.sh` の `fonts-noto-cjk` で正しく出る。
- **macOS で AppleScript が QML を操作できない問題と同様、offscreen でも実マウス操作は注入できない**。`--screenshot` は「起動直後の静止画」前提。FileDialog 操作後の状態を撮りたいときは `-j` で初期 JSON を自動ロードして見せる（macOS の手法と同じ発想）。
- 実機 i.MX8MP の `scripts/yocto/vnc-capture.py`（VNC 経由）とは別経路。あちらは weston 実機専用、こちらは PC ビルドのヘッドレス用。
- 詳細は [Docs/claude-web-dev.md](../../../Docs/claude-web-dev.md)「GUI スクショ（ヘッドレス）」。

## ファイル配置と PR への埋め込み

- 出力先：`Docs/screenshots/task-<N>-<短い名>.png`（branch 名と揃える）。**PNG はこれまで通りコミットする**（リポジトリ内の恒久的な証跡。Codex / レビュアーは GitHub のファイルビューアや checkout で確認できる）。
- **PR 本文のインライン画像は GitHub 添付（user-attachments）URL を使う**。`raw.githubusercontent.com` は使わない：
  ```markdown
  ## Screenshot
  ![Task N: <短い説明>](https://github.com/user-attachments/assets/<uuid>)
  ```
- GUI 変化が無いタスク（純粋な Schema / docs / CMake のみ）はスクショ省略可。

### なぜ raw.githubusercontent.com はダメなのか（private リポジトリの 404 罠）

本リポジトリは **private**。`https://raw.githubusercontent.com/...` は github.com とドメインが別でログインセッションの cookie が効かず、private コンテンツへのアクセスには一時 `?token=` が必須。トークンの無い PR 本文の埋め込みは **404 not found** になり、スクショが映らない（実害：全 PR でスクショが表示されなかった。2026-06-08 にこの方式から user-attachments へ移行）。`github.com/<owner>/<repo>/raw/...` や `blob/...?raw=true` も、private ではマークダウンのインライン画像として安定表示されない。**ログイン中の閲覧者に確実にインライン表示されるのは user-attachments のみ**（GitHub が署名付き URL で配信するため）。

### user-attachments URL の取得（手動アップロードが必要）

`github.com/user-attachments/assets/<uuid>` URL は、**GitHub web の PR 説明 / コメント編集ボックスに画像をドラッグ&ドロップ（または貼り付け）すると自動生成される**。これは github.com のログインセッション + CSRF を要するため `gh` CLI / GitHub MCP / REST API では**自動化できない**（Claude 単独では取得不可）。そのため運用は次の分担にする：

1. **Claude**：スクショ撮影 → `Docs/screenshots/task-<N>-...png` をコミット → `gh pr create` で PR 作成。Screenshot セクションには **下記プレースホルダ**を置く（raw URL は書かない）。
2. **ユーザー（= browser セッションを持つ側）**：コミット済み PNG（`Docs/screenshots/...`）を PR 説明欄にドラッグ&ドロップしてインライン化する。GitHub が `github.com/user-attachments/assets/<uuid>` を生成して埋め込む。
3. ユーザーが添付 URL を Claude に渡した場合は、Claude が `gh pr edit <N> --body-file ...` でプレースホルダを当該 URL に置換する。

PR 作成時に置くプレースホルダ例：
```markdown
## Screenshot
<!-- ↓ Docs/screenshots/task-<N>-<短い名>.png をこの欄にドラッグ&ドロップしてインライン化してください（private repo のため user-attachments URL が必要） -->
撮影済み（コミット済み）: `Docs/screenshots/task-<N>-<短い名>.png`
```

## README 掲載スクショの同期

> **自動化メモ**：この同期がオンデマンドの skill 内に埋もれて効かず、Task 33〜41 で `editor.png` / `simulator.png` が古いまま残った（2026-06-09）。再発防止に **path-scoped rule [readme-screenshot-sync](../../rules/readme-screenshot-sync.md)（UI 本体 / README / screenshots を触る時に自動ロード）＋ Stop hook `scripts/hooks/check-readme-screenshots.sh`（UI〔QML〕差分があるのに固定スクショ未更新ならリマインド）** の二段構えで効かせている。本節はその撮影手順の正本。

README.md には **「常に最新」を表す固定ファイル名** のスクショを別途掲載している（[README.md](../../../README.md) の「スクリーンショット」節）。

| 固定ファイル | 対応アプリ |
|---|---|
| `Docs/screenshots/editor.png` | Editor |
| `Docs/screenshots/simulator.png` | Simulator（必要になったタイミングで追加） |

- **Editor / Simulator の見た目が変わる PR では、`task-<N>-<短い名>.png` を撮るのと同じコミットで `editor.png` / `simulator.png` も上書きで撮り直す**。`task-*.png` は SHA 固定で時系列の証跡を残す用途、`editor.png` / `simulator.png` は README から相対パス参照で「現状を見せる」用途。役割が違うので両方更新する。
- 上書きコマンド例（Editor の場合）：
  ```sh
  ./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor &
  sleep 2
  scripts/capture-app-window.sh hmi_editor Docs/screenshots/editor.png
  kill %1
  ```
- README から相対パス参照しているため、固定ファイル名はリネームしない（リネームすると README のリンクが切れる）。
- 純粋に GUI 変化が無い PR（Schema / docs / CMake / テストのみ）は README スクショも更新不要。
