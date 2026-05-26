#include "ProjectLoader.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDebug>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>

#include <Spix/AnyRpcServer.h>
#include <Spix/QtQmlBot.h>

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
    parser.addOption(e2eOpt);
    parser.addOption(e2ePortOpt);
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

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("projectLoader"),
                                             &projectLoader);
    engine.rootContext()->setContextProperty(QStringLiteral("initialJsonUrl"),
                                             startupUrl);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule("HmiSimulator", "Main");

    // `--e2e` 指定時のみ Spix を起動。通常起動時は AnyRpcServer / QtQmlBot を
    // 一切構築しないため、ネットワークを開かない。
    // 構造は Spix `examples/qtquick/RemoteCtrl/main.cpp` に準拠：
    // QtQmlBot は process 終了まで生存させたいので heap allocate（OS 回収）。
    // AnyRpcServer は static ローカルにして、if スコープを抜けても破棄させない。
    if (parser.isSet(e2eOpt)) {
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
    }

    return app.exec();
}
