#include "OpcUaController.h"

#include <QDebug>
#include <QOpcUaClient>
#include <QOpcUaEndpointDescription>
#include <QOpcUaMonitoringParameters>
#include <QOpcUaNode>
#include <QOpcUaProvider>
#include <QTimer>
#include <QUrl>

OpcUaController::OpcUaController(QObject *parent) : QObject(parent) {}

OpcUaController::~OpcUaController()
{
    stop();
}

void OpcUaController::configure(const QVariantList &connections, const QVariantList &variables)
{
    // 世代を進める（stop() 内でも進むが明示）。これ以前に発行済みの非同期コールバックは
    // 世代チェックで弾かれる。
    ++m_generation;
    // 再 configure（プロジェクト読み替え）に備えて一旦全停止。
    stop();

    // source を持つ変数を接続 id ごとの購読対象に振り分ける（接続生成より先に作っておくと
    // setupSubscriptions が接続確立時に引ける）。nodeId 無し = OPC-UA 対象でないので無視。
    for (const QVariant &vv : variables) {
        const QVariantMap v = vv.toMap();
        const QString name = v.value(QStringLiteral("name")).toString();
        if (name.isEmpty()) {
            continue;
        }
        const QVariant sourceVar = v.value(QStringLiteral("source"));
        if (!sourceVar.isValid() || sourceVar.isNull()) {
            continue; // source 無し = 内部変数のまま（後方互換）。
        }
        const QVariantMap s = sourceVar.toMap();
        if (s.isEmpty()) {
            continue;
        }
        const QString connectionId = s.value(QStringLiteral("connection")).toString();
        const QString nodeId = s.value(QStringLiteral("nodeId")).toString();
        if (connectionId.isEmpty() || nodeId.isEmpty()) {
            // connection / nodeId が無い source は OPC-UA 対象でない（Modbus 等）。黙って無視。
            continue;
        }
        NodeItem item;
        item.name = name;
        item.connectionId = connectionId;
        item.nodeId = nodeId;
        // OPC-UA の poll は**購読不可時のフォールバック読込周期 [ms]**（plan の定義）。**0 は
        // 「購読のみ＝フォールバックなし」を意味する正当値**で、Editor/Schema も OPC-UA 既定として
        // poll=0 を保存する（Modbus の 1000ms 既定と違う）。購読自体の発行間隔には使わない（それは
        // kSubscriptionIntervalMs）。負値（不正）だけ 0 へ補正して 0 はそのまま保持する。
        int poll = s.value(QStringLiteral("poll"), 0).toInt();
        if (poll < 0) {
            poll = 0;
        }
        item.pollMs = poll;
        m_itemsByConnection[connectionId].append(item);
    }

    // proto=="opcua" の接続を用意する。
    for (const QVariant &cv : connections) {
        const QVariantMap c = cv.toMap();
        const QString id = c.value(QStringLiteral("id")).toString();
        if (id.isEmpty()) {
            continue;
        }
        const QString proto = c.value(QStringLiteral("proto"),
                                      QStringLiteral("modbusTcp")).toString();
        if (proto != QStringLiteral("opcua")) {
            continue; // Modbus 等は ModbusController が拾う（同じ list を両者へ渡してよい）。
        }
        const QString endpoint = c.value(QStringLiteral("endpoint")).toString();
        if (endpoint.isEmpty()) {
            qWarning().noquote() << "OpcUaController: empty endpoint for connection" << id
                                 << "(skipped)";
            continue;
        }
        // この接続を参照するノードが 1 つも無ければクライアントを作らない（無駄な接続を避ける）。
        if (!m_itemsByConnection.contains(id)) {
            continue;
        }

        QOpcUaProvider provider;
        const QStringList backends = provider.availableBackends();
        if (backends.isEmpty()) {
            qWarning().noquote()
                << "OpcUaController: no OPC-UA backend plugin available (need open62541);"
                << "connection" << id << "skipped";
            continue;
        }
        const QString backend = backends.contains(QStringLiteral("open62541"))
                                    ? QStringLiteral("open62541")
                                    : backends.first();
        QOpcUaClient *client = provider.createClient(backend);
        if (!client) {
            qWarning().noquote() << "OpcUaController: createClient(" << backend
                                 << ") failed for connection" << id;
            continue;
        }
        client->setParent(this);

        const quint64 generation = m_generation;
        // エンドポイント探索の結果。MVP は securityPolicy None（無暗号・匿名）を優先する。
        QObject::connect(client, &QOpcUaClient::endpointsRequestFinished, this,
                         [this, id, generation, client](
                             const QList<QOpcUaEndpointDescription> &endpoints,
                             QOpcUa::UaStatusCode statusCode, const QUrl &) {
                             if (generation != m_generation) {
                                 return; // 旧世代は無視。
                             }
                             if (statusCode != QOpcUa::UaStatusCode::Good
                                 || endpoints.isEmpty()) {
                                 qWarning().noquote()
                                     << "OpcUaController: no endpoints for connection" << id
                                     << "status" << statusCode;
                                 return;
                             }
                             // securityPolicy None を優先（無ければ先頭）。
                             QOpcUaEndpointDescription chosen = endpoints.constFirst();
                             for (const QOpcUaEndpointDescription &ep : endpoints) {
                                 if (ep.securityPolicy().endsWith(QStringLiteral("#None"))) {
                                     chosen = ep;
                                     break;
                                 }
                             }
                             client->connectToEndpoint(chosen);
                         });

        // 接続状態が Connected になったらノード購読を開始する。
        QObject::connect(client, &QOpcUaClient::stateChanged, this,
                         [this, id, generation](QOpcUaClient::ClientState state) {
                             if (generation != m_generation) {
                                 return;
                             }
                             if (state == QOpcUaClient::Connected) {
                                 setupSubscriptions(id, generation);
                             }
                         });

        QObject::connect(client, &QOpcUaClient::errorChanged, this,
                         [id](QOpcUaClient::ClientError error) {
                             if (error != QOpcUaClient::NoError) {
                                 qWarning().noquote()
                                     << "OpcUaController: connection" << id << "error" << error;
                             }
                         });

        m_clients.insert(id, client);
        client->requestEndpoints(QUrl(endpoint));
    }
}

void OpcUaController::setupSubscriptions(const QString &connectionId, quint64 generation)
{
    QOpcUaClient *client = m_clients.value(connectionId);
    if (!client) {
        return;
    }
    const QList<NodeItem> items = m_itemsByConnection.value(connectionId);
    for (const NodeItem &item : items) {
        QOpcUaNode *node = client->node(item.nodeId);
        if (!node) {
            qWarning().noquote() << "OpcUaController: cannot create node" << item.nodeId
                                 << "for variable" << item.name << "(skipped)";
            continue;
        }
        node->setParent(this);
        const QString name = item.name;
        const int pollMs = item.pollMs;
        // 値（購読の変化通知）を variableUpdated へ流す。値の型（Double/Int32/Boolean…）は
        // QVariant のまま渡し、QML 側 VariableStore.coerce が変数型（int/real/bool）へ寄せる。
        QObject::connect(node, &QOpcUaNode::dataChangeOccurred, this,
                         [this, name, generation](QOpcUa::NodeAttribute attr,
                                                  const QVariant &value) {
                             if (generation != m_generation) {
                                 return;
                             }
                             if (attr == QOpcUa::NodeAttribute::Value) {
                                 emit variableUpdated(name, value);
                             }
                         });
        // フォールバック読込（readAttributes）の結果も同じく variableUpdated へ流す。
        QObject::connect(node, &QOpcUaNode::attributeRead, this,
                         [this, node, name, generation](QOpcUa::NodeAttributes attrs) {
                             if (generation != m_generation) {
                                 return;
                             }
                             if (attrs.testFlag(QOpcUa::NodeAttribute::Value)
                                 && node->valueAttributeError() == QOpcUa::UaStatusCode::Good) {
                                 emit variableUpdated(name, node->valueAttribute());
                             }
                         });
        // 購読作成が失敗したノードは、poll>0 なら poll 周期の readAttributes へフォールバックする
        // （MonitoredItem を拒否する実サーバ/ノード対策。poll=0＝購読のみ指定なら警告のみ）。
        QObject::connect(node, &QOpcUaNode::enableMonitoringFinished, this,
                         [this, node, name, pollMs, generation](QOpcUa::NodeAttribute,
                                                                QOpcUa::UaStatusCode status) {
                             if (generation != m_generation
                                 || status == QOpcUa::UaStatusCode::Good) {
                                 return; // 購読成功（または旧世代）なら何もしない。
                             }
                             if (pollMs <= 0) {
                                 qWarning().noquote()
                                     << "OpcUaController: enableMonitoring failed for" << name
                                     << "status" << status << "(no poll fallback; poll=0)";
                                 return;
                             }
                             qWarning().noquote()
                                 << "OpcUaController: enableMonitoring failed for" << name
                                 << "status" << status << "- falling back to poll" << pollMs
                                 << "ms";
                             auto *timer = new QTimer(this);
                             timer->setInterval(pollMs);
                             QObject::connect(timer, &QTimer::timeout, node,
                                              [node]() {
                                                  node->readAttributes(
                                                      QOpcUa::NodeAttribute::Value);
                                              });
                             timer->start();
                             m_pollTimers.append(timer);
                             node->readAttributes(QOpcUa::NodeAttribute::Value); // 初回即読み。
                         });
        // 購読の発行間隔は poll と無関係の固定既定（0 直渡し＝最速 Publish 要求を避ける）。
        node->enableMonitoring(QOpcUa::NodeAttribute::Value,
                               QOpcUaMonitoringParameters(kSubscriptionIntervalMs));
        m_nodes.append(node);
    }
}

void OpcUaController::stop()
{
    // 世代を進め、発行済みの非同期コールバックを無効化する。
    ++m_generation;

    // フォールバック読込タイマを止めて破棄する（ノード破棄前に止めて、停止後の readAttributes を防ぐ）。
    for (QTimer *timer : std::as_const(m_pollTimers)) {
        if (timer) {
            timer->stop();
            delete timer;
        }
    }
    m_pollTimers.clear();

    // ノードは生成元 QOpcUaClient の存続中だけ有効なので、**クライアントより先に同期破棄**する
    // （`deleteLater` だとアプリ終了時にイベントループ停止後まで処理されず、同じ親〔this〕配下の
    // クライアントが先に消えてノード破棄が未定義動作になり得る＝Codex PR #143 [Major]）。
    // 直接 delete はシグナル接続も切る。stop() はノードのシグナル発火中からは呼ばれない。
    for (QOpcUaNode *node : std::as_const(m_nodes)) {
        delete node;
    }
    m_nodes.clear();

    // ノードを片付けた後にクライアントを破棄する（ノードはもう client を参照しない）。
    for (const QPointer<QOpcUaClient> &client : std::as_const(m_clients)) {
        if (client) {
            client->disconnectFromEndpoint();
            delete client;
        }
    }
    m_clients.clear();
    m_itemsByConnection.clear();
}
