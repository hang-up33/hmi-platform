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
        // 小数（real 初期値）。`QString::number(d)` の既定は有効 6 桁で、
        // `0.123456789` のような real 初期値が読込時に丸められ round-trip が壊れる
        // （Codex PR #112 [P2]）。**round-trip する最短桁数**を探して返す：精度を 1→17 と
        // 上げ、`toDouble()` で元値に戻る最小桁を採用する（`'g',17` 固定だと 0.1 が
        // "0.10000000000000001" のように冗長化するのを避けつつ、高精度小数も保つ）。
        for (int prec = 1; prec < 17; ++prec) {
            const QString s = QString::number(d, 'g', prec);
            if (s.toDouble() == d) {
                return s;
            }
        }
        return QString::number(d, 'g', 17);
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
        || t == QStringLiteral("real")
        || t == QStringLiteral("string");
}

} // namespace hmi::schema
