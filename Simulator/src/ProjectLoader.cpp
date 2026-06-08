#include "ProjectLoader.h"

#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/WidgetData.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QVariantList>
#include <QVariantMap>

#include "hmi/schema/ActionData.h"
#include "hmi/schema/BindingData.h"
#include "hmi/schema/VariableData.h"

namespace {
using namespace hmi::schema;

// Task 39: Schema 型 → QVariantList of QVariantMap（QML 描画 / 実行へ渡す。読み取り専用なので
// load 方向のみ。Editor の ProjectIo と同形だが、規約どおり Editor/Simulator は独立保持）。
QVariantList actionsToVariant(const QList<ActionData> &actions)
{
    QVariantList result;
    for (const ActionData &a : actions) {
        QVariantMap m;
        m.insert(QStringLiteral("trigger"), a.trigger);
        m.insert(QStringLiteral("op"), a.op);
        m.insert(QStringLiteral("target"), a.target);
        m.insert(QStringLiteral("value"), a.value);
        result.append(m);
    }
    return result;
}

QVariantList bindingsToVariant(const QList<BindingData> &bindings)
{
    QVariantList result;
    for (const BindingData &b : bindings) {
        QVariantMap m;
        m.insert(QStringLiteral("property"), b.property);
        m.insert(QStringLiteral("variable"), b.variable);
        result.append(m);
    }
    return result;
}

QVariantList variablesToVariant(const QList<VariableData> &variables)
{
    QVariantList result;
    for (const VariableData &var : variables) {
        QVariantMap m;
        m.insert(QStringLiteral("name"), var.name);
        m.insert(QStringLiteral("type"), var.type);
        m.insert(QStringLiteral("initial"), var.initial);
        result.append(m);
    }
    return result;
}

} // namespace

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
        // Task 31: ボーダー＋角丸も QML delegate へ届ける（Editor の ProjectIo.load と同形）。
        // Simulator / Runtime は読み取り専用だが描画に新スタイルを渡す口は必要。
        // -1 / 空は HmiButton 側で既定外観にフォールバックされる。
        m.insert(QStringLiteral("borderColor"), w.borderColor);
        m.insert(QStringLiteral("borderWidth"), w.borderWidth);
        m.insert(QStringLiteral("radius"), w.radius);
        // Task 33: フォント詳細も QML delegate へ届ける（Editor の ProjectIo.load と同形）。
        // Simulator / Runtime は読み取り専用だが描画に新スタイルを渡す口は必要。
        m.insert(QStringLiteral("fontBold"), w.fontBold);
        m.insert(QStringLiteral("fontItalic"), w.fontItalic);
        m.insert(QStringLiteral("fontFamily"), w.fontFamily);
        // Task 34: 配置 + opacity も QML delegate へ届ける（Editor の ProjectIo.load と同形）。
        // Simulator / Runtime は読み取り専用だが描画に新スタイルを渡す口は必要。
        // 空 / -1 は HmiButton 側で既定（中央寄せ・不透明度 1.0）にフォールバックされる。
        m.insert(QStringLiteral("hAlign"), w.hAlign);
        m.insert(QStringLiteral("vAlign"), w.vAlign);
        m.insert(QStringLiteral("opacity"), w.opacity);
        // Task 39: アクション / バインディングも QML へ届ける（T41 で実行 / 追従に使う）。
        m.insert(QStringLiteral("actions"), actionsToVariant(w.actions));
        m.insert(QStringLiteral("bindings"), bindingsToVariant(w.bindings));
        widgetsVar.append(m);
    }

    result.insert(QStringLiteral("ok"), true);
    result.insert(QStringLiteral("project"), proj.project);
    result.insert(QStringLiteral("screen"), screen.name);
    result.insert(QStringLiteral("widgets"), widgetsVar);
    // Task 39: 変数定義も QML へ届ける（T41 で実行ストアの初期化に使う）。
    result.insert(QStringLiteral("variables"), variablesToVariant(proj.variables));
    return result;
}
