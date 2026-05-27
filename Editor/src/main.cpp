#include "ProjectIo.h"

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
    app.setApplicationName("hmi_editor");

    // Task 16 / 19: CLI 引数のセットアップ。
    //   --e2e             : E2E テスト用 Spix エンドポイントを有効化（Task 16）
    //   --e2e-port <port> : Spix のリッスンポート（既定 9876、Simulator=9877）
    //   --open <path>     : 起動時に表示する JSON を自動ロード（Task 19）
    //                       ※ Simulator と同名 (`--open`) で命名を揃える
    // `--e2e` をフラグ、`--e2e-port` を値オプションに分けるのは
    // QCommandLineParser が単一オプションの optional value をサポートしないため。
    QCommandLineParser parser;
    parser.setApplicationDescription("HMI Editor");
    parser.addHelpOption();
    QCommandLineOption e2eOpt(QStringLiteral("e2e"),
                              QStringLiteral("E2E テスト用エンドポイントを有効化する"));
    QCommandLineOption e2ePortOpt(QStringLiteral("e2e-port"),
                                  QStringLiteral("E2E エンドポイントの listen ポート（既定 9876）"),
                                  QStringLiteral("port"),
                                  QStringLiteral("9876"));
    QCommandLineOption openOpt({QStringLiteral("o"), QStringLiteral("open")},
                               QStringLiteral("起動時に読み込むプロジェクト JSON のパス"),
                               QStringLiteral("path"));
    parser.addOption(e2eOpt);
    parser.addOption(e2ePortOpt);
    parser.addOption(openOpt);
    parser.process(app);

    // Task 19: 起動時自動ロード。Simulator/src/main.cpp と同じパターンで、
    // QFileInfo で絶対パスに正規化してから QUrl::fromLocalFile に渡す
    // （QML 側で QUrl のまま FileDialog 相当の API に流し込めるようにする）。
    QUrl startupUrl;
    if (parser.isSet(openOpt)) {
        const QString startupPath = parser.value(openOpt);
        if (!startupPath.isEmpty()) {
            const QFileInfo fi(startupPath);
            startupUrl = QUrl::fromLocalFile(fi.absoluteFilePath());
        }
    }

    QQmlApplicationEngine engine;

    // Task 6: QML から呼ぶ JSON 保存ヘルパー。setContextProperty で `projectIo` として公開。
    ProjectIo projectIo;
    engine.rootContext()->setContextProperty(QStringLiteral("projectIo"), &projectIo);
    // Task 19: QML 側で Component.onCompleted から参照する起動時 JSON URL。
    // 空 URL なら自動ロードは行われない（Main.qml 側で isValid() を判定）。
    engine.rootContext()->setContextProperty(QStringLiteral("initialJsonUrl"),
                                             startupUrl);

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
