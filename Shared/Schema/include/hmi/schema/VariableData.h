#pragma once

#include "SourceData.h"

#include <QJsonObject>
#include <QString>
#include <QVariantMap>

#include <optional>

namespace hmi::schema {

// Task 39: 実行時変数（タグ）の定義。Project レベルに配列で持つ（widget 非依存の
// 横断サブシステム）。型は "bool" / "int" / "real" / "string"。初期値は **文字列で保持**
// し（JSON / QVariantMap を跨いで型をブレさせない）、実行時に type に応じて解釈する。
// 例: { "name": "running", "type": "bool", "initial": "false" }
//
// Phase 7 / MB-1: optional な `source`（SourceData）を持つ。未設定 = 内部変数のまま
// （後方互換）。設定時は PLC のレジスタ写像（どの接続の・どのレジスタか）を表す。
struct VariableData {
    QString name;
    QString type;     // "bool" / "int" / "real" / "string"
    QString initial;  // 初期値（文字列表現。type に応じて実行時に解釈）

    // Phase 7 / MB-1: 変数ソース写像（optional）。空のとき toJson で省略（後方互換）。
    std::optional<SourceData> source;

    QJsonObject toJson() const;
    static VariableData fromJson(const QJsonObject &obj);

    // QML との往復用に QVariantMap（QtCore）と相互変換する（ActionData と同方針）。
    QVariantMap toVariantMap() const;
    static VariableData fromVariantMap(const QVariantMap &map);

    // name が非空文字列で type が 4 種のいずれかなら有効。source は optional のため
    // 必須集合に入れない（後方互換）。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
