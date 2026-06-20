#pragma once

#include <QJsonObject>
#include <QString>
#include <QVariantMap>

namespace hmi::schema {

// Phase 7 / MB-1: 変数ソース写像（変数 → どの接続の・どのレジスタ / ノードを読み書きするか）。
// VariableData に optional で持つ（source 無し = 内部変数のまま＝後方互換）。実通信は
// MB-2 / OP-2 以降で、ここでは定義を JSON / QVariantMap に round-trip させるだけ。
//   connection : ProjectData.connections[].id を参照する接続 id
//   reg        : Modbus 用。"coil" / "discrete" / "input" / "holding"（書込可は coil / holding）
//   address    : Modbus 用。0 始まりのプロトコル番地（JSON / 内部の正準は 0 ベース）。既定 0
//   poll       : ポーリング周期 [ms]。既定 1000（OPC-UA は購読不可時のフォールバック周期）
//   nodeId     : OPC-UA 用。ノード id（例 "ns=2;s=Spindle.Temp"）。optional（空時 toJson 省略）。
//                Phase 9 / OP-1。Modbus は reg/address、OPC-UA は nodeId で対象を指す。
struct SourceData {
    QString connection;
    QString reg;
    int address = 0;
    int poll = 1000;
    QString nodeId;

    QJsonObject toJson() const;
    static SourceData fromJson(const QJsonObject &obj);

    // QML との往復用に QVariantMap（QtCore）と相互変換する（BindingData と同方針）。
    QVariantMap toVariantMap() const;
    static SourceData fromVariantMap(const QVariantMap &map);

    // connection が非空、かつ（reg が 4 種のいずれか〔Modbus〕 または nodeId が非空〔OPC-UA〕）
    // なら有効。proto を知らずに source が持つフィールドの有無で proto 種別を弁別する
    // （Phase 9 / OP-1。Codex PR #139 [Major]）。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
