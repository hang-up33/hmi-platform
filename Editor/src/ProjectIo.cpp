#include "ProjectIo.h"

#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/WidgetData.h"

#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QVariantMap>

ProjectIo::ProjectIo(QObject *parent) : QObject(parent) {}

bool ProjectIo::save(const QUrl &fileUrl,
                     const QString &projectName,
                     const QString &screenName,
                     const QVariantList &widgets)
{
    using namespace hmi::schema;

    ProjectData proj;
    proj.project = projectName;

    ScreenData screen;
    screen.name = screenName;
    screen.widgets.reserve(widgets.size());

    for (const QVariant &v : widgets) {
        const QVariantMap m = v.toMap();
        WidgetData w;
        w.id = m.value(QStringLiteral("id")).toString();
        w.type = m.value(QStringLiteral("type")).toString();
        w.x = m.value(QStringLiteral("x")).toInt();
        w.y = m.value(QStringLiteral("y")).toInt();
        w.width = m.value(QStringLiteral("width")).toInt();
        w.height = m.value(QStringLiteral("height")).toInt();
        w.text = m.value(QStringLiteral("text")).toString();
        w.tag = m.value(QStringLiteral("tag")).toString();
        screen.widgets.append(w);
    }

    proj.screens.append(screen);

    const QJsonDocument doc(proj.toJson());

    // QML の FileDialog は file:/// 形式の QUrl を返す。toLocalFile で OS パスへ変換する。
    const QString localPath = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    if (localPath.isEmpty()) {
        return false;
    }

    QSaveFile file(localPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    if (file.write(doc.toJson(QJsonDocument::Indented)) < 0) {
        return false;
    }
    return file.commit();
}
