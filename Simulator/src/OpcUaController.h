#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

QT_BEGIN_NAMESPACE
class QOpcUaClient;
class QOpcUaNode;
class QTimer;
QT_END_NAMESPACE

// Phase 9 / OP-2 + OP-4: PC（Simulator）/ 実機（Runtime）が OPC-UA クライアントになり、
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
//   - **OP-4：書込**：HMI 操作（NumericField 確定 / Button アクション）由来の変数更新を
//     writeAttribute(Value) で対応ノードへ書く（writeVariable）。読込（variableUpdated→setValue）
//     由来の変化では呼ばないこと（ModbusController と同じ経路分離で書戻しループを避ける）。
//   - **OP-4：接続状態**：接続 id → 状態文字列（connected/connecting/disconnected/error）を
//     Q_PROPERTY QVariantMap connectionStates + NOTIFY で公開する（MB-4 と同型）。
//   - **OP-4：自動再接続**：切断 / 接続失敗で Disconnected に戻ったら一定間隔で再接続を試みる
//     （世代カウンタで configure/stop 後の旧接続・旧購読・旧再接続タイマを確実に弾く）。
//   - 接続失敗 / ノードエラーは qWarning() に記録して落ちない。
//
// 本クラスは **Simulator 共有ソース**に置く（Runtime が CMake glue でソース共有して
// 自動的に継承する。ModbusController と同じ配置）。Editor は `Qt6::OpcUa` を一切リンク
// しないので Editor には載らない（接続定義を JSON に書くだけ＝通信しない）。`hmi_schema`
// には絶対に置かない（Schema は通信を知らない）。
class OpcUaController : public QObject {
    Q_OBJECT
    // OP-4: 接続 id → 状態文字列（"connected"/"connecting"/"disconnected"/"error"）のマップ。
    // QML が接続状態をラベル等へ最小表示できるよう公開する（MB-4 の connectionStates と同型）。
    Q_PROPERTY(QVariantMap connectionStates READ connectionStates NOTIFY connectionStatesChanged)
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

    // OP-4: HMI 操作（NumericField 確定 / Button アクション）由来の変数更新を OPC-UA ノードへ
    // 書き込む。name が OPC-UA source（nodeId）を持つ変数なら、対応接続の QOpcUaNode で
    // writeAttribute(Value) を発行する。source 無し / OPC-UA 以外の変数は no-op（呼ぶ側は気にせず
    // 一律に呼べる）。読込（variableUpdated→setValue）由来の変化では呼ばないこと（書戻しループ回避）。
    Q_INVOKABLE void writeVariable(const QString &name, const QVariant &value);

    // 接続 id → 状態文字列のマップ（Q_PROPERTY READ）。
    QVariantMap connectionStates() const { return m_connectionStates; }

signals:
    // 購読で受けたノード値を変数名付きで通知する。QML 側が VariableStore.setValue へ接続。
    void variableUpdated(const QString &name, const QVariant &value);

    // OP-4: 接続状態マップが変化したときに通知する。
    void connectionStatesChanged();

private:
    // 1 つの購読対象（変数 → 接続/ノード写像）。
    struct NodeItem {
        QString name;
        QString connectionId;
        QString nodeId;
        // 購読不可時のフォールバック読込周期 [ms]（source.poll 由来）。0 = フォールバックなし（購読のみ）。
        int pollMs = 0;
    };

    // OP-4: 書込対象（変数名 → 接続/ノード写像）。OPC-UA source を持つ変数を登録する。
    // variableType（"int"/"real"/"bool"/"string"）は writeAttribute に渡す OPC-UA 型を決めるのに使う
    // （QML から来る数値は QVariant で double になりがちで、サーバの Int32 ノードと型不一致になり
    //  書込が拒否されるため、変数定義の型に合わせて明示変換する）。
    struct WriteItem {
        QString connectionId;
        QString nodeId;
        QString variableType;
    };

    // 接続確立後に、その接続のノードを生成して購読を開始する。
    void setupSubscriptions(const QString &connectionId, quint64 generation);
    // OP-4: 指定接続の既存購読ノード / フォールバックタイマを破棄する（再接続時の再購読前に
    // 旧ノード/タイマを片付け、重複通知・タイマ多重起動を防ぐ）。
    void cleanupSubscriptions(const QString &connectionId);
    // OP-4: 接続状態の更新（重複通知を避けつつ connectionStatesChanged を emit）。
    void setConnectionState(const QString &id, const QString &state);
    // OP-4: 切断 / 接続失敗時の再接続を一定間隔で試みるタイマを開始する。
    void scheduleReconnect(const QString &id);
    // OP-4: 接続 id のエンドポイント探索を開始する（初回接続・再接続で共用）。
    void startDiscovery(const QString &id, quint64 generation);

    // 購読の発行間隔 [ms]（source.poll とは別。最速 Publish 要求＝0 を避けるための固定既定）。
    static constexpr double kSubscriptionIntervalMs = 250.0;
    // OP-4: 再接続の試行間隔 [ms]（poll とは独立した固定値。MB-4 と同型）。
    static constexpr int kReconnectIntervalMs = 4000;

    // 接続 id → クライアント。
    QHash<QString, QPointer<QOpcUaClient>> m_clients;
    // 接続 id → エンドポイント URL（再接続時の再 discovery に使う）。
    QHash<QString, QString> m_endpoints;
    // 接続 id → その接続を参照するノード購読対象。configure で構築、setupSubscriptions で消費。
    QHash<QString, QList<NodeItem>> m_itemsByConnection;
    // OP-4: 変数名 → 書込写像（OPC-UA source を持つ変数）。writeVariable で引く。
    QHash<QString, WriteItem> m_writeItems;
    // OP-4: 接続 id → 状態文字列（QML 公開用）。
    QVariantMap m_connectionStates;
    // OP-4: 接続 id → 再接続タイマ。stop() / configure() で確実に止める。
    QHash<QString, QTimer *> m_reconnectTimers;
    // 接続 id → 生成済み購読ノード（再接続時は接続単位で破棄・再作成、stop() で全破棄する）。
    QHash<QString, QList<QOpcUaNode *>> m_nodes;
    // 接続 id → 購読不可ノードのフォールバック読込タイマ（接続単位で破棄、stop() で全破棄する）。
    QHash<QString, QList<QTimer *>> m_pollTimers;
    // OP-4: 書込専用に作ったノード（attributeWritten 完了で個別破棄。ただし完了前に stop() が
    // 走った場合に client より先に同期破棄するため追跡する＝client より長生きさせない）。
    QList<QOpcUaNode *> m_writeNodes;
    // configure()/stop() ごとに増やす世代カウンタ。非同期コールバック（endpointsRequestFinished /
    // stateChanged / dataChangeOccurred）が capture した世代と一致する時だけ処理し、プロジェクト
    // 切替後に旧接続由来の値が VariableStore へ混入するのを防ぐ（ModbusController と同型）。
    quint64 m_generation = 0;
};
