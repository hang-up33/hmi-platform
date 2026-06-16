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

void ModbusController::configure(const QVariantList &connections, const QVariantList &variables)
{
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

        auto *client = new QModbusTcpClient(this);
        client->setConnectionParameter(QModbusDevice::NetworkAddressParameter, host);
        client->setConnectionParameter(QModbusDevice::NetworkPortParameter, port);
        // 接続失敗は致命にせず警告のみ（再接続の作り込みは MB-4）。
        QObject::connect(client, &QModbusClient::errorOccurred, this,
                         [id](QModbusDevice::Error error) {
                             if (error != QModbusDevice::NoError) {
                                 qWarning().noquote()
                                     << "ModbusController: connection" << id
                                     << "error" << error;
                             }
                         });
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

        PollItem item;
        item.name = name;
        item.connectionId = connectionId;
        item.regType = regType;
        item.address = s.value(QStringLiteral("address"), 0).toInt();
        item.poll = s.value(QStringLiteral("poll"), 1000).toInt();
        if (item.poll < 1) {
            item.poll = 1000;
        }
        m_items.append(item);
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
    QObject::connect(reply, &QModbusReply::finished, this, [this, reply, name, boolReg]() {
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

void ModbusController::stop()
{
    for (QTimer *timer : std::as_const(m_timers)) {
        timer->stop();
        timer->deleteLater();
    }
    m_timers.clear();
    m_items.clear();

    for (const QPointer<QModbusTcpClient> &client : std::as_const(m_clients)) {
        if (client) {
            client->disconnectDevice();
            client->deleteLater();
        }
    }
    m_clients.clear();
    m_unitIds.clear();
}
