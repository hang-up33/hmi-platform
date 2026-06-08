#pragma once

#include "ScreenData.h"
#include "VariableData.h"

#include <QJsonObject>
#include <QList>
#include <QString>

namespace hmi::schema {

struct ProjectData {
    QString project;
    QList<ScreenData> screens;

    // Task 39: Project レベルの変数（タグ）定義。optional 配列で、空のとき toJson で省略
    // （後方互換）。実行時の現在値はランタイム変数ストア（T41）が保持し、ここは定義のみ。
    QList<VariableData> variables;

    QJsonObject toJson() const;
    static ProjectData fromJson(const QJsonObject &obj);

    // JSON が Project 形式として有効か（screens が配列で 1 件以上、各要素が
    // ScreenData として有効）を判定する。Editor / Simulator 側はこれが true の
    // ときだけ fromJson の結果を信頼できる。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
