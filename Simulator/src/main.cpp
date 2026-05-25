#include "ProjectLoader.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("hmi_simulator");

    // 起動時に表示する JSON を CLI で指定できるようにする（任意）。
    //   hmi_simulator [--open <path>] [path]
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

    return app.exec();
}
