#include "ModbusController.h"

#include <QModbusDataUnit>
#include <QModbusDataUnitMap>
#include <QModbusTcpServer>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTest>
#include <QVariantList>
#include <QVariantMap>

// Phase 7 / MB-2: ModbusController の Signal/Slot ユニットテスト。
// 実 PLC 無しで検証できる粒度にする：
//   1. reg 文字列 → RegisterType / bool 系判定（純関数）。
//   2. 接続定義 + source 付き変数を configure → variableUpdated が期待値で emit される
//      ことを **同一プロセス内の QModbusTcpServer**（Qt 標準のソフトスレーブ）相手に検証。
//      pymodbus / ネットワーク到達性に依存せず CI / offscreen でも安定して回る。
class TestModbusController : public QObject {
    Q_OBJECT

private slots:
    void registerTypeMapping();
    void booleanRegisterClassification();
    void configureWithoutSourceEmitsNothing();
    void readHoldingRegisterEmitsValue();
    void readCoilEmitsBool();

private:
    // 任意レジスタ値を載せた in-process Modbus TCP スレーブを起動し、listen ポートを返す。
    // 失敗時は 0 を返す（呼び出し側で QSKIP）。
    quint16 startSlave(QModbusTcpServer &server, int unitId,
                       QModbusDataUnit::RegisterType type, int address, quint16 value);
};

void TestModbusController::registerTypeMapping()
{
    QCOMPARE(ModbusController::registerTypeFromString("coil"), QModbusDataUnit::Coils);
    QCOMPARE(ModbusController::registerTypeFromString("discrete"),
             QModbusDataUnit::DiscreteInputs);
    QCOMPARE(ModbusController::registerTypeFromString("input"),
             QModbusDataUnit::InputRegisters);
    QCOMPARE(ModbusController::registerTypeFromString("holding"),
             QModbusDataUnit::HoldingRegisters);
    // 不正 / 空は Invalid。
    QCOMPARE(ModbusController::registerTypeFromString("bogus"), QModbusDataUnit::Invalid);
    QCOMPARE(ModbusController::registerTypeFromString(""), QModbusDataUnit::Invalid);
}

void TestModbusController::booleanRegisterClassification()
{
    QVERIFY(ModbusController::isBooleanRegister(QModbusDataUnit::Coils));
    QVERIFY(ModbusController::isBooleanRegister(QModbusDataUnit::DiscreteInputs));
    QVERIFY(!ModbusController::isBooleanRegister(QModbusDataUnit::InputRegisters));
    QVERIFY(!ModbusController::isBooleanRegister(QModbusDataUnit::HoldingRegisters));
    QVERIFY(!ModbusController::isBooleanRegister(QModbusDataUnit::Invalid));
}

void TestModbusController::configureWithoutSourceEmitsNothing()
{
    // source を持たない変数（内部変数）だけのプロジェクトでは何も読まない＝emit されない。
    ModbusController controller;
    QSignalSpy spy(&controller, &ModbusController::variableUpdated);

    QVariantList connections;
    QVariantList variables;
    variables.append(QVariantMap{{"name", "internalVar"}, {"type", "int"}, {"initial", "5"}});

    controller.configure(connections, variables);

    // 周期到来を少し待っても何も来ないこと（source 無し＝後方互換）。
    QTest::qWait(150);
    QCOMPARE(spy.count(), 0);
}

quint16 TestModbusController::startSlave(QModbusTcpServer &server, int unitId,
                                         QModbusDataUnit::RegisterType type, int address,
                                         quint16 value)
{
    QModbusDataUnitMap reg;
    // address+1 個ぶん確保し、対象アドレスに value を載せる。
    reg.insert(type, {type, 0, static_cast<quint16>(address + 1)});
    if (!server.setMap(reg)) {
        return 0;
    }
    server.setServerAddress(unitId);
    server.setData(type, static_cast<quint16>(address), value);

    // 空きポートを OS に選ばせる：先に QTcpServer で空きを取り、即解放してから再利用する
    // （Qt の QModbusTcpServer はポートを設定 → listen する API のため）。
    quint16 port = 0;
    {
        QTcpServer probe;
        if (!probe.listen(QHostAddress::LocalHost, 0)) {
            return 0;
        }
        port = probe.serverPort();
    }
    server.setConnectionParameter(QModbusDevice::NetworkAddressParameter,
                                  QStringLiteral("127.0.0.1"));
    server.setConnectionParameter(QModbusDevice::NetworkPortParameter, port);
    if (!server.connectDevice()) {
        return 0;
    }
    return port;
}

void TestModbusController::readHoldingRegisterEmitsValue()
{
    QModbusTcpServer server;
    const int unitId = 1;
    const quint16 port = startSlave(server, unitId, QModbusDataUnit::HoldingRegisters,
                                    /*address*/ 3, /*value*/ 1234);
    if (port == 0) {
        QSKIP("Could not start in-process Modbus TCP slave");
    }

    ModbusController controller;
    QSignalSpy spy(&controller, &ModbusController::variableUpdated);

    QVariantList connections;
    connections.append(QVariantMap{{"id", "plc1"},
                                   {"proto", "modbusTcp"},
                                   {"host", "127.0.0.1"},
                                   {"port", static_cast<int>(port)},
                                   {"unitId", unitId}});
    QVariantList variables;
    variables.append(QVariantMap{
        {"name", "tankLevel"},
        {"type", "int"},
        {"source", QVariantMap{{"connection", "plc1"},
                               {"reg", "holding"},
                               {"address", 3},
                               {"poll", 50}}}});

    controller.configure(connections, variables);

    // 接続確立 → 初回 read → finished まで待つ（非同期）。
    QVERIFY(spy.wait(5000));
    QList<QVariant> args = spy.takeFirst();
    QCOMPARE(args.at(0).toString(), QStringLiteral("tankLevel"));
    QCOMPARE(args.at(1).toInt(), 1234);
}

void TestModbusController::readCoilEmitsBool()
{
    QModbusTcpServer server;
    const int unitId = 1;
    const quint16 port = startSlave(server, unitId, QModbusDataUnit::Coils,
                                    /*address*/ 0, /*value*/ 1);
    if (port == 0) {
        QSKIP("Could not start in-process Modbus TCP slave");
    }

    ModbusController controller;
    QSignalSpy spy(&controller, &ModbusController::variableUpdated);

    QVariantList connections;
    connections.append(QVariantMap{{"id", "plc1"},
                                   {"host", "127.0.0.1"},
                                   {"port", static_cast<int>(port)},
                                   {"unitId", unitId}});
    QVariantList variables;
    variables.append(QVariantMap{
        {"name", "running"},
        {"type", "bool"},
        {"source", QVariantMap{{"connection", "plc1"},
                               {"reg", "coil"},
                               {"address", 0},
                               {"poll", 50}}}});

    controller.configure(connections, variables);

    QVERIFY(spy.wait(5000));
    QList<QVariant> args = spy.takeFirst();
    QCOMPARE(args.at(0).toString(), QStringLiteral("running"));
    // coil は bool に正規化される（0/1 ではなく true/false）。
    QCOMPARE(args.at(1).typeId(), QMetaType::Bool);
    QCOMPARE(args.at(1).toBool(), true);
}

QTEST_MAIN(TestModbusController)
#include "tst_modbus_controller.moc"
