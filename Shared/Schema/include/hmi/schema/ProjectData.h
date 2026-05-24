#pragma once

#include "ScreenData.h"

#include <QJsonObject>
#include <QList>
#include <QString>

namespace hmi::schema {

struct ProjectData {
    QString project;
    QList<ScreenData> screens;

    QJsonObject toJson() const;
    static ProjectData fromJson(const QJsonObject &obj);
};

} // namespace hmi::schema
