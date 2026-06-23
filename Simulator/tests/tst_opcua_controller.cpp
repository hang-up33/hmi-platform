#include "OpcUaController.h"

#include <QHostAddress>
#include <QOpcUaProvider>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTest>
#include <QVariantList>
#include <QVariantMap>

namespace {
// 「何も listen していない＝到達不能」なポートを動的確保する。空きポートを OS に選ばせて
// 即解放することで、E2E（test_opcua_read.py の既定 14840）など固定ポートとの衝突を避ける
// （`ctest -R opcua -j2` の並列実行で E2E サーバへ偶然つながり spy 前提が崩れるのを防ぐ。
// Codex PR #143 [Minor]）。確保失敗時は 0 を返す（呼び出し側で QSKIP）。
quint16 unusedLoopbackPort()
{
    QTcpServer probe;
    if (!probe.listen(QHostAddress::LocalHost, 0)) {
        return 0;
    }
    const quint16 port = probe.serverPort();
    probe.close();
    return port;
}
} // namespace

// Phase 9 / OP-2: OpcUaController の Signal/Slot ユニットテスト。
//
// Modbus（tst_modbus_controller）は Qt 標準の **in-process QModbusTcpServer** を相手に
// read→variableUpdated まで同一プロセスで検証できたが、**Qt OPC-UA はサーバ機能（QOpcUaServer）を
// この構成（open62541 client backend のみ）では提供しない**ため、実サーバ相手の購読 round-trip は
// E2E（`tests/e2e/test_opcua_read.py`：asyncua ソフトサーバ）に委ねる。
// ここでは実サーバ無しで検証できる粒度に絞る：
//   1. OPC-UA backend plugin（open62541）が利用可能であること（kit / rootfs の同梱確認）。
//   2. OPC-UA でない source / source 無し変数では何も emit しないこと（Modbus と排他・後方互換）。
//   3. 到達不能エンドポイントを configure しても落ちず・誤った値を emit しないこと
//      （非同期コールバックの世代ガード・クリーンアップの健全性）。
//   4. 再 configure / stop が安全に繰り返せること。
class TestOpcUaController : public QObject {
    Q_OBJECT

private slots:
    void backendAvailable();
    void configureWithoutOpcuaSourceEmitsNothing();
    void unreachableEndpointDoesNotCrashOrEmit();
    void reconfigureAndStopAreSafe();
    // OP-4: 接続状態の公開と、書込・再接続の安全性。
    void connectionStateExposedForOpcuaConnection();
    void writeVariableIsSafeWhenUnknownOrDisconnected();
    void stopClearsConnectionStates();
};

void TestOpcUaController::backendAvailable()
{
    // OP-2 は open62541 backend plugin が無いと購読が動かない（plan §依存「バックエンド plugin」）。
    // kit / rootfs に同梱されていることをここで担保する。
    QOpcUaProvider provider;
    const QStringList backends = provider.availableBackends();
    QVERIFY2(!backends.isEmpty(),
             "No OPC-UA backend plugin available (expected open62541). "
             "Qt OPC-UA kit / rootfs is incomplete.");
}

void TestOpcUaController::configureWithoutOpcuaSourceEmitsNothing()
{
    // proto が opcua でない接続・nodeId 無し source・source 無し変数だけなら、OPC-UA としては
    // 何も購読しない＝emit されない（Modbus 接続と同じ list を渡しても排他に動くことの担保）。
    OpcUaController controller;
    QSignalSpy spy(&controller, &OpcUaController::variableUpdated);

    QVariantList connections;
    connections.append(QVariantMap{{"id", "plc1"},
                                   {"proto", "modbusTcp"},
                                   {"host", "127.0.0.1"},
                                   {"port", 1502}});
    QVariantList variables;
    variables.append(QVariantMap{{"name", "internalVar"}, {"type", "int"}, {"initial", "5"}});
    variables.append(QVariantMap{
        {"name", "tankLevel"},
        {"type", "int"},
        {"source", QVariantMap{{"connection", "plc1"},
                               {"reg", "holding"},
                               {"address", 3}}}}); // Modbus source（nodeId 無し）→ OPC-UA は無視。

    controller.configure(connections, variables);

    QTest::qWait(200);
    QCOMPARE(spy.count(), 0);
}

void TestOpcUaController::unreachableEndpointDoesNotCrashOrEmit()
{
    // 到達不能なエンドポイントへ opcua 接続を試みる。接続は確立せず購読も始まらないが、
    // 非同期コールバック（endpointsRequestFinished / stateChanged）の世代ガードと
    // クリーンアップが健全なら、落ちず・誤った値も emit しない。
    const quint16 deadPort = unusedLoopbackPort();
    if (deadPort == 0) {
        QSKIP("Could not reserve an unused loopback port");
    }
    const QString deadEndpoint =
        QStringLiteral("opc.tcp://127.0.0.1:%1").arg(deadPort);

    OpcUaController controller;
    QSignalSpy spy(&controller, &OpcUaController::variableUpdated);

    QVariantList connections;
    connections.append(QVariantMap{
        {"id", "srv1"},
        {"proto", "opcua"},
        // 動的確保した未使用ポート（requestEndpoints は失敗する）。E2E 固定ポートと衝突しない。
        {"endpoint", deadEndpoint}});
    QVariantList variables;
    variables.append(QVariantMap{
        {"name", "temp"},
        {"type", "real"},
        {"source", QVariantMap{{"connection", "srv1"},
                               {"nodeId", "ns=2;s=Temp"},
                               {"poll", 100}}}});

    controller.configure(connections, variables);

    // 接続失敗の非同期処理が一巡するのを待つ。emit は起きないはず。
    QTest::qWait(1500);
    QCOMPARE(spy.count(), 0);

    // stop しても落ちない。
    controller.stop();
    QCOMPARE(spy.count(), 0);
}

void TestOpcUaController::reconfigureAndStopAreSafe()
{
    // 同じ controller を繰り返し configure / stop しても安全（世代カウンタで旧接続が無効化される）。
    const quint16 deadPort = unusedLoopbackPort();
    if (deadPort == 0) {
        QSKIP("Could not reserve an unused loopback port");
    }
    const QString deadEndpoint =
        QStringLiteral("opc.tcp://127.0.0.1:%1").arg(deadPort);

    OpcUaController controller;

    QVariantList connections;
    connections.append(QVariantMap{
        {"id", "srv1"}, {"proto", "opcua"}, {"endpoint", deadEndpoint}});
    QVariantList variables;
    variables.append(QVariantMap{
        {"name", "temp"},
        {"type", "real"},
        {"source", QVariantMap{{"connection", "srv1"}, {"nodeId", "ns=2;s=Temp"}}}});

    controller.configure(connections, variables);
    QTest::qWait(100);
    controller.configure(connections, variables); // 再構成（内部で stop される）。
    QTest::qWait(100);
    controller.stop();
    controller.stop(); // 二重 stop も安全。

    QVERIFY(true); // ここまで到達＝クラッシュしていない。
}

void TestOpcUaController::connectionStateExposedForOpcuaConnection()
{
    // OP-4: opcua 接続を configure すると、接続 id が connectionStates に現れる
    //（discovery 開始で "connecting"、到達不能なので最終的に "disconnected"/"error"）。
    // 専用の状態表示 Widget は作らず、QML が読む Q_PROPERTY を最小担保する。
    const quint16 deadPort = unusedLoopbackPort();
    if (deadPort == 0) {
        QSKIP("Could not reserve an unused loopback port");
    }
    const QString deadEndpoint =
        QStringLiteral("opc.tcp://127.0.0.1:%1").arg(deadPort);

    OpcUaController controller;
    QSignalSpy stateSpy(&controller, &OpcUaController::connectionStatesChanged);

    QVariantList connections;
    connections.append(QVariantMap{
        {"id", "srv1"}, {"proto", "opcua"}, {"endpoint", deadEndpoint}});
    QVariantList variables;
    variables.append(QVariantMap{
        {"name", "temp"},
        {"type", "real"},
        {"source", QVariantMap{{"connection", "srv1"}, {"nodeId", "ns=2;s=Temp"}}}});

    controller.configure(connections, variables);
    // discovery 開始で connecting 状態へ → connectionStatesChanged が出る。
    QVERIFY2(stateSpy.count() > 0, "configure did not emit connectionStatesChanged");

    const QVariantMap states = controller.connectionStates();
    QVERIFY2(states.contains(QStringLiteral("srv1")),
             "connectionStates missing the configured opcua connection id");

    // 到達不能なので接続失敗の非同期処理が一巡するのを待ち、最終的に未接続系の状態に落ち着く。
    QTest::qWait(1500);
    const QString finalState = controller.connectionStates()
                                   .value(QStringLiteral("srv1"))
                                   .toString();
    QVERIFY2(finalState == QStringLiteral("disconnected")
                 || finalState == QStringLiteral("error")
                 || finalState == QStringLiteral("connecting"),
             qPrintable(QStringLiteral("unexpected connection state: %1").arg(finalState)));

    controller.stop();
}

void TestOpcUaController::writeVariableIsSafeWhenUnknownOrDisconnected()
{
    // OP-4: 書込写像が無い変数（内部変数 / OPC-UA 以外の source）への writeVariable は no-op で
    // 落ちない。OPC-UA source を持つが未接続の変数への writeVariable も落ちない（接続前に書けない
    // だけで致命にしない）。emit は起きない。
    const quint16 deadPort = unusedLoopbackPort();
    if (deadPort == 0) {
        QSKIP("Could not reserve an unused loopback port");
    }
    const QString deadEndpoint =
        QStringLiteral("opc.tcp://127.0.0.1:%1").arg(deadPort);

    OpcUaController controller;
    QSignalSpy spy(&controller, &OpcUaController::variableUpdated);

    // configure 前：未知変数への書込は安全。
    controller.writeVariable(QStringLiteral("nope"), 1);

    QVariantList connections;
    connections.append(QVariantMap{
        {"id", "srv1"}, {"proto", "opcua"}, {"endpoint", deadEndpoint}});
    QVariantList variables;
    variables.append(QVariantMap{
        {"name", "setpoint"},
        {"type", "int"},
        {"source", QVariantMap{{"connection", "srv1"}, {"nodeId", "ns=2;s=Setpoint"}}}});
    controller.configure(connections, variables);

    // OPC-UA source を持つが（到達不能で）未接続の変数への書込：no-op で落ちない。
    controller.writeVariable(QStringLiteral("setpoint"), 4242);
    // 書込写像が無い変数への書込も no-op。
    controller.writeVariable(QStringLiteral("internalOnly"), 7);

    QTest::qWait(300);
    QCOMPARE(spy.count(), 0); // 書込は読込シグナルを発火しない。

    controller.stop();
    // stop 後の書込も安全（写像クリア済み）。
    controller.writeVariable(QStringLiteral("setpoint"), 1);
    QVERIFY(true);
}

void TestOpcUaController::stopClearsConnectionStates()
{
    // OP-4: stop() で接続状態がクリアされ、再 configure 時の stale 表示を防ぐ。
    const quint16 deadPort = unusedLoopbackPort();
    if (deadPort == 0) {
        QSKIP("Could not reserve an unused loopback port");
    }
    const QString deadEndpoint =
        QStringLiteral("opc.tcp://127.0.0.1:%1").arg(deadPort);

    OpcUaController controller;
    QVariantList connections;
    connections.append(QVariantMap{
        {"id", "srv1"}, {"proto", "opcua"}, {"endpoint", deadEndpoint}});
    QVariantList variables;
    variables.append(QVariantMap{
        {"name", "temp"},
        {"type", "real"},
        {"source", QVariantMap{{"connection", "srv1"}, {"nodeId", "ns=2;s=Temp"}}}});

    controller.configure(connections, variables);
    QVERIFY(!controller.connectionStates().isEmpty());

    controller.stop();
    QVERIFY2(controller.connectionStates().isEmpty(),
             "stop() did not clear connectionStates");
}

QTEST_MAIN(TestOpcUaController)
#include "tst_opcua_controller.moc"
