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
    return s;
}

QVariantMap SourceData::toVariantMap() const
{
    QVariantMap m;
    m.insert(QStringLiteral("connection"), connection);
    m.insert(QStringLiteral("reg"), reg);
    m.insert(QStringLiteral("address"), address);
    m.insert(QStringLiteral("poll"), poll);
    return m;
}

SourceData SourceData::fromVariantMap(const QVariantMap &map)
{
    SourceData s;
    s.connection = map.value(QStringLiteral("connection")).toString();
    s.reg = map.value(QStringLiteral("reg")).toString();
    s.address = map.value(QStringLiteral("address"), 0).toInt();
    s.poll = map.value(QStringLiteral("poll"), 1000).toInt();
    return s;
}

bool SourceData::isValidJson(const QJsonObject &obj)
{
    if (!obj.value("connection").isString() || obj.value("connection").toString().isEmpty()) {
        return false;
    }
    const QString reg = obj.value("reg").toString();
    if (reg != QStringLiteral("coil")
        && reg != QStringLiteral("discrete")
        && reg != QStringLiteral("input")
        && reg != QStringLiteral("holding")) {
        return false;
    }
    // address は 0 始まりの非負番地。存在する場合のみ検証（欠落時は fromJson が 0 を補う）。
    // 外部 JSON の不正値素通りを防ぐ（CodeRabbit PR #119）。
    if (obj.contains("address") && obj.value("address").toInt(0) < 0) {
        return false;
    }
    return true;
}

} // namespace hmi::schema
