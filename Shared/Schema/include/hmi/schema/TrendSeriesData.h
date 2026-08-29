#pragma once

#include <QJsonObject>
#include <QString>
#include <QVariantMap>

namespace hmi::schema {

// Task 8B-A（Phase 8-B）: Trend の 1 系列（折れ線 1 本）の定義。WidgetData に optional 配列
// （series）で持ち、N 本の折れ線を重ね描く。Phase 8 の単系列は series 空＝既存 value バインド +
// lineColor を暗黙 1 系列として扱う（後方互換。設計の正本は
// Docs/archive/phase8b-trend-extend-plan.md「§Task 8B-A」）。
//   variable : サンプル源の変数名（VariableStore のキー。必須）
//   color    : 線色 "#RRGGBB"。空 = 未指定（HmiTrend の系列既定パレットへ解決）
//   label    : 凡例ラベル。空 = 未指定（凡例では変数名にフォールバック）
// ActionData / BindingData と同じ三点セット（toJson/fromJson/isValidJson）+ QVariantMap 往復。
struct TrendSeriesData {
    QString variable;
    QString color;
    QString label;

    QJsonObject toJson() const;
    static TrendSeriesData fromJson(const QJsonObject &obj);

    // QML との往復用に QVariantMap（QtCore）と相互変換する（ActionData / BindingData と同方針）。
    QVariantMap toVariantMap() const;
    static TrendSeriesData fromVariantMap(const QVariantMap &map);

    // variable が非空なら有効（color / label は optional）。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
