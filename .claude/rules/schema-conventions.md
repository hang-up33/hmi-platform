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
- **optional フィールドの省略書き出し・子型配列の相互変換・optional 配列検証は private ヘッダ [`src/SchemaJsonIo_p.h`](../../Shared/Schema/src/SchemaJsonIo_p.h)（`hmi::schema::detail`）に集約**（リファクタリングで定着）。`putString`（空省略）/ `putSentinelInt`（`>= 0`）/ `putPositiveInt`（`> 0`）/ `putSentinelReal`（`>= 0.0`）/ `putFlag(obj,key,v,default)`（既定値と異なる時だけ書く）/ `putPresentReal`（presence フラグ）/ `putJsonArray`・`jsonArrayToList`・`listToVariantList`・`variantListToList`（子型配列）/ `isValidOptionalArray`（optional 配列検証）。**新フィールドを足す時はこのヘルパーを使い、`>= 0` と `> 0` の取り違えや `.toArray()` ループの手書きコピーを避ける**。公開 API ではないので include/ でなく src/ に置く（hmi_schema は QML 非依存を維持）。
- **省略可能フィールド**：`toJson()` で `isEmpty()` 判定して書き出しを省略する（Widget の `text` / `tag` が前例）。ヘルパー（上記）を使えば 1 行で書ける。
- **`0` が正当値の optional 数値は `-1` をセンチネルにする**（Task 31 で定着。設計の正本は [phase4-button-slice-plan.md](../../Docs/archive/phase4-button-slice-plan.md)「`0` が正当値の数値プロパティは `-1` センチネル」節）。`fontSize` のように「`0` = 未指定」が使える場合と違い、`borderWidth` / `radius` は `0` 自体が意味を持つ（ボーダー / 角丸なし）。このとき `toJson` は `>= 0` で書き出し（`0` も書く）、`fromJson` は欠落時 `-1` で読む。**API トラップ（Task 31 で実際に踏んだ）**：欠落時の既定を渡す書き方は型で全く別物なので混同しない ――
  - `QJsonValue::toInt(int defaultValue)`：**int** を取る。`obj.value("borderWidth").toInt(-1)`（`fromJson`、`obj` は `QJsonObject`）。
  - `QVariant::toInt(bool *ok)`：引数は **`bool*`（変換成否）であって既定値ではない**。`QVariant` に対して `.toInt(-1)` と書くと `int → bool*` でコンパイルエラー。`QVariantMap` から既定付きで読むときは **`m.value(key, -1).toInt()`**（`QVariantMap::value(key, default)` 側で既定を与える。C++ ブリッジ save の正しい書き方）。テストで `QVariantMap` 値を検証する時は既定不要なら素の `.toInt()`。
- **JSON 検証 API**：各型に `static bool isValidJson(const QJsonObject &);` も持たせる（Task 7 で定着）。`fromJson` はキー欠落時に既定値で埋める緩い設計なので、読込側は **必ず検証を通してから `fromJson` を呼ぶ**。検証は階層構造的に：`ProjectData::isValidJson` → `ScreenData::isValidJson` → `WidgetData::isValidJson` と再帰し、Shared/Schema 側に検証ロジックを集約する（利用側に検証コードを散らさない）。新しい必須フィールドを足す型変更時は `isValidJson` も同時に更新する。**読込側（ProjectIo / ProjectLoader）は `ProjectData::parseValidated(const QByteArray&)→std::optional<ProjectData>` を呼ぶ**（リファクタリングで定着）：これがバイト列の `QJsonDocument::fromJson` → `isObject` → `isValidJson` → `fromJson` を 1 箇所で行い、「検証してから fromJson」の取りこぼしを構造的に防ぐ（無効なら `std::nullopt`）。ファイル / `QUrl` の OS I/O は利用側に残し、Schema は QFile を持たずバイト列のみ受ける。回帰は `tst_project_data.cpp` の `parseValidatedAcceptsValidJson` / `parseValidatedRejectsMalformedJson` / `parseValidatedRejectsStructurallyInvalidJson` で固定する。
- **配列 / ネストした型の JSON I/O**（Task 39 で定着）。子型（`ActionData` / `BindingData` / `VariableData`）を `QList<T>` で持つフィールドは、`toJson` で **空のとき省略**（`if (!list.isEmpty())` で `QJsonArray` を組む。後方互換）、`fromJson` で `obj.value(key).toArray()` を回して `T::fromJson(v.toObject())` を append（欠落時は空配列）。これらの **optional 子型は `isValidJson` の必須集合に入れない**（旧 JSON が持たなくても有効＝後方互換）。子型自身も `toJson`/`fromJson`/`isValidJson` の三点セットを持つ（スカラーと同じ規約）。Project レベル要素（変数定義）は `ProjectIo::save` に optional 引数を足して受ける（既定空）。
- **QML との QVariantMap 往復は Schema 型自身の `toVariantMap()` / `fromVariantMap()` に集約する**（リファクタリングで定着。旧方針＝各 C++ ブリッジの匿名 namespace に `<T>FromVariant`/`<T>ToVariant` を重複保持、は廃止）。各型（`WidgetData` / `ActionData` / `BindingData` / `VariableData`）は `toJson`/`fromJson` と並べて `QVariantMap toVariantMap() const` / `static <T> fromVariantMap(const QVariantMap&)` を持つ。`WidgetData::toVariantMap`/`fromVariantMap` は自分の actions / bindings 配列の子型変換まで内部で面倒を見る（QVariantList of QVariantMap）。**`QVariantMap`/`QVariantList`/`QVariant` は QtCore（QtQml 非依存）なので `hmi_schema` は引き続き QML を一切 import しない**。`fromVariantMap` のキー欠落時の既定は `fromJson` と同一規則：`0` が正当値の数値（borderWidth / radius / opacity）は `map.value(key, -1).toInt()` / `map.value(key, -1.0).toDouble()`、`enabled` は `map.value(key, true).toBool()`（[[qml-module-conventions]] の `QVariant::toInt` トラップと同じ）。**新しい Widget 属性を増やす時は `toJson`/`fromJson` と `toVariantMap`/`fromVariantMap` の 4 メソッド（すべて Schema の同じ .cpp 内）を揃えるだけでよい**（ProjectIo / ProjectLoader は `WidgetData::fromVariantMap(v.toMap())` / `w.toVariantMap()` を呼ぶだけなので変更不要。従来「縦スライスで一番取りこぼしやすい」とされた C++ ブリッジ 3 箇所の手書きコピーは解消済み）。round-trip は `tst_widget_data.cpp` の `variantMapRoundTripFullFields` / `fromVariantMapFillsSentinelDefaults` で回帰固定する。
