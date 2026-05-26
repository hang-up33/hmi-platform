#include "ProjectIo.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include <Spix/AnyRpcServer.h>
#include <Spix/QtQmlBot.h>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("hmi_editor");

    // Task 16: E2E テスト用 Spix エンドポイントの起動制御。
    // `--e2e` フラグと `--e2e-port <port>` 値オプションを分けて受ける
    // （QCommandLineParser は optional value を持つ単一オプションをサポート
    // しないため）。既定ポートは Editor=9876、Simulator=9877 にし、両方を
    // 同時起動する E2E シナリオでもポート競合を起こさないようにする。
    QCommandLineParser parser;
    parser.setApplicationDescription("HMI Editor");
    parser.addHelpOption();
    QCommandLineOption e2eOpt(QStringLiteral("e2e"),
                              QStringLiteral("E2E テスト用エンドポイントを有効化する"));
    QCommandLineOption e2ePortOpt(QStringLiteral("e2e-port"),
                                  QStringLiteral("E2E エンドポイントの listen ポート（既定 9876）"),
                                  QStringLiteral("port"),
                                  QStringLiteral("9876"));
    parser.addOption(e2eOpt);
    parser.addOption(e2ePortOpt);
    parser.process(app);

    QQmlApplicationEngine engine;

    // Task 6: QML から呼ぶ JSON 保存ヘルパー。setContextProperty で `projectIo` として公開。
    ProjectIo projectIo;
    engine.rootContext()->setContextProperty(QStringLiteral("projectIo"), &projectIo);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule("HmiEditor", "Main");

    // `--e2e` 指定時のみ Spix を起動。通常起動時は AnyRpcServer / QtQmlBot を
    // 一切構築しないため、ネットワークを開かない。
    // 構造は Spix `examples/qtquick/RemoteCtrl/main.cpp` に準拠：
    // QtQmlBot は process 終了まで生存させたいので heap allocate（OS 回収）。
    // AnyRpcServer は static ローカルにして、if スコープを抜けても破棄させない。
    if (parser.isSet(e2eOpt)) {
        const quint16 port = parser.value(e2ePortOpt).toUShort();
        static spix::AnyRpcServer server(port);
        auto *bot = new spix::QtQmlBot();
        bot->runTestServer(server);
    }

    return app.exec();
}
