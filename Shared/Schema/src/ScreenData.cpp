#include "hmi/schema/ScreenData.h"

#include <QJsonArray>

namespace hmi::schema {

QJsonObject ScreenData::toJson() const
{
    QJsonArray arr;
    for (const auto &w : widgets) {
        arr.append(w.toJson());
    }
    QJsonObject obj;
    obj["name"] = name;
    obj["widgets"] = arr;
    return obj;
}

ScreenData ScreenData::fromJson(const QJsonObject &obj)
{
    ScreenData s;
    s.name = obj.value("name").toString();
    const QJsonArray arr = obj.value("widgets").toArray();
    s.widgets.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        s.widgets.append(WidgetData::fromJson(v.toObject()));
    }
    return s;
}

} // namespace hmi::schema
