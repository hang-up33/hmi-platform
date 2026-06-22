#include "hmi/schema/ScreenData.h"

#include "SchemaJsonIo_p.h"

#include <QJsonArray>
#include <QJsonValue>

namespace hmi::schema {

using namespace hmi::schema::detail;

QJsonObject ScreenData::toJson() const
{
    // widgets は（空でも）必須キーとして常に書き出す（後方互換・読込側の前提）。
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
    s.widgets = jsonArrayToList<WidgetData>(obj.value("widgets"));
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
