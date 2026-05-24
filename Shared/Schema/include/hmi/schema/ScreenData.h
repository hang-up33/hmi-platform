#pragma once

#include "WidgetData.h"

#include <QJsonObject>
#include <QList>
#include <QString>

namespace hmi::schema {

struct ScreenData {
    QString name;
    QList<WidgetData> widgets;

    QJsonObject toJson() const;
    static ScreenData fromJson(const QJsonObject &obj);
};

} // namespace hmi::schema
