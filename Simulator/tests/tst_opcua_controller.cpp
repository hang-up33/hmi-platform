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

QTEST_MAIN(TestOpcUaController)
#include "tst_opcua_controller.moc"
