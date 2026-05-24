#include "ProjectIo.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

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

    return app.exec();
}
