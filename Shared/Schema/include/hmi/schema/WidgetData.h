#pragma once

#include <QJsonObject>
#include <QString>

namespace hmi::schema {

struct WidgetData {
    QString id;
    QString type;
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;
    QString text;
    QString tag;

    QJsonObject toJson() const;
    static WidgetData fromJson(const QJsonObject &obj);
};

} // namespace hmi::schema
