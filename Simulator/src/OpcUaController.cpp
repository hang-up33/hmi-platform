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

        // OP-4: 書込写像にも登録する（OPC-UA は AccessLevel で書込可否が決まるが MVP は
        // 「書けるノードへ書く・失敗はログ」とし、Editor は読/書を区別しない＝plan の方針）。
        WriteItem witem;
        witem.connectionId = connectionId;
        witem.nodeId = nodeId;
        witem.variableType = v.value(QStringLiteral("type"),
                                     QStringLiteral("string")).toString();
        m_writeItems.insert(name, witem);
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
                                 // 探索失敗は未接続のままなので再接続をスケジュールする（OP-4）。
                                 setConnectionState(id, QStringLiteral("disconnected"));
                                 scheduleReconnect(id);
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

        // 接続状態を QML へ反映し、Connected で購読開始・Disconnected で再接続を試みる（OP-4）。
        QObject::connect(client, &QOpcUaClient::stateChanged, this,
                         [this, id, generation](QOpcUaClient::ClientState state) {
                             if (generation != m_generation) {
                                 return;
                             }
                             switch (state) {
                             case QOpcUaClient::Connecting:
                                 setConnectionState(id, QStringLiteral("connecting"));
                                 break;
                             case QOpcUaClient::Connected:
                                 setConnectionState(id, QStringLiteral("connected"));
                                 // 再接続タイマが回っていれば止める（接続が戻った）。
                                 if (QTimer *t = m_reconnectTimers.take(id)) {
                                     t->stop();
                                     t->deleteLater();
                                 }
                                 setupSubscriptions(id, generation);
                                 break;
                             case QOpcUaClient::Disconnected:
                                 setConnectionState(id, QStringLiteral("disconnected"));
                                 // 接続が落ちた / 接続失敗で未接続に戻ったら再接続を試みる。
                                 scheduleReconnect(id);
                                 break;
                             default:
                                 break;
                             }
                         });

        QObject::connect(client, &QOpcUaClient::errorChanged, this,
                         [this, id, generation](QOpcUaClient::ClientError error) {
                             if (generation != m_generation) {
                                 return;
                             }
                             if (error != QOpcUaClient::NoError) {
                                 qWarning().noquote()
                                     << "OpcUaController: connection" << id << "error" << error;
                                 // 接続エラーは状態を "error" にする（state は別途 stateChanged で更新）。
                                 if (error == QOpcUaClient::ConnectionError) {
                                     setConnectionState(id, QStringLiteral("error"));
                                 }
                             }
                         });

        m_clients.insert(id, client);
        m_endpoints.insert(id, endpoint);
        startDiscovery(id, generation);
    }
}

void OpcUaController::startDiscovery(const QString &id, quint64 generation)
{
    if (generation != m_generation) {
        return;
    }
    QOpcUaClient *client = m_clients.value(id);
    if (!client) {
        return;
    }
    const QString endpoint = m_endpoints.value(id);
    if (endpoint.isEmpty()) {
        return;
    }
    // discovery 中は connecting 扱いにして UI に出す（接続確立で connected に更新される）。
    setConnectionState(id, QStringLiteral("connecting"));
    // requestEndpoints が false なら endpointsRequestFinished が来ない（endpoint URL 不正 /
    // backend が GetEndpoints を送出できない等）。そのまま放置すると connecting で固着し
    // 自動再接続も始まらないため、disconnected に戻して再接続をスケジュールする
    // （Codex PR #145 [Major]）。
    if (!client->requestEndpoints(QUrl(endpoint))) {
        qWarning().noquote() << "OpcUaController: requestEndpoints failed for connection" << id
                             << "endpoint" << endpoint << "- will retry";
        setConnectionState(id, QStringLiteral("disconnected"));
        scheduleReconnect(id);
    }
}

void OpcUaController::setupSubscriptions(const QString &connectionId, quint64 generation)
{
    QOpcUaClient *client = m_clients.value(connectionId);
    if (!client) {
        return;
    }
    // 再接続（Disconnected→Connected）のたびに呼ばれるため、まず当該接続の旧ノード/旧タイマを
    // 片付ける（残すと同じ変数のノード/タイマが再作成され続け、重複通知・不要 readAttributes・
    // リソース増加につながる＝Codex PR #145 [Major]）。初回接続時は no-op。
    cleanupSubscriptions(connectionId);
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
                         [this, node, name, pollMs, generation,
                          connectionId](QOpcUa::NodeAttribute, QOpcUa::UaStatusCode status) {
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
                             m_pollTimers[connectionId].append(timer);
                             node->readAttributes(QOpcUa::NodeAttribute::Value); // 初回即読み。
                         });
        // 購読の発行間隔は poll と無関係の固定既定（0 直渡し＝最速 Publish 要求を避ける）。
        node->enableMonitoring(QOpcUa::NodeAttribute::Value,
                               QOpcUaMonitoringParameters(kSubscriptionIntervalMs));
        m_nodes[connectionId].append(node);
    }
}

void OpcUaController::cleanupSubscriptions(const QString &connectionId)
{
    // タイマを先に止めて破棄する（ノード破棄前に止めて、停止後の readAttributes を防ぐ）。
    const QList<QTimer *> timers = m_pollTimers.take(connectionId);
    for (QTimer *timer : timers) {
        if (timer) {
            timer->stop();
            delete timer;
        }
    }
    // ノードを同期破棄する（生成元 client より先に。直接 delete でシグナル接続も切れる）。
    const QList<QOpcUaNode *> nodes = m_nodes.take(connectionId);
    for (QOpcUaNode *node : nodes) {
        delete node;
    }
}

void OpcUaController::writeVariable(const QString &name, const QVariant &value)
{
    // 書込写像が無い変数（内部変数 / OPC-UA 以外の source）は何もしない（呼ぶ側は気にせず呼べる）。
    const auto it = m_writeItems.constFind(name);
    if (it == m_writeItems.constEnd()) {
        return;
    }
    const WriteItem &witem = it.value();

    QOpcUaClient *client = m_clients.value(witem.connectionId);
    if (!client) {
        qWarning().noquote() << "OpcUaController: writeVariable" << name
                             << "has no client for connection" << witem.connectionId;
        return;
    }
    if (client->state() != QOpcUaClient::Connected) {
        // 未接続なら書けない（接続復帰後の次の操作で書ける）。購読が復帰後に最新値を
        // 持ってくるので致命にはしない（MB-4 と同方針）。
        qWarning().noquote() << "OpcUaController: writeVariable" << name
                             << "skipped (connection" << witem.connectionId << "not connected)";
        return;
    }

    QOpcUaNode *node = client->node(witem.nodeId);
    if (!node) {
        qWarning().noquote() << "OpcUaController: writeVariable" << name
                             << "cannot create node" << witem.nodeId;
        return;
    }
    // 書込専用に作ったノードは write 完了後に破棄する（購読ノードとは別。リーク防止）。
    // ただし完了（attributeWritten）前に stop() が走ると、購読ノードだけ破棄した後に生成元
    // client が先に消え、このノードが client より長生きして未定義動作になる（Codex PR #145
    // [Major]）。そこで m_writeNodes に追跡し、stop() で client より先に同期破棄できるようにする。
    node->setParent(this);
    m_writeNodes.append(node);
    // 追跡からの除去は **実際に破棄された時**（destroyed）に行う。deleteLater 直後にリストから
    // 外すと、DeferredDelete 処理前に stop() が走ったとき stop() の先行削除対象から漏れ、書込ノードが
    // client より長生きして UB が再発する（Codex PR #145 [Major] 2nd）。destroyed で外せば、
    // 通常完了（deleteLater）でも stop() の同期 delete でも確実に回収・除去される。
    QObject::connect(node, &QObject::destroyed, this,
                     [this, node]() { m_writeNodes.removeOne(node); });
    const QString capturedName = name;
    const quint64 generation = m_generation;
    QObject::connect(node, &QOpcUaNode::attributeWritten, this,
                     [node, capturedName, generation, this](QOpcUa::NodeAttribute attr,
                                                            QOpcUa::UaStatusCode status) {
                         if (generation == m_generation
                             && attr == QOpcUa::NodeAttribute::Value
                             && status != QOpcUa::UaStatusCode::Good) {
                             qWarning().noquote() << "OpcUaController: write error for"
                                                  << capturedName << "status" << status;
                         }
                         node->deleteLater(); // 除去は上の destroyed ハンドラが行う。
                     });

    // 値と OPC-UA 型を変数定義の型に合わせて明示変換する。QML から来る数値は QVariant で
    // double 化されがちで、Undefined 型のまま書くとサーバの Int32 ノードと型不一致（Double 拒否）に
    // なる。変数型（int/real/bool/string）に対応する OPC-UA スカラ型へ寄せて書く（MVP はスカラのみ）。
    QVariant typed = value;
    QOpcUa::Types opcType = QOpcUa::Types::Undefined;
    if (witem.variableType == QStringLiteral("int")) {
        typed = value.toInt();
        opcType = QOpcUa::Types::Int32;
    } else if (witem.variableType == QStringLiteral("real")) {
        typed = value.toDouble();
        opcType = QOpcUa::Types::Double;
    } else if (witem.variableType == QStringLiteral("bool")) {
        typed = value.toBool();
        opcType = QOpcUa::Types::Boolean;
    } else { // string ほか
        typed = value.toString();
        opcType = QOpcUa::Types::String;
    }
    // writeAttribute が false なら非同期 write が開始されず attributeWritten が来ない＝
    // deleteLater/destroyed 経由の回収も走らないため、書込ノードが m_writeNodes に溜まり続ける
    // （無効 nodeId / backend 送出失敗で同じ書込を繰り返すと蓄積。Codex PR #145 [Major]）。
    // 失敗時は警告してその場で破棄する（destroyed ハンドラが m_writeNodes から外す）。
    if (!node->writeAttribute(QOpcUa::NodeAttribute::Value, typed, opcType)) {
        qWarning().noquote() << "OpcUaController: writeAttribute dispatch failed for" << name
                             << "nodeId" << witem.nodeId;
        delete node;
    }
}

void OpcUaController::setConnectionState(const QString &id, const QString &state)
{
    if (m_connectionStates.value(id).toString() == state) {
        return; // 重複通知を避ける。
    }
    m_connectionStates.insert(id, state);
    emit connectionStatesChanged();
}

void OpcUaController::scheduleReconnect(const QString &id)
{
    // 既に再接続タイマが回っているなら二重起動しない。
    if (m_reconnectTimers.contains(id)) {
        return;
    }
    if (!m_clients.contains(id)) {
        return;
    }
    auto *timer = new QTimer(this);
    timer->setInterval(kReconnectIntervalMs);
    const quint64 generation = m_generation;
    QObject::connect(timer, &QTimer::timeout, this, [this, id, generation, timer]() {
        // 世代が変わった（configure / stop）なら、このタイマ自身を止めて破棄してから抜ける
        // （stop でも片付くが、無駄な再試行を残さないよう明示的に止める。MB-4 と同型）。
        // hash には同 id の新世代タイマが入っている可能性があるので、自分自身のときだけ外す。
        if (generation != m_generation) {
            if (m_reconnectTimers.value(id) == timer) {
                m_reconnectTimers.remove(id);
            }
            timer->stop();
            timer->deleteLater();
            return;
        }
        QOpcUaClient *client = m_clients.value(id);
        if (!client) {
            return;
        }
        if (client->state() == QOpcUaClient::Connected) {
            // 既に接続済みなら再接続タイマを止めて破棄する。
            if (QTimer *t = m_reconnectTimers.take(id)) {
                t->stop();
                t->deleteLater();
            }
            return;
        }
        if (client->state() == QOpcUaClient::Disconnected) {
            // 未接続ならエンドポイント探索からやり直す（失敗しても次周期で再試行）。
            startDiscovery(id, generation);
        }
    });
    timer->start();
    m_reconnectTimers.insert(id, timer);
}

void OpcUaController::stop()
{
    // 世代を進め、発行済みの非同期コールバックを無効化する。
    ++m_generation;

    // 再接続タイマを確実に止める（世代切替後に旧接続を叩かないように。MB-4 と同型）。
    for (QTimer *timer : std::as_const(m_reconnectTimers)) {
        if (timer) {
            timer->stop();
            delete timer;
        }
    }
    m_reconnectTimers.clear();

    // フォールバック読込タイマを止めて破棄する（ノード破棄前に止めて、停止後の readAttributes を防ぐ）。
    for (const QList<QTimer *> &timers : std::as_const(m_pollTimers)) {
        for (QTimer *timer : timers) {
            if (timer) {
                timer->stop();
                delete timer;
            }
        }
    }
    m_pollTimers.clear();

    // ノードは生成元 QOpcUaClient の存続中だけ有効なので、**クライアントより先に同期破棄**する
    // （`deleteLater` だとアプリ終了時にイベントループ停止後まで処理されず、同じ親〔this〕配下の
    // クライアントが先に消えてノード破棄が未定義動作になり得る＝Codex PR #143 [Major]）。
    // 直接 delete はシグナル接続も切る。stop() はノードのシグナル発火中からは呼ばれない。
    // 購読ノード（接続単位）と書込ノード（完了前に stop した分）の両方を client より先に破棄する
    // （書込ノードを残すと購読ノードだけ消した後 client が先に消えて UB＝Codex PR #145 [Major]）。
    for (const QList<QOpcUaNode *> &nodes : std::as_const(m_nodes)) {
        for (QOpcUaNode *node : nodes) {
            delete node;
        }
    }
    m_nodes.clear();
    // 書込ノードは destroyed ハンドラが m_writeNodes から自分を外すため、**先にリストを退避して
    // クリア**してから delete する（イテレート中の自己除去によるリスト変更を避ける。クリア済みなので
    // 各 destroyed の removeOne は無害な no-op）。
    const QList<QOpcUaNode *> writeNodes = m_writeNodes;
    m_writeNodes.clear();
    for (QOpcUaNode *node : writeNodes) {
        delete node;
    }

    // ノードを片付けた後にクライアントを破棄する（ノードはもう client を参照しない）。
    for (const QPointer<QOpcUaClient> &client : std::as_const(m_clients)) {
        if (client) {
            client->disconnectFromEndpoint();
            delete client;
        }
    }
    m_clients.clear();
    m_endpoints.clear();
    m_itemsByConnection.clear();
    m_writeItems.clear();

    // 接続状態をクリアして QML へ通知する（再 configure 時の stale 表示防止）。
    if (!m_connectionStates.isEmpty()) {
        m_connectionStates.clear();
        emit connectionStatesChanged();
    }
}
