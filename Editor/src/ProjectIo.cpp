#include "ProjectIo.h"

#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/WidgetData.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QSaveFile>
#include <QVariantList>
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

QVariantMap ProjectIo::load(const QUrl &fileUrl)
{
    using namespace hmi::schema;

    QVariantMap result;
    result.insert(QStringLiteral("ok"), false);
    result.insert(QStringLiteral("widgets"), QVariantList{});

    // FileDialog から渡される file:/// 形式の QUrl を OS パスへ変換する（Task 6 の save と同方針）。
    const QString localPath = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    if (localPath.isEmpty()) {
        return result;
    }

    QFile file(localPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return result;
    }
    const QByteArray data = file.readAll();
    file.close();

    QJsonParseError parseErr{};
    const QJsonDocument doc = QJsonDocument::fromJson(data, &parseErr);
    if (parseErr.error != QJsonParseError::NoError || !doc.isObject()) {
        return result;
    }

    // JSON 構造の妥当性検証は Shared/Schema を唯一の真実とする方針に従い、
    // ProjectData::isValidJson（再帰的に Screen / Widget まで検査）に委ねる。
    // fromJson はキー欠落時に既定値で埋める緩い設計のため、これを通さないと
    // `{}` や別形式の JSON でも成功扱いになってしまう。
    const QJsonObject root = doc.object();
    if (!ProjectData::isValidJson(root)) {
        return result;
    }

    const ProjectData proj = ProjectData::fromJson(root);

    // isValidJson が screens 配列に最低 1 件含まれていることを保証している。
    // MVP では先頭スクリーンのみを編集対象とする（save 側も "Main" 単一スクリーン構成）。
    const ScreenData screen = proj.screens.first();

    QVariantList widgetsVar;
    widgetsVar.reserve(screen.widgets.size());
    for (const WidgetData &w : screen.widgets) {
        QVariantMap m;
        m.insert(QStringLiteral("id"), w.id);
        m.insert(QStringLiteral("type"), w.type);
        m.insert(QStringLiteral("x"), w.x);
        m.insert(QStringLiteral("y"), w.y);
        m.insert(QStringLiteral("width"), w.width);
        m.insert(QStringLiteral("height"), w.height);
        m.insert(QStringLiteral("text"), w.text);
        m.insert(QStringLiteral("tag"), w.tag);
        widgetsVar.append(m);
    }

    result.insert(QStringLiteral("ok"), true);
    result.insert(QStringLiteral("project"), proj.project);
    result.insert(QStringLiteral("screen"), screen.name);
    result.insert(QStringLiteral("widgets"), widgetsVar);
    return result;
}
