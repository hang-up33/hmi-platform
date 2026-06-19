---
name: readme-screenshot-sync
description: Editor / Simulator の見た目が変わる変更では、README ヒーロースクショ（Docs/screenshots/editor.png / simulator.png）を同じコミットで撮り直して同期する。UI 本体（QML）/ README / screenshots を触る時のみロード
paths:
  - "**/*.qml"
  - "Editor/**"
  - "Simulator/**"
  - "Runtime/**"
  - "Shared/Widgets/**"
  - "README.md"
  - "Docs/screenshots/**"
metadata:
  type: project
---

# README スクショ同期（見た目が変わったら撮り直す）

Editor / Simulator の**見た目が変わる**変更（QML レイアウト・インスペクタ UI・ツールバー・スタイル描画・UI 系 bugfix）では、その作業と**同じコミット**で README 掲載のヒーロースクショを撮り直して同期する。

| 固定ファイル | 対応アプリ | 参照元 |
|---|---|---|
| `Docs/screenshots/editor.gif` | Editor ヒーロー（組み上げアニメ。`python3 scripts/web/build-hero-gif.py` で再生成。[hero-demo](../skills/hero-demo/SKILL.md)）。**README が表示する正本＝Stop hook はこの gif の更新を必須判定** | [README.md](../../README.md) 冒頭ヒーロー |
| `Docs/screenshots/simulator.png` | Simulator | README「スクリーンショット」節 |

> 旧 `editor.png`（静止スクショ）は README 非参照になった。撮り直しても README には反映されないため、Editor ヒーロー同期は `editor.gif` のみを正とする。

- `task-<N>-<短い名>.png`（SHA 固定の時系列証跡）を撮るのと**両方**やる。`editor.png` / `simulator.png` は README から相対パス参照される「現状を見せる」用途なので、見た目が変わったら上書きで撮り直す。
- **キャプションの文言も更新する**：README のスクショ説明が「Task 25〜31」「色・ボーダー」止まりのように古いと、画像だけ新しくても齟齬が残る。追加した UI（フォント詳細 / 配置 / opacity / グリッドスナップ / 複数選択 / コピペ / undo-redo / 変数・アクションのインスペクタ等）を反映する。
- 撮影手順は [screenshot-capture](../skills/screenshot-capture/SKILL.md) スキル（macOS / Windows / Linux・Web ヘッドレス `--screenshot`）。このリモート環境でも `scripts/capture-app-screenshot-linux.sh` で撮れる。
- 純粋に見た目が変わらない変更（Schema / docs / CMake / テスト / 内部ロジックのみ）はスクショ更新不要。

**Why（この rule を作った理由）:** README スクショ同期の指示は元々 screenshot-capture スキルの末尾節にだけ書かれており、**オンデマンドの skill 内に埋もれて自動では効かなかった**。実際 Phase 4 拡張（Task 33〜41）で各タスクの `task-*.png` は撮られたのに `editor.png` / `simulator.png` だけ古いまま残り、README が Task 31 時点の画像のままになった（2026-06-09 にユーザー指摘）。そこで①この path-scoped rule（UI 本体・README・screenshots を触る時に自動ロード）と②Stop hook（`scripts/hooks/check-readme-screenshots.sh`：UI〔QML〕差分があるのに `editor.png` / `simulator.png` 未更新ならリマインド）の**二段構え**で効かせることにした。

**How to apply:** UI 本体（`*/qml/*.qml`）を編集したらこの rule がロードされる。タスク完了報告・PR 作成（[codex-pr](../skills/codex-pr/SKILL.md)）の前に「見た目は変わったか？変わったなら editor.png / simulator.png とキャプションを同期したか？」を確認する。Stop 時にも hook が同じ観点で警告する（見た目不変・撮影不能なら一言述べて終了可、ブロックはしない）。

関連：[[feedback-continuous-improvement]] / [screenshot-capture](../skills/screenshot-capture/SKILL.md) スキル「README 掲載スクショの同期」節
