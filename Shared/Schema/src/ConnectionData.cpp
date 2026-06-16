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
    return c;
}

bool ConnectionData::isValidJson(const QJsonObject &obj)
{
    return obj.value("id").isString() && !obj.value("id").toString().isEmpty();
}

} // namespace hmi::schema
