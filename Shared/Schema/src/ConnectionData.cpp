#include "hmi/schema/ConnectionData.h"

#include <QJsonValue>

namespace hmi::schema {

QJsonObject ConnectionData::toJson() const
{
    QJsonObject obj;
    obj["id"] = id;
    obj["proto"] = proto;
    obj["host"] = host;
    obj["port"] = port;
    obj["unitId"] = unitId;
    // Phase 9 / OP-1: OPC-UA エンドポイントは optional。空のときは省略（Modbus 既存 JSON 無改変）。
    if (!endpoint.isEmpty()) {
        obj["endpoint"] = endpoint;
    }
    return obj;
}

ConnectionData ConnectionData::fromJson(const QJsonObject &obj)
{
    ConnectionData c;
    c.id = obj.value("id").toString();
    // 欠落時の既定：proto "modbusTcp"、port 502、unitId 1。
    c.proto = obj.value("proto").toString();
    if (c.proto.isEmpty()) {
        c.proto = QStringLiteral("modbusTcp");
    }
    c.host = obj.value("host").toString();
    c.port = obj.value("port").toInt(502);
    c.unitId = obj.value("unitId").toInt(1);
    // Phase 9 / OP-1: endpoint は欠落時空（OPC-UA でなければ未使用）。
    c.endpoint = obj.value("endpoint").toString();
    return c;
}

QVariantMap ConnectionData::toVariantMap() const
{
    QVariantMap m;
    m.insert(QStringLiteral("id"), id);
    m.insert(QStringLiteral("proto"), proto);
    m.insert(QStringLiteral("host"), host);
    m.insert(QStringLiteral("port"), port);
    m.insert(QStringLiteral("unitId"), unitId);
    // Phase 9 / OP-1: endpoint は optional。QVariantMap は QML 往復用なので空でも入れておく
    // （QML 側は空文字で「未設定」を判定でき、JSON 省略と挙動を分けない）。
    m.insert(QStringLiteral("endpoint"), endpoint);
    return m;
}

ConnectionData ConnectionData::fromVariantMap(const QVariantMap &map)
{
    ConnectionData c;
    c.id = map.value(QStringLiteral("id")).toString();
    c.proto = map.value(QStringLiteral("proto")).toString();
    if (c.proto.isEmpty()) {
        c.proto = QStringLiteral("modbusTcp");
    }
    c.host = map.value(QStringLiteral("host")).toString();
    c.port = map.value(QStringLiteral("port"), 502).toInt();
    c.unitId = map.value(QStringLiteral("unitId"), 1).toInt();
    c.endpoint = map.value(QStringLiteral("endpoint")).toString();
    return c;
}

bool ConnectionData::isValidJson(const QJsonObject &obj)
{
    if (!obj.value("id").isString() || obj.value("id").toString().isEmpty()) {
        return false;
    }
    // port は存在する場合のみ範囲検証（欠落時は fromJson が 502 を補う）。外部 JSON を
    // fromJson 経由で読む際の不正値素通りを防ぐ（CodeRabbit PR #119）。
    if (obj.contains("port")) {
        const int port = obj.value("port").toInt(0);
        if (port < 1 || port > 65535) {
            return false;
        }
    }
    return true;
}

} // namespace hmi::schema
