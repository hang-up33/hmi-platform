#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariant>
#include <QVariantList>

QT_BEGIN_NAMESPACE
class QOpcUaClient;
class QOpcUaNode;
class QTimer;
QT_END_NAMESPACE

// Phase 9 / OP-2: PC（Simulator）/ 実機（Runtime）が OPC-UA クライアントになり、
// OPC-UA サーバ（PLC / ゲートウェイ）のノードを MonitoredItem 購読（subscription）して
// 既存の変数ストア + binding 経路へ流す。Modbus（ModbusController）の proto 2 本目に当たり、
// 設計は同型：
//   - 接続（connections[].id）ごとに 1 つの QOpcUaClient を作り、requestEndpoints →
//     endpointsRequestFinished で得たエンドポイント（MVP は securityPolicy None を優先）へ
//     connectToEndpoint する。
//   - 接続確立（ClientState::Connected）後に、その接続を参照する source（{connection,nodeId,poll}）
//     を持つ変数ごとに QOpcUaNode を作り、dataChangeOccurred を variableUpdated(name,value) で
//     emit して QML 側（Main.qml）が VariableStore.setValue へ接続する。
//   - **購読を主とし、購読不可ノードは source.poll[ms] 周期の読込（readAttributes）にフォールバック**
//     する（plan の方針。`poll=0` は「購読のみ＝フォールバックなし」を意味する。購読自体の発行間隔は
//     poll と無関係の固定既定 kSubscriptionIntervalMs を使う＝最速 Publish 要求による負荷を避ける）。
//   - 読込/購読のみ（書込・接続状態 UI・自動再接続は OP-4）。接続失敗 / ノードエラーは
//     qWarning() に記録して落ちない。
//
// 本クラスは **Simulator 共有ソース**に置く（Runtime が CMake glue でソース共有して
// 自動的に継承する。ModbusController と同じ配置）。Editor は `Qt6::OpcUa` を一切リンク
// しないので Editor には載らない（接続定義を JSON に書くだけ＝通信しない）。`hmi_schema`
// には絶対に置かない（Schema は通信を知らない）。
class OpcUaController : public QObject {
    Q_OBJECT
public:
    explicit OpcUaController(QObject *parent = nullptr);
    ~OpcUaController() override;

    // プロジェクトの connections[] と source 付き variables[] を受け取り、proto=="opcua" の
    // 接続を確立してノードを購読する。各 connection は {id,proto,endpoint,...} の QVariantMap、
    // 各 variable は {name,type,source:{connection,nodeId,poll}} の QVariantMap。
    // proto が opcua でない接続 / nodeId 無しの source / source 無し変数は無視する
    //（Modbus 専用の接続は ModbusController 側が拾う＝両 controller に同じ list を渡してよい）。
    Q_INVOKABLE void configure(const QVariantList &connections, const QVariantList &variables);

    // 全ノード購読停止・全接続切断（再 configure や終了時に呼ぶ）。
    Q_INVOKABLE void stop();

signals:
    // 購読で受けたノード値を変数名付きで通知する。QML 側が VariableStore.setValue へ接続。
    void variableUpdated(const QString &name, const QVariant &value);

private:
    // 1 つの購読対象（変数 → 接続/ノード写像）。
    struct NodeItem {
        QString name;
        QString connectionId;
        QString nodeId;
        // 購読不可時のフォールバック読込周期 [ms]（source.poll 由来）。0 = フォールバックなし（購読のみ）。
        int pollMs = 0;
    };

    // 接続確立後に、その接続のノードを生成して購読を開始する。
    void setupSubscriptions(const QString &connectionId, quint64 generation);

    // 購読の発行間隔 [ms]（source.poll とは別。最速 Publish 要求＝0 を避けるための固定既定）。
    static constexpr double kSubscriptionIntervalMs = 250.0;

    // 接続 id → クライアント。
    QHash<QString, QPointer<QOpcUaClient>> m_clients;
    // 接続 id → その接続を参照するノード購読対象。configure で構築、setupSubscriptions で消費。
    QHash<QString, QList<NodeItem>> m_itemsByConnection;
    // 生成済みノード（stop() で破棄する）。
    QList<QOpcUaNode *> m_nodes;
    // 購読不可ノードのフォールバック読込タイマ（stop() で破棄する）。
    QList<QTimer *> m_pollTimers;
    // configure()/stop() ごとに増やす世代カウンタ。非同期コールバック（endpointsRequestFinished /
    // stateChanged / dataChangeOccurred）が capture した世代と一致する時だけ処理し、プロジェクト
    // 切替後に旧接続由来の値が VariableStore へ混入するのを防ぐ（ModbusController と同型）。
    quint64 m_generation = 0;
};
