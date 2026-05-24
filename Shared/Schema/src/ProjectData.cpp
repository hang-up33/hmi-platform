#include "hmi/schema/ProjectData.h"

#include <QJsonArray>

namespace hmi::schema {

QJsonObject ProjectData::toJson() const
{
    QJsonArray arr;
    for (const auto &s : screens) {
        arr.append(s.toJson());
    }
    QJsonObject obj;
    obj["project"] = project;
    obj["screens"] = arr;
    return obj;
}

ProjectData ProjectData::fromJson(const QJsonObject &obj)
{
    ProjectData p;
    p.project = obj.value("project").toString();
    const QJsonArray arr = obj.value("screens").toArray();
    p.screens.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        p.screens.append(ScreenData::fromJson(v.toObject()));
    }
    return p;
}

} // namespace hmi::schema
