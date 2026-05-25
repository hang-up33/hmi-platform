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

    // JSON が Screen 形式として有効か（widgets が配列で、各要素が WidgetData として
    // 有効）を判定する。widgets が空配列であること自体は許容する（新規 Screen）。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
