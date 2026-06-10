#include "hmi/schema/VariableData.h"

#include <QJsonValue>

namespace hmi::schema {

namespace {
// Task 39（Codex PR #78 [P2]）：initial / value は **文字列表現**で保持する契約だが、
// 手書き JSON で `initial: true` / `5` のように非文字列が来ても **値を失わない**よう
// 文字列へ正規化する（`QJsonValue::toString()` は非文字列で空になり、bool/int が
// 静かに既定値へ落ちるのを防ぐ）。
QString jsonValueToString(const QJsonValue &v)
{
    if (v.isString()) {
        return v.toString();
    }
    if (v.isBool()) {
        return v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
    }
    if (v.isDouble()) {
        const double d = v.toDouble();
        const long long asInt = static_cast<long long>(d);
        if (static_cast<double>(asInt) == d) {
            return QString::number(asInt);  // 整数は整数表現に
        }
        return QString::number(d);
    }
    return QString();
}
} // namespace

QJsonObject VariableData::toJson() const
{
    QJsonObject obj;
    obj["name"] = name;
    obj["type"] = type;
    obj["initial"] = initial;
    return obj;
}

VariableData VariableData::fromJson(const QJsonObject &obj)
{
    VariableData v;
    v.name = obj.value("name").toString();
    v.type = obj.value("type").toString();
    // 非文字列 initial（bool/int）も文字列へ正規化して値を保つ。
    v.initial = jsonValueToString(obj.value("initial"));
    return v;
}

QVariantMap VariableData::toVariantMap() const
{
    QVariantMap m;
    m.insert(QStringLiteral("name"), name);
    m.insert(QStringLiteral("type"), type);
    m.insert(QStringLiteral("initial"), initial);
    return m;
}

VariableData VariableData::fromVariantMap(const QVariantMap &map)
{
    VariableData v;
    v.name = map.value(QStringLiteral("name")).toString();
    v.type = map.value(QStringLiteral("type")).toString();
    v.initial = map.value(QStringLiteral("initial")).toString();
    return v;
}

bool VariableData::isValidJson(const QJsonObject &obj)
{
    if (!obj.value("name").isString() || obj.value("name").toString().isEmpty()) {
        return false;
    }
    const QString t = obj.value("type").toString();
    return t == QStringLiteral("bool")
        || t == QStringLiteral("int")
        || t == QStringLiteral("string");
}

} // namespace hmi::schema
