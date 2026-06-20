#pragma once

#include <QJsonObject>
#include <QString>
#include <QVariantMap>

namespace hmi::schema {

// Phase 7 / MB-1: プロジェクト共通の接続定義（PLC への接続先）。ProjectData に optional 配列で
// 持つ（複数変数が同一 PLC を指す実態に合わせ host/port/unitId の重複を防ぐ）。変数側は
// SourceData.connection でこの id を参照する。実通信は MB-2 以降で、MB-1 では round-trip のみ。
//   id       : 接続 id（SourceData.connection から参照される）
//   proto    : プロトコル。既定 "modbusTcp"（"opcua" で OPC-UA）
//   host     : 接続先ホスト（IP / ホスト名）。Modbus 用
//   port     : TCP ポート。既定 502。Modbus 用
//   unitId   : Modbus ユニット id。既定 1。Modbus 用
//   endpoint : OPC-UA エンドポイント URL（例 "opc.tcp://192.168.0.20:4840"）。OPC-UA 用・
//              optional（空時 toJson 省略＝Modbus 既存 JSON は無改変）。Phase 9 / OP-1。
struct ConnectionData {
    QString id;
    QString proto = QStringLiteral("modbusTcp");
    QString host;
    int port = 502;
    int unitId = 1;
    QString endpoint;

    QJsonObject toJson() const;
    static ConnectionData fromJson(const QJsonObject &obj);

    // QML との往復用に QVariantMap（QtCore）と相互変換する（BindingData と同方針）。
    QVariantMap toVariantMap() const;
    static ConnectionData fromVariantMap(const QVariantMap &map);

    // id が非空なら有効（host は空でも編集途中を許容する）。
    static bool isValidJson(const QJsonObject &obj);
};

} // namespace hmi::schema
