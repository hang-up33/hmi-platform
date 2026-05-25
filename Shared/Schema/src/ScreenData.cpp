#include "hmi/schema/ScreenData.h"

#include <QJsonArray>
#include <QJsonValue>

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

bool ScreenData::isValidJson(const QJsonObject &obj)
{
    if (!obj.value("widgets").isArray()) {
        return false;
    }
    const QJsonArray arr = obj.value("widgets").toArray();
    for (const QJsonValue &v : arr) {
        if (!v.isObject() || !WidgetData::isValidJson(v.toObject())) {
            return false;
        }
    }
    return true;
}

} // namespace hmi::schema
