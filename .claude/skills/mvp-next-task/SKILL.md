---
name: mvp-next-task
description: MVP の次の 1 タスクを実装する標準ワークフロー。設計書の「1 タスクずつ・ビルド成功を完了基準とする」を守る。「次のタスクを進めて」「Task N をやる」「MVP の次」のような指示で発火。
origin: hmi-platform
---

# MVP 次タスク実装ワークフロー

本プロジェクトは **Phase 単位で 1 タスクずつ、ビルド成功を完了基準** として進める（MVP / Phase 2 / Phase 3-A / Phase 3-B …）。本スキルはその標準手順。

## 適用タイミング（When to Use）

- ユーザーが「次のタスクを進めて」「Task N を実装」「MVP / Phase の次に進む」と指示した時
- 直前のタスクが完了済み・ビルドが緑のときに次の一歩を踏み出す時

## 手順（How It Works）

1. **進捗確認**
   - [CLAUDE.md](../../../CLAUDE.md)「現在のフェーズ」セクションと [README.md](../../../README.md)「フェーズ進捗」表を Read
   - 直近の git log を確認
   - 未着手の最も若い番号のタスクを次のタスクとして特定（フェーズを跨ぐ場合はフェーズ計画書 `Docs/phase*-plan.md` も併読）

2. **タスク宣言**
   - ユーザー宛に「Task N: <名前> に取り組みます。完了基準は <X>」と冒頭で明示

3. **ブランチ作成**
   ```sh
   git checkout main && git pull --ff-only
   git checkout -b task/<N>-<短い名>
   ```
   - 例：`task/2-canvas`、`task/3-widget-schema`

4. **実装範囲の限定**
   - 1 タスクのみ。「ついで」リファクタは禁止
   - 影響範囲を箇条書きで列挙してから着手

5. **実装**
   - 設計書ルール（[CLAUDE.md](../../../CLAUDE.md) の「開発ルール」セクション）を逐条守る
   - 特に：Shared/Schema を唯一の真実 / フォルダ変更禁止 / 既存コード削除禁止

6. **ビルド検証**
   ```sh
   cmake --build build
   ```
   - 失敗時は [cmake-build-resolver](../../agents/cmake-build-resolver.md) エージェントに委譲

7. **動作確認 + スクリーンショット**
   - UI 系タスクなら Editor / Simulator を起動して目視（または PID 確認程度の自動検証）
   - **GUI に変化があるタスクは `scripts/capture-app-window.sh` で必ずスクリーンショットを撮る**。**タスクが変化させる対象アプリ（Editor / Simulator）を判断し、起動バイナリとプロセス名を切り替えること**：
     ```sh
     # Editor を変えた場合
     ./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor &
     sleep 2
     scripts/capture-app-window.sh hmi_editor Docs/screenshots/task-<N>-<短い名>.png
     kill %1

     # Simulator を変えた場合
     ./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator &
     sleep 2
     scripts/capture-app-window.sh hmi_simulator Docs/screenshots/task-<N>-<短い名>.png
     kill %1
     ```
   - 両方の見た目が同時に変わるタスクは両方撮り、`-editor.png` / `-simulator.png` の suffix を付けてコミットする
   - 撮ったスクショは Read ツールで内容を確認してから採用する（黒画面・他ウィンドウが混入していないか）
   - 詳細運用は [screenshot-capture](../screenshot-capture/SKILL.md) スキル参照

8. **進捗反映**
   - README.md の進捗表の該当行を ⬜ → ✅ に更新

9. **継続的改善（kaizen）**
   - [kaizen-close](../kaizen-close/SKILL.md) スキルを実行し、新たな知見を CLAUDE.md / README / メモリに反映

10. **コミット + push + PR 作成**
    - [codex-pr](../codex-pr/SKILL.md) スキルに従い、`Task N: <短い説明>` コミット → push → `gh pr create`（ready-for-review）
    - PR URL を完了報告に含める
    - **マージは Codex レビュー後にユーザーが行う**（Claude は勝手にマージしない）

## やってはいけないこと（Must Never）

- 複数タスクを一度に進める
- 設計書外のフォルダを作る
- テストフレームワーク等を独断で導入する
- main に直接 push / コミットする（必ず `task/<N>-<短い名>` ブランチ + PR）
- PR を勝手にマージする（マージはユーザーの責任）

## 例（Example）

```
ユーザー: 次のタスクを進めて
あなた  : README の進捗を確認 → Task 2 (キャンバス表示) が未着手
         → 「Task 2: キャンバス表示 に取り組みます。完了基準は Editor 起動でキャンバスが描画されること」
         → git checkout -b task/2-canvas
         → Editor/qml/Main.qml にキャンバス Item を追加
         → cmake --build build → 成功
         → Editor 起動 → キャンバス描画を目視
         → README 進捗を ✅ に更新
         → kaizen-close で学びをドキュメントに反映
         → コミット → push → gh pr create
         → 完了報告に PR URL を含める（マージは Codex レビュー後にユーザー）
```
