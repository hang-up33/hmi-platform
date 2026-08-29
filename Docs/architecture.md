# アーキテクチャ概要 (Architecture)

このドキュメントは、Atlas（hmi-platform）の**アーキテクチャとモジュール構成の正本**。「どう作られているか」を知りたくなったら、まずここを見ればOK。

---

## 1. 全体構造

ルートの `CMakeLists.txt` が 5 つのサブプロジェクトをまとめている。

| モジュール | ターゲット名 | 種類 | QML URI | 役割 |
|---|---|---|---|---|
| **Shared/Schema** | `hmi_schema` | STATIC lib | — | プロジェクト JSON の**唯一の真実**。Widget/Screen/Project の C++ 型と JSON I/O を定義 |
| **Shared/Widgets** | `hmi_widgets` | QML module | `HmiWidgets` | Editor / Simulator / Runtime で共有する Widget 部品 |
| **Editor** | `hmi_editor` | アプリ | `HmiEditor` | 作画ツールアプリ。`loadFromModule("HmiEditor", "Main")` で起動 |
| **Simulator** | `hmi_simulator` | アプリ | `HmiSimulator` | PC 上の試験環境アプリ。Editor と同じ JSON を描画 |
| **Runtime** | `hmi_runtime` | アプリ | `HmiSimulator` (再利用) | i.MX8MP / Yocto 実機向けランタイム。**Simulator/ のソースを共有**し `hmi_runtime` バイナリを生成 |

---

## 2. コア設計原則

### JSON スキーマの一元管理 (`Shared/Schema`)
- Widget / Screen / Project にあたるデータ型と、JSON の読み書き処理（`toJson`/`fromJson`/`isValidJson`）は、すべて `Shared/Schema` にだけ置く。
- 実装の細かい規約は [.claude/rules/schema-conventions.md](../.claude/rules/schema-conventions.md) を見てほしい。

### QML モジュールとコンポーネント設計 (`Shared/Widgets`)
- Widget コンポーネントには必ず `Hmi` という接頭辞を付ける（例: `HmiButton.qml`, `HmiLabel.qml`, `HmiMeter.qml`）。QtQuick 標準の型と名前がかぶらないようにするため。
- 共有 QML モジュールは `STATIC` ライブラリとしてビルドして、アプリ本体に直接リンクする形にしている。
- QML モジュールの細かい規約は [.claude/rules/qml-module-conventions.md](../.claude/rules/qml-module-conventions.md) を見てほしい。

### WidgetModel の設計方針
- JSON の入出力には `QJsonDocument` を使う。
- Editor / Simulator の Widget リストは、いまのところ **QML の `var` 配列** で持っている（`widgetModel = widgetModel.concat([...])` のように配列を丸ごと差し替えて Repeater を作り直す方式）。
- `QAbstractListModel` への置き換えは今は保留にしている（理由は [.claude/rules/project-widgetmodel-refactor-deferred.md](../.claude/rules/project-widgetmodel-refactor-deferred.md) 参照）。

---

## 3. プラットフォームとビルド展開

- **PC ビルド (macOS / Windows)**: Editor / Simulator / Runtime はそれぞれ普通にビルド・実行できる。
- **実機ビルド (i.MX8MP / Yocto)**: Runtime は `Simulator` の QML/C++ ソースをそのまま使い回し、Yocto SDK (aarch64) でクロスビルドして i.MX8MP (scarthgap / weston / Qt6) 上で動かす。
- 詳しい手順は [Docs/archive/phase3b-runtime-plan.md](archive/phase3b-runtime-plan.md) にまとめている。
