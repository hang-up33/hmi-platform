#include "hmi/schema/SourceData.h"

#include <QJsonValue>

namespace hmi::schema {

QJsonObject SourceData::toJson() const
{
    QJsonObject obj;
    obj["connection"] = connection;
    obj["reg"] = reg;
    // address は 0 が正当値（先頭レジスタ）なので常に書き出す。
    obj["address"] = address;
    obj["poll"] = poll;
    // Phase 9 / OP-1: nodeId（OPC-UA）は optional。空のときは省略（Modbus 既存 JSON 無改変）。
    if (!nodeId.isEmpty()) {
        obj["nodeId"] = nodeId;
    }
    return obj;
}

SourceData SourceData::fromJson(const QJsonObject &obj)
{
    SourceData s;
    s.connection = obj.value("connection").toString();
    s.reg = obj.value("reg").toString();
    // 欠落時の既定：address 0（先頭レジスタ）、poll 1000ms。
    s.address = obj.value("address").toInt(0);
    s.poll = obj.value("poll").toInt(1000);
    // Phase 9 / OP-1: nodeId は欠落時空（OPC-UA でなければ未使用）。
    s.nodeId = obj.value("nodeId").toString();
    return s;
}

QVariantMap SourceData::toVariantMap() const
{
    QVariantMap m;
    m.insert(QStringLiteral("connection"), connection);
    m.insert(QStringLiteral("reg"), reg);
    m.insert(QStringLiteral("address"), address);
    m.insert(QStringLiteral("poll"), poll);
    // Phase 9 / OP-1: nodeId は optional。QVariantMap は QML 往復用なので空でも入れておく。
    m.insert(QStringLiteral("nodeId"), nodeId);
    return m;
}

SourceData SourceData::fromVariantMap(const QVariantMap &map)
{
    SourceData s;
    s.connection = map.value(QStringLiteral("connection")).toString();
    s.reg = map.value(QStringLiteral("reg")).toString();
    s.address = map.value(QStringLiteral("address"), 0).toInt();
    s.poll = map.value(QStringLiteral("poll"), 1000).toInt();
    s.nodeId = map.value(QStringLiteral("nodeId")).toString();
    return s;
}

bool SourceData::isValidJson(const QJsonObject &obj)
{
    if (!obj.value("connection").isString() || obj.value("connection").toString().isEmpty()) {
        return false;
    }
    // Phase 9 / OP-1: proto 種別を source 自身のフィールド有無で弁別する（SourceData は接続の
    // proto を知らない）。Modbus は reg が 4 種のいずれか、OPC-UA は nodeId が非空であれば有効。
    // どちらも満たさない（reg も nodeId も無い / 不正）ものは従来どおり不正（Codex PR #139 [Major]）。
    const QString reg = obj.value("reg").toString();
    const bool regValid = reg == QStringLiteral("coil")
        || reg == QStringLiteral("discrete")
        || reg == QStringLiteral("input")
        || reg == QStringLiteral("holding");
    // nodeId は文字列型 + 非空のときのみ OPC-UA source として有効（数値等の型不正は弾く。
    // Codex / CodeRabbit PR #140）。
    const QJsonValue nodeIdVal = obj.value("nodeId");
    const bool nodeIdValid = nodeIdVal.isString() && !nodeIdVal.toString().isEmpty();
    if (!regValid && !nodeIdValid) {
        return false;
    }
    // address は 0 始まりの非負番地。存在する場合のみ検証（欠落時は fromJson が 0 を補う）。
    // 外部 JSON の不正値素通りを防ぐ（CodeRabbit PR #119）。OPC-UA source（reg/address 無し）でも
    // 害は無い（address を持たなければスキップ）。
    if (obj.contains("address") && obj.value("address").toInt(0) < 0) {
        return false;
    }
    return true;
}

} // namespace hmi::schema
