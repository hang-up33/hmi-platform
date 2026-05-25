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

    // JSON が Project 形式として有効か（screens が配列で 1 件以上、各要素が
    // ScreenData として有効）を判定する。Editor / Simulator 側はこれが true の
    // ときだけ fromJson の結果を信頼できる。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
