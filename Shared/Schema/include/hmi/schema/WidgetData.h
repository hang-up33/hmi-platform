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

    // JSON が Widget 形式として有効か（id / type / width / height が必要な型で
    // 揃っているか）を判定する。fromJson はキー欠落時に既定値で埋める緩い設計の
    // ため、読込時に「正しい形式かどうか」を判定する際はこちらを使う。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
