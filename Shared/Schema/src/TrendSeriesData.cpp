#include "hmi/schema/TrendSeriesData.h"

namespace hmi::schema {

QJsonObject TrendSeriesData::toJson() const
{
    QJsonObject obj;
    obj["variable"] = variable;
    // color / label は空（= 未指定）のとき省略（後方互換・他の optional 文字列と同方針）。
    if (!color.isEmpty()) {
        obj["color"] = color;
    }
    if (!label.isEmpty()) {
        obj["label"] = label;
    }
    return obj;
}

TrendSeriesData TrendSeriesData::fromJson(const QJsonObject &obj)
{
    TrendSeriesData s;
    s.variable = obj.value("variable").toString();
    s.color = obj.value("color").toString();
    s.label = obj.value("label").toString();
    return s;
}

QVariantMap TrendSeriesData::toVariantMap() const
{
    QVariantMap m;
    m.insert(QStringLiteral("variable"), variable);
    m.insert(QStringLiteral("color"), color);
    m.insert(QStringLiteral("label"), label);
    return m;
}

TrendSeriesData TrendSeriesData::fromVariantMap(const QVariantMap &map)
{
    TrendSeriesData s;
    s.variable = map.value(QStringLiteral("variable")).toString();
    s.color = map.value(QStringLiteral("color")).toString();
    s.label = map.value(QStringLiteral("label")).toString();
    return s;
}

bool TrendSeriesData::isValidJson(const QJsonObject &obj)
{
    // variable は必須（非空文字列）。color / label は optional だが、**存在する場合は
    // 文字列であることを要求する**（CodeRabbit PR #132）。さもないと {"variable":"v1","color":123}
    // のような不正値が有効扱いになり、fromJson が空文字へ畳んで値が黙って欠落する。
    if (!obj.value("variable").isString() || obj.value("variable").toString().isEmpty()) {
        return false;
    }
    if (obj.contains("color") && !obj.value("color").isString()) {
        return false;
    }
    if (obj.contains("label") && !obj.value("label").isString()) {
        return false;
    }
    return true;
}

} // namespace hmi::schema
