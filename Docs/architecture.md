# アーキテクチャ概要 (Architecture)

本ドキュメントは、Atlas（hmi-platform）プロジェクトの**アーキテクチャおよびモジュール設計に関する正本**です。

---

## 1. 全体構造

ルート `CMakeLists.txt` から 5 つのサブプロジェクトを統合しています。

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
- Widget / Screen / Project に該当するすべてのデータ型および JSON シリアライズ/デシリアライズ処理（`toJson`/`fromJson`/`isValidJson`）は、`Shared/Schema` にのみ定義・実装します。
- 詳細な実装規約は [.claude/rules/schema-conventions.md](../.claude/rules/schema-conventions.md) を参照してください。

### QML モジュールとコンポーネント設計 (`Shared/Widgets`)
- Widget コンポーネントは QtQuick 標準型との名称衝突を避けるため、必ず `Hmi` プレフィックスを付与します（例: `HmiButton.qml`, `HmiLabel.qml`, `HmiMeter.qml`）。
- 共有 QML モジュールは `STATIC` ライブラリとしてビルドし、アプリ本体に直リンクします。
- 詳細な QML モジュール規約は [.claude/rules/qml-module-conventions.md](../.claude/rules/qml-module-conventions.md) を参照してください。

### WidgetModel の設計方針
- JSON 入出力は `QJsonDocument` を使用します。
- Editor / Simulator における Widget リストの現状実装は **QML の `var` 配列ベース** です（`widgetModel = widgetModel.concat([...])` で配列丸ごと差し替えて Repeater をリトリガする方式）。
- `QAbstractListModel` 化は現時点では deferred（保留）としています（[.claude/rules/project-widgetmodel-refactor-deferred.md](../.claude/rules/project-widgetmodel-refactor-deferred.md) 参照）。

---

## 3. プラットフォームとビルド展開

- **PC ビルド (macOS / Windows)**: Editor / Simulator / Runtime をそれぞれビルド・実行可能。
- **実機ビルド (i.MX8MP / Yocto)**: Runtime モジュールは `Simulator` の QML/C++ ソースを共有し、Yocto SDK (aarch64) でクロスビルドして i.MX8MP (scarthgap / weston / Qt6) 上で実行します。
- 詳細は [Docs/archive/phase3b-runtime-plan.md](archive/phase3b-runtime-plan.md) を参照してください。
