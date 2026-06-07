---
name: schema-conventions
description: Shared/Schema の型・JSON I/O 実装規約（struct + namespace、toJson/fromJson/isValidJson のパターン）。Shared/Schema 配下を触る時のみロード
paths:
  - "Shared/Schema/**"
metadata:
  type: project
---

# Schema 実装規約（`Shared/Schema`）

Task 3 で定着したスタイル。新しいデータ型を追加するときも踏襲する。

- **型は struct + namespace `hmi::schema`** で表現する（Q_GADGET / Q_OBJECT は必要になるまで付けない。Task 3 時点では QML 直接 expose しないため）。
- **ヘッダ配置**：`Shared/Schema/include/hmi/schema/<TypeName>.h`。利用側は `#include "hmi/schema/<TypeName>.h"`。
- **ソース**：`Shared/Schema/src/<TypeName>.cpp`。新規追加時は `Shared/Schema/CMakeLists.txt` の `qt_add_library(hmi_schema STATIC ...)` 一覧にも追記する。
- **JSON I/O**：各型に `QJsonObject toJson() const;` と `static <T> fromJson(const QJsonObject &);` を持たせる（メンバ関数 + 静的ファクトリ）。`QJsonDocument` は最上位（Project）でのみ使用する想定。
- **省略可能フィールド**：`toJson()` で `isEmpty()` 判定して書き出しを省略する（Widget の `text` / `tag` が前例）。
- **`0` が正当値の optional 数値は `-1` をセンチネルにする**（Task 31 で定着。設計の正本は [phase4-button-slice-plan.md](../../Docs/phase4-button-slice-plan.md)「`0` が正当値の数値プロパティは `-1` センチネル」節）。`fontSize` のように「`0` = 未指定」が使える場合と違い、`borderWidth` / `radius` は `0` 自体が意味を持つ（ボーダー / 角丸なし）。このとき `toJson` は `>= 0` で書き出し（`0` も書く）、`fromJson` は欠落時 `-1` で読む。**API トラップ（Task 31 で実際に踏んだ）**：欠落時の既定を渡す書き方は型で全く別物なので混同しない ――
  - `QJsonValue::toInt(int defaultValue)`：**int** を取る。`obj.value("borderWidth").toInt(-1)`（`fromJson`、`obj` は `QJsonObject`）。
  - `QVariant::toInt(bool *ok)`：引数は **`bool*`（変換成否）であって既定値ではない**。`QVariant` に対して `.toInt(-1)` と書くと `int → bool*` でコンパイルエラー。`QVariantMap` から既定付きで読むときは **`m.value(key, -1).toInt()`**（`QVariantMap::value(key, default)` 側で既定を与える。C++ ブリッジ save の正しい書き方）。テストで `QVariantMap` 値を検証する時は既定不要なら素の `.toInt()`。
- **JSON 検証 API**：各型に `static bool isValidJson(const QJsonObject &);` も持たせる（Task 7 で定着）。`fromJson` はキー欠落時に既定値で埋める緩い設計なので、Editor / Simulator の読込側は **必ず `ProjectData::isValidJson` を通してから `fromJson` を呼ぶ**。検証は階層構造的に：`ProjectData::isValidJson` → `ScreenData::isValidJson` → `WidgetData::isValidJson` と再帰し、Shared/Schema 側に検証ロジックを集約する（利用側に検証コードを散らさない）。新しい必須フィールドを足す型変更時は `isValidJson` も同時に更新する。
