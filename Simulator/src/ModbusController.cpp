#include "ModbusController.h"

#include <QDebug>
#include <QModbusReply>
#include <QModbusTcpClient>
#include <QTimer>
#include <QVariant>

ModbusController::ModbusController(QObject *parent) : QObject(parent) {}

ModbusController::~ModbusController()
{
    stop();
}

QModbusDataUnit::RegisterType ModbusController::registerTypeFromString(const QString &reg)
{
    if (reg == QStringLiteral("coil")) {
        return QModbusDataUnit::Coils;
    }
    if (reg == QStringLiteral("discrete")) {
        return QModbusDataUnit::DiscreteInputs;
    }
    if (reg == QStringLiteral("input")) {
        return QModbusDataUnit::InputRegisters;
    }
    if (reg == QStringLiteral("holding")) {
        return QModbusDataUnit::HoldingRegisters;
    }
    return QModbusDataUnit::Invalid;
}

bool ModbusController::isBooleanRegister(QModbusDataUnit::RegisterType type)
{
    return type == QModbusDataUnit::Coils || type == QModbusDataUnit::DiscreteInputs;
}

bool ModbusController::isWritableRegister(QModbusDataUnit::RegisterType type)
{
    // discrete / input は読取専用、coil / holding のみ書込可能（Modbus 仕様）。
    return type == QModbusDataUnit::Coils || type == QModbusDataUnit::HoldingRegisters;
}

void ModbusController::configure(const QVariantList &connections, const QVariantList &variables)
{
    // 世代を進める（stop() 内でも進むが、明示しておく）。これ以前に発行済みの
    // reply は finished しても下の世代チェックで弾かれる（CodeRabbit PR #121）。
    ++m_generation;
    // 再 configure（プロジェクト読み替え）に備えて一旦全停止。
    stop();

    // 接続を用意する。connection id → client を作って connectDevice()。
    for (const QVariant &cv : connections) {
        const QVariantMap c = cv.toMap();
        const QString id = c.value(QStringLiteral("id")).toString();
        if (id.isEmpty()) {
            continue;
        }
        // 既定 "modbusTcp" のみ対応（他プロトコルは将来）。
        const QString proto = c.value(QStringLiteral("proto"),
                                       QStringLiteral("modbusTcp")).toString();
        if (proto != QStringLiteral("modbusTcp")) {
            qWarning().noquote() << "ModbusController: unsupported proto" << proto
                                 << "for connection" << id << "(skipped)";
            continue;
        }
        const QString host = c.value(QStringLiteral("host")).toString();
        const int port = c.value(QStringLiteral("port"), 502).toInt();
        const int unitId = c.value(QStringLiteral("unitId"), 1).toInt();
        if (host.isEmpty()) {
            qWarning().noquote() << "ModbusController: empty host for connection" << id
                                 << "(skipped)";
            continue;
        }
        // 範囲外（手編集 JSON 等）は毎周期失敗し続けるので登録せず弾く（CodeRabbit PR #121）。
        if (port < 1 || port > 65535) {
            qWarning().noquote() << "ModbusController: invalid port" << port
                                 << "for connection" << id << "(skipped)";
            continue;
        }
        if (unitId < 1 || unitId > 247) {
            qWarning().noquote() << "ModbusController: invalid unitId" << unitId
                                 << "for connection" << id << "(skipped)";
            continue;
        }

        auto *client = new QModbusTcpClient(this);
        client->setConnectionParameter(QModbusDevice::NetworkAddressParameter, host);
        client->setConnectionParameter(QModbusDevice::NetworkPortParameter, port);
        // Phase 7 / MB-4: 接続状態を QML へ反映し、切断 / エラー時は再接続を試みる。
        const quint64 generation = m_generation;
        QObject::connect(client, &QModbusClient::stateChanged, this,
                         [this, id, generation](QModbusDevice::State state) {
                             if (generation != m_generation) {
                                 return; // 旧世代のクライアントは無視。
                             }
                             setConnectionState(id, state);
                             if (state == QModbusDevice::UnconnectedState) {
                                 // 接続が落ちた / 接続失敗で未接続に戻ったら再接続を試みる。
                                 scheduleReconnect(id);
                             }
                         });
        QObject::connect(client, &QModbusClient::errorOccurred, this,
                         [this, id, generation](QModbusDevice::Error error) {
                             if (generation != m_generation) {
                                 return;
                             }
                             if (error != QModbusDevice::NoError) {
                                 qWarning().noquote()
                                     << "ModbusController: connection" << id
                                     << "error" << error;
                                 // 接続エラーは状態を "error" にする（state は別途 stateChanged で更新）。
                                 if (error == QModbusDevice::ConnectionError) {
                                     m_connectionStates.insert(id, QStringLiteral("error"));
                                     emit connectionStatesChanged();
                                 }
                             }
                         });
        // 初期状態を反映（connectDevice 前は disconnected）。
        setConnectionState(id, client->state());
        if (!client->connectDevice()) {
            qWarning().noquote() << "ModbusController: connectDevice() failed for" << id
                                 << client->errorString();
        }
        m_clients.insert(id, client);
        m_unitIds.insert(id, unitId);
    }

    // source を持つ変数をポーリング対象に登録する。
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
        const QModbusDataUnit::RegisterType regType =
            registerTypeFromString(s.value(QStringLiteral("reg")).toString());
        if (connectionId.isEmpty() || regType == QModbusDataUnit::Invalid) {
            qWarning().noquote() << "ModbusController: variable" << name
                                 << "has invalid source (connection/reg)" << "(skipped)";
            continue;
        }
        if (!m_clients.contains(connectionId)) {
            qWarning().noquote() << "ModbusController: variable" << name
                                 << "references unknown connection" << connectionId
                                 << "(skipped)";
            continue;
        }

        const int address = s.value(QStringLiteral("address"), 0).toInt();
        if (address < 0 || address > 65535) {
            qWarning().noquote() << "ModbusController: variable" << name
                                 << "has invalid address" << address << "(skipped)";
            continue;
        }

        PollItem item;
        item.name = name;
        item.connectionId = connectionId;
        item.regType = regType;
        item.address = address;
        item.poll = s.value(QStringLiteral("poll"), 1000).toInt();
        if (item.poll < 1) {
            item.poll = 1000;
        }
        m_items.append(item);

        // Phase 7 / MB-4: 書込可能レジスタ（coil / holding）なら write 表にも登録する。
        // discrete / input は読取専用なので write 表に入れない（writeVariable で no-op）。
        if (isWritableRegister(regType)) {
            WriteItem witem;
            witem.connectionId = connectionId;
            witem.regType = regType;
            witem.address = address;
            m_writeItems.insert(name, witem);
        }
    }

    startPolling();
}

void ModbusController::startPolling()
{
    for (const PollItem &item : std::as_const(m_items)) {
        auto *timer = new QTimer(this);
        timer->setInterval(item.poll);
        const PollItem captured = item;
        QObject::connect(timer, &QTimer::timeout, this, [this, captured]() {
            pollOne(captured);
        });
        timer->start();
        m_timers.append(timer);
        // 初回は周期を待たずに即読みして初期値を素早く反映する。
        pollOne(item);
    }
}

void ModbusController::pollOne(const PollItem &item)
{
    QModbusTcpClient *client = m_clients.value(item.connectionId);
    if (!client) {
        return;
    }
    if (client->state() != QModbusDevice::ConnectedState) {
        // 未接続 / 接続中はこの周期はスキップ（次周期で再試行）。再接続は MB-4。
        return;
    }

    const int unitId = m_unitIds.value(item.connectionId, 1);
    QModbusDataUnit unit(item.regType, item.address, 1);

    auto *reply = client->sendReadRequest(unit, unitId);
    if (!reply) {
        qWarning().noquote() << "ModbusController: sendReadRequest returned null for"
                             << item.name << client->errorString();
        return;
    }
    if (reply->isFinished()) {
        // ブロードキャスト等で即完了したケース（read では稀）。リークを避けて破棄。
        reply->deleteLater();
        return;
    }
    const QString name = item.name;
    const bool boolReg = isBooleanRegister(item.regType);
    const quint64 generation = m_generation;
    QObject::connect(reply, &QModbusReply::finished, this, [this, reply, name, boolReg, generation]() {
        // configure()/stop() 後に finished した旧世代 reply は古い値を流さず捨てる。
        if (generation != m_generation) {
            reply->deleteLater();
            return;
        }
        if (reply->error() == QModbusDevice::NoError) {
            const QModbusDataUnit result = reply->result();
            if (result.valueCount() > 0) {
                const quint16 raw = result.value(0);
                // bool 系（coil/discrete）は 0/1 に正規化、レジスタは生の数値。
                const QVariant value = boolReg ? QVariant(raw != 0)
                                               : QVariant(static_cast<int>(raw));
                emit variableUpdated(name, value);
            }
        } else {
            qWarning().noquote() << "ModbusController: read error for" << name
                                 << reply->errorString();
        }
        reply->deleteLater();
    });
}

void ModbusController::writeVariable(const QString &name, const QVariant &value)
{
    // 書込写像が無い変数（内部変数 / 読取専用レジスタ）は何もしない（呼ぶ側は気にせず呼べる）。
    const auto it = m_writeItems.constFind(name);
    if (it == m_writeItems.constEnd()) {
        return;
    }
    const WriteItem &witem = it.value();

    QModbusTcpClient *client = m_clients.value(witem.connectionId);
    if (!client) {
        qWarning().noquote() << "ModbusController: writeVariable" << name
                             << "has no client for connection" << witem.connectionId;
        return;
    }
    if (client->state() != QModbusDevice::ConnectedState) {
        // 未接続なら書けない（接続復帰後の次の操作で書ける）。読込ポーリングが
        // 復帰後に最新値を持ってくるので致命にはしない。
        qWarning().noquote() << "ModbusController: writeVariable" << name
                             << "skipped (connection" << witem.connectionId << "not connected)";
        return;
    }

    // coil は bool→0/1、holding は int→quint16 に正規化する。
    QModbusDataUnit unit(witem.regType, witem.address, 1);
    if (witem.regType == QModbusDataUnit::Coils) {
        unit.setValue(0, value.toBool() ? 1 : 0);
    } else { // HoldingRegisters
        unit.setValue(0, static_cast<quint16>(value.toInt()));
    }

    const int unitId = m_unitIds.value(witem.connectionId, 1);
    auto *reply = client->sendWriteRequest(unit, unitId);
    if (!reply) {
        qWarning().noquote() << "ModbusController: sendWriteRequest returned null for"
                             << name << client->errorString();
        return;
    }
    if (reply->isFinished()) {
        reply->deleteLater();
        return;
    }
    const quint64 generation = m_generation;
    const QString capturedName = name;
    QObject::connect(reply, &QModbusReply::finished, this,
                     [this, reply, capturedName, generation]() {
                         // configure() / stop() 後に finished した旧世代 reply は無視。
                         if (generation == m_generation
                             && reply->error() != QModbusDevice::NoError) {
                             qWarning().noquote() << "ModbusController: write error for"
                                                  << capturedName << reply->errorString();
                         }
                         reply->deleteLater();
                     });
}

void ModbusController::setConnectionState(const QString &id, QModbusDevice::State state)
{
    QString text;
    switch (state) {
    case QModbusDevice::ConnectingState:
        text = QStringLiteral("connecting");
        break;
    case QModbusDevice::ConnectedState:
        text = QStringLiteral("connected");
        break;
    case QModbusDevice::ClosingState:
    case QModbusDevice::UnconnectedState:
    default:
        text = QStringLiteral("disconnected");
        break;
    }
    if (m_connectionStates.value(id).toString() == text) {
        return; // 重複通知を避ける。
    }
    m_connectionStates.insert(id, text);
    emit connectionStatesChanged();
}

void ModbusController::scheduleReconnect(const QString &id)
{
    // 既に再接続タイマが回っているなら二重起動しない。
    if (m_reconnectTimers.contains(id)) {
        return;
    }
    QModbusTcpClient *client = m_clients.value(id);
    if (!client) {
        return;
    }
    auto *timer = new QTimer(this);
    timer->setInterval(kReconnectIntervalMs);
    const quint64 generation = m_generation;
    QObject::connect(timer, &QTimer::timeout, this, [this, id, generation, timer]() {
        // 世代が変わった（configure / stop）なら、このタイマ自身を止めて破棄してから抜ける
        // （stop でも片付くが、無駄な再試行を残さないよう明示的に止める。CodeRabbit PR #122）。
        // hash には同 id の新世代タイマが入っている可能性があるので、自分自身のときだけ外す。
        if (generation != m_generation) {
            if (m_reconnectTimers.value(id) == timer) {
                m_reconnectTimers.remove(id);
            }
            timer->stop();
            timer->deleteLater();
            return;
        }
        QModbusTcpClient *c = m_clients.value(id);
        if (!c) {
            return;
        }
        if (c->state() == QModbusDevice::ConnectedState) {
            // 既に接続済みなら再接続タイマを止めて破棄する。
            if (QTimer *t = m_reconnectTimers.take(id)) {
                t->stop();
                t->deleteLater();
            }
            return;
        }
        if (c->state() == QModbusDevice::UnconnectedState) {
            c->connectDevice(); // 失敗しても次周期で再試行。
        }
    });
    timer->start();
    m_reconnectTimers.insert(id, timer);
}

void ModbusController::stop()
{
    // 世代を進め、発行済み reply の finished ラムダを無効化する（CodeRabbit PR #121）。
    ++m_generation;
    for (QTimer *timer : std::as_const(m_timers)) {
        timer->stop();
        timer->deleteLater();
    }
    m_timers.clear();
    m_items.clear();
    m_writeItems.clear();

    // Phase 7 / MB-4: 再接続タイマを確実に止める（世代切替後に旧接続を叩かないように）。
    for (QTimer *timer : std::as_const(m_reconnectTimers)) {
        if (timer) {
            timer->stop();
            timer->deleteLater();
        }
    }
    m_reconnectTimers.clear();

    for (const QPointer<QModbusTcpClient> &client : std::as_const(m_clients)) {
        if (client) {
            client->disconnectDevice();
            client->deleteLater();
        }
    }
    m_clients.clear();
    m_unitIds.clear();

    // Phase 7 / MB-4: 接続状態をクリアして QML へ通知する（再 configure 時の stale 表示防止）。
    if (!m_connectionStates.isEmpty()) {
        m_connectionStates.clear();
        emit connectionStatesChanged();
    }
}
