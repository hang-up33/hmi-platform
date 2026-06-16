#pragma once

#include <QJsonObject>
#include <QString>
#include <QVariantMap>

namespace hmi::schema {

// Phase 7 / MB-1: 変数ソース写像（変数 → どの接続の・どのレジスタを読み書きするか）。
// VariableData に optional で持つ（source 無し = 内部変数のまま＝後方互換）。実通信は
// MB-2 以降で、MB-1 ではこの定義を JSON / QVariantMap に round-trip させるだけ。
//   connection : ProjectData.connections[].id を参照する接続 id
//   reg        : "coil" / "discrete" / "input" / "holding"（書込可は coil / holding）
//   address    : 0 始まりのプロトコル番地（JSON / 内部の正準は 0 ベース）。既定 0
//   poll       : ポーリング周期 [ms]。既定 1000
struct SourceData {
    QString connection;
    QString reg;
    int address = 0;
    int poll = 1000;

    QJsonObject toJson() const;
    static SourceData fromJson(const QJsonObject &obj);

    // QML との往復用に QVariantMap（QtCore）と相互変換する（BindingData と同方針）。
    QVariantMap toVariantMap() const;
    static SourceData fromVariantMap(const QVariantMap &map);

    // connection と reg が非空、かつ reg が 4 種のいずれかなら有効。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
