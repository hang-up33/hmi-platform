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

    // Task 28: スタイル属性（縦スライス）。いずれも optional（既定値は「未指定」を表し、
    // toJson で省略書き出し、fromJson で既定値埋め）。後方互換のため isValidJson の
    // 必須集合（id/type/width/height）には含めない。値の表現は HmiButton が解釈できる
    // 形式に合わせる：色は "#RRGGBB" 文字列（空 = 未指定）、fontSize は int px（0 = 未指定）。
    // 実際の既定外観（#4cc9f0 / white / 14px）は描画の唯一の真実である HmiButton 側に持つ。
    QString backgroundColor;
    QString textColor;
    int fontSize = 0;

    QJsonObject toJson() const;
    static WidgetData fromJson(const QJsonObject &obj);

    // JSON が Widget 形式として有効か（id / type / width / height が必要な型で
    // 揃っているか）を判定する。fromJson はキー欠落時に既定値で埋める緩い設計の
    // ため、読込時に「正しい形式かどうか」を判定する際はこちらを使う。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
