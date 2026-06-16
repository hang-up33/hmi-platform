#pragma once

#include "ConnectionData.h"
#include "ScreenData.h"
#include "VariableData.h"

#include <QByteArray>
#include <QJsonObject>
#include <QList>
#include <QString>

#include <optional>

namespace hmi::schema {

struct ProjectData {
    QString project;
    QList<ScreenData> screens;

    // Task 39: Project レベルの変数（タグ）定義。optional 配列で、空のとき toJson で省略
    // （後方互換）。実行時の現在値はランタイム変数ストア（T41）が保持し、ここは定義のみ。
    QList<VariableData> variables;

    // Phase 7 / MB-1: プロジェクト共通の接続定義（PLC への接続先）。optional 配列で空のとき
    // 省略（後方互換）。VariableData.source.connection がこの id を参照する。
    QList<ConnectionData> connections;

    QJsonObject toJson() const;
    static ProjectData fromJson(const QJsonObject &obj);

    // JSON が Project 形式として有効か（screens が配列で 1 件以上、各要素が
    // ScreenData として有効）を判定する。Editor / Simulator 側はこれが true の
    // ときだけ fromJson の結果を信頼できる。
    static bool isValidJson(const QJsonObject &obj);

    // JSON バイト列を **検証付きで** パースする。JSON として不正、または Project 形式として
    // 無効（`isValidJson` が false）なら `std::nullopt` を返す。読込側（ProjectIo /
    // ProjectLoader）が個別に「parse → isObject → isValidJson → fromJson」を書くのをやめ、
    // 「検証してから fromJson」を **この 1 箇所に強制**する（検証の取りこぼし防止）。
    // ファイル / QUrl の読込は OS I/O なので利用側アプリに残し、ここはバイト列のみ受ける
    //（Schema は QFile を持たず、データ + JSON の責務に閉じる）。
    static std::optional<ProjectData> parseValidated(const QByteArray &json);
};

} // namespace hmi::schema
