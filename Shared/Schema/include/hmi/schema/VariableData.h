#pragma once

#include <QJsonObject>
#include <QString>

namespace hmi::schema {

// Task 39: 実行時変数（タグ）の定義。Project レベルに配列で持つ（widget 非依存の
// 横断サブシステム）。型は "bool" / "int" / "string" の 3 種。初期値は **文字列で保持**
// し（JSON / QVariantMap を跨いで型をブレさせない）、実行時に type に応じて解釈する。
// 例: { "name": "running", "type": "bool", "initial": "false" }
struct VariableData {
    QString name;
    QString type;     // "bool" / "int" / "string"
    QString initial;  // 初期値（文字列表現。type に応じて実行時に解釈）

    QJsonObject toJson() const;
    static VariableData fromJson(const QJsonObject &obj);

    // name が非空文字列で type が 3 種のいずれかなら有効。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
