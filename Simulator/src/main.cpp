#include "ModbusController.h"
#include "ProjectLoader.h"
#include "ScreenshotGrabber.h"

// Phase 9 / OP-2: Qt OPC-UA が無い環境（Web/CI＝qtopcua 非同梱）では HMI_HAS_OPCUA が
// 未定義になり、OPC-UA 機能を除いてビルドする（Main.qml は opcuaController 不在を許容）。
#ifdef HMI_HAS_OPCUA
#include "OpcUaController.h"
#endif

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDebug>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>

// HMI_HAS_SPIX は CMake から `target_compile_definitions` で渡される。
// Windows MinGW など Spix を有効化できないビルドでは未定義になり、
// `--e2e` 指定時に明確なエラーで終了する（黙ってフラグを無視しない）。
#ifdef HMI_HAS_SPIX
#include <Spix/AnyRpcServer.h>
#include <Spix/QtQmlBot.h>
#endif

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("hmi_simulator");

    // 起動時に表示する JSON を CLI で指定できるようにする（任意）。
    //   hmi_simulator [--open <path>] [--e2e] [--e2e-port <port>] [path]
    // 位置引数として渡すこともできる（FileDialog で後から開くことも可）。
    QCommandLineParser parser;
    parser.setApplicationDescription("HMI Simulator (read-only)");
    parser.addHelpOption();
    QCommandLineOption openOpt({"o", "open"},
                               "Path to project JSON to load on startup.",
                               "path");
    parser.addOption(openOpt);
    parser.addPositionalArgument("path",
                                 "Optional project JSON path to load on startup.");
    // Task 16: E2E テスト用 Spix エンドポイント。Editor (9876) との同時起動時に
    // ポート競合させないため、Simulator は既定ポート 9877 を取る。
    QCommandLineOption e2eOpt(QStringLiteral("e2e"),
                              QStringLiteral("E2E テスト用エンドポイントを有効化する"));
    QCommandLineOption e2ePortOpt(QStringLiteral("e2e-port"),
                                  QStringLiteral("E2E エンドポイントの listen ポート（既定 9877）"),
                                  QStringLiteral("port"),
                                  QStringLiteral("9877"));
    // ヘッドレス動作証跡スクショ（Claude Code on the web 用）。
    //   --screenshot <path>        : 起動直後のウィンドウを PNG 保存して終了
    //   --screenshot-delay <ms>    : 撮影前の待機ミリ秒（既定 700）
    // QT_QPA_PLATFORM=offscreen と組み合わせてウィンドウシステム無しで撮る。
    // Runtime（Simulator ソース共有）の PC ビルドでも同じフラグが効く。
    QCommandLineOption screenshotOpt(
        QStringLiteral("screenshot"),
        QStringLiteral("起動直後のウィンドウを指定パスに PNG 保存して終了する（ヘッドレス証跡用）"),
        QStringLiteral("path"));
    QCommandLineOption screenshotDelayOpt(
        QStringLiteral("screenshot-delay"),
        QStringLiteral("スクショ撮影前の待機ミリ秒（既定 700）"),
        QStringLiteral("ms"),
        QStringLiteral("700"));
    parser.addOption(e2eOpt);
    parser.addOption(e2ePortOpt);
    parser.addOption(screenshotOpt);
    parser.addOption(screenshotDelayOpt);
    parser.process(app);

    QString startupPath = parser.value(openOpt);
    if (startupPath.isEmpty() && !parser.positionalArguments().isEmpty()) {
        startupPath = parser.positionalArguments().constFirst();
    }
    QUrl startupUrl;
    if (!startupPath.isEmpty()) {
        const QFileInfo fi(startupPath);
        startupUrl = QUrl::fromLocalFile(fi.absoluteFilePath());
    }

    // Task 8: QML から呼ぶ JSON 読込ヘルパー。
    // `setContextProperty` で渡した QObject* の所有権は QQmlContext が持たないため、
    // engine よりも先に破棄されると終了時に QML 側が無効ポインタを参照するリスクが
    // ある。C++ の destruction order は LIFO なので、`projectLoader` を `engine` より
    // **前に** 宣言することで `engine` が先に破棄されることを保証する。
    ProjectLoader projectLoader;

    // Phase 7 / MB-2: Modbus TCP マスタ。projectLoader と同じく engine より前に宣言して
    // engine が先に破棄されることを保証する（LIFO）。QML から configure/stop を呼び、
    // variableUpdated シグナルを VariableStore.setValue へ接続する（Main.qml）。
    ModbusController modbusController;

    // Phase 9 / OP-2: OPC-UA クライアント。Modbus と同じく engine より前に宣言（LIFO で
    // engine が先に破棄されることを保証）。QML から configure/stop を呼び、variableUpdated を
    // VariableStore.setValue へ接続する（Main.qml）。Modbus と同じ connections/variables を
    // 渡してよく、proto=="opcua" の接続だけを OpcUaController が拾う。
#ifdef HMI_HAS_OPCUA
    OpcUaController opcuaController;
#endif

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("projectLoader"),
                                             &projectLoader);
    engine.rootContext()->setContextProperty(QStringLiteral("modbusController"),
                                             &modbusController);
#ifdef HMI_HAS_OPCUA
    engine.rootContext()->setContextProperty(QStringLiteral("opcuaController"),
                                             &opcuaController);
#endif
    engine.rootContext()->setContextProperty(QStringLiteral("initialJsonUrl"),
                                             startupUrl);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    // `--screenshot` 指定時のみ撮影フックを仕込む（loadFromModule の前）。
    // 通常起動には影響しない。
    if (parser.isSet(screenshotOpt)) {
        bool delayOk = false;
        int delayMs = parser.value(screenshotDelayOpt).toInt(&delayOk);
        if (!delayOk || delayMs < 0) {
            delayMs = 700;
        }
        installScreenshotGrabber(engine, parser.value(screenshotOpt), delayMs);
    }

    engine.loadFromModule("HmiSimulator", "Main");

    // `--e2e` 指定時のみ Spix を起動。通常起動時は AnyRpcServer / QtQmlBot を
    // 一切構築しないため、ネットワークを開かない。
    // 構造は Spix `examples/qtquick/RemoteCtrl/main.cpp` に準拠：
    // QtQmlBot は process 終了まで生存させたいので heap allocate（OS 回収）。
    // AnyRpcServer は static ローカルにして、if スコープを抜けても破棄させない。
    if (parser.isSet(e2eOpt)) {
#ifdef HMI_HAS_SPIX
        // `toUShort` は変換失敗時 0 を返す。0 のままサーバを起動すると AnyRPC が
        // OS 任せのエフェメラルポートを取りに行き、テスト側が接続先を見失う。
        // 不正値は明示的に弾く（Codex Task 16 P2 指摘）。
        bool ok = false;
        const quint16 port = parser.value(e2ePortOpt).toUShort(&ok);
        if (!ok || port == 0) {
            qCritical().noquote()
                << "Invalid --e2e-port value:" << parser.value(e2ePortOpt);
            return 1;
        }
        static spix::AnyRpcServer server(port);
        auto *bot = new spix::QtQmlBot();
        bot->runTestServer(server);
#else
        qCritical().noquote()
            << "This build does not include Spix (E2E support is disabled, "
               "rebuild with -DHMI_ENABLE_E2E=ON to enable).";
        return 1;
#endif
    }

    return app.exec();
}
