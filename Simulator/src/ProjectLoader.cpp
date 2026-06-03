#include "ProjectLoader.h"

#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/WidgetData.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QVariantList>
#include <QVariantMap>

ProjectLoader::ProjectLoader(QObject *parent) : QObject(parent) {}

QVariantMap ProjectLoader::load(const QUrl &fileUrl)
{
    using namespace hmi::schema;

    QVariantMap result;
    result.insert(QStringLiteral("ok"), false);
    result.insert(QStringLiteral("widgets"), QVariantList{});

    // QML の FileDialog は file:/// 形式の QUrl を返す。toLocalFile で OS パスへ変換する。
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
    // ProjectData::isValidJson に委ねる（Task 7 で導入した検証 API を Simulator
    // 側でも同じく呼ぶ）。
    const QJsonObject root = doc.object();
    if (!ProjectData::isValidJson(root)) {
        return result;
    }

    const ProjectData proj = ProjectData::fromJson(root);

    // isValidJson が screens 配列に最低 1 件含まれていることを保証している。
    // MVP では先頭スクリーンのみを表示対象とする。
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
        // Task 28: スタイル属性も QML delegate へ届ける（Editor の ProjectIo.load と同形）。
        // Simulator / Runtime は読み取り専用だが、描画に新スタイルを渡す口は必要。
        m.insert(QStringLiteral("backgroundColor"), w.backgroundColor);
        m.insert(QStringLiteral("textColor"), w.textColor);
        m.insert(QStringLiteral("fontSize"), w.fontSize);
        widgetsVar.append(m);
    }

    result.insert(QStringLiteral("ok"), true);
    result.insert(QStringLiteral("project"), proj.project);
    result.insert(QStringLiteral("screen"), screen.name);
    result.insert(QStringLiteral("widgets"), widgetsVar);
    return result;
}
