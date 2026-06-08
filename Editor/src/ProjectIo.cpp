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
        // Task 28: スタイル属性も QVariantMap → WidgetData へ手動コピーする。
        // ここを抜かすと Schema / delegate を直しても styled JSON の色・フォントが
        // 保存に乗らない（縦スライスで一番取りこぼしやすい箇所）。
        w.backgroundColor = m.value(QStringLiteral("backgroundColor")).toString();
        w.textColor = m.value(QStringLiteral("textColor")).toString();
        w.fontSize = m.value(QStringLiteral("fontSize")).toInt();
        // Task 31: ボーダー＋角丸。数値は **キー欠落時に -1 を既定**にして読む
        //（`m.value(key, -1).toInt()`）。`.toInt()` だと QVariantMap にキーが無い経路
        //（Canvas を介さない呼び出し・既存テスト等）で 0 が返り、toJson の `>= 0` 規則で
        // 「未指定」でなく「明示的なボーダーなし」として誤保存される（Codex PR #62 P2）。
        w.borderColor = m.value(QStringLiteral("borderColor")).toString();
        w.borderWidth = m.value(QStringLiteral("borderWidth"), -1).toInt();
        w.radius = m.value(QStringLiteral("radius"), -1).toInt();
        // Task 33: フォント詳細も QVariantMap → WidgetData へ手動コピーする。
        // bool は既定 false なのでキー欠落時も false（QVariant::toBool() の既定）。
        w.fontBold = m.value(QStringLiteral("fontBold")).toBool();
        w.fontItalic = m.value(QStringLiteral("fontItalic")).toBool();
        w.fontFamily = m.value(QStringLiteral("fontFamily")).toString();
        // Task 34: 配置 + opacity も QVariantMap → WidgetData へ手動コピーする。配置は
        // 欠落時 空文字（= 未指定）。opacity は **`m.value(key, -1.0).toDouble()`**
        // （QVariantMap の value 側で既定 -1 を与える。`QVariant::toDouble(-1)` は引数を
        // 取らないので不可。borderWidth と同じ罠の real 版）。
        w.hAlign = m.value(QStringLiteral("hAlign")).toString();
        w.vAlign = m.value(QStringLiteral("vAlign")).toString();
        w.opacity = m.value(QStringLiteral("opacity"), -1.0).toDouble();
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
        // Task 28: load 経路でもスタイル属性を QML 側へ届ける（delegate が読む）。
        m.insert(QStringLiteral("backgroundColor"), w.backgroundColor);
        m.insert(QStringLiteral("textColor"), w.textColor);
        m.insert(QStringLiteral("fontSize"), w.fontSize);
        // Task 31: ボーダー＋角丸も QML delegate へ届ける。未指定（-1 / 空）は
        // QML 側で HmiButton の既定外観にフォールバックされる（-1 を素通しする）。
        m.insert(QStringLiteral("borderColor"), w.borderColor);
        m.insert(QStringLiteral("borderWidth"), w.borderWidth);
        m.insert(QStringLiteral("radius"), w.radius);
        // Task 33: フォント詳細も QML delegate へ届ける（delegate が HmiButton へ渡す）。
        m.insert(QStringLiteral("fontBold"), w.fontBold);
        m.insert(QStringLiteral("fontItalic"), w.fontItalic);
        m.insert(QStringLiteral("fontFamily"), w.fontFamily);
        // Task 34: 配置 + opacity も QML delegate へ届ける。未指定（空 / -1）は QML 側で
        // HmiButton の既定（中央寄せ・不透明度 1.0）にフォールバックされる（素通しする）。
        m.insert(QStringLiteral("hAlign"), w.hAlign);
        m.insert(QStringLiteral("vAlign"), w.vAlign);
        m.insert(QStringLiteral("opacity"), w.opacity);
        widgetsVar.append(m);
    }

    result.insert(QStringLiteral("ok"), true);
    result.insert(QStringLiteral("project"), proj.project);
    result.insert(QStringLiteral("screen"), screen.name);
    result.insert(QStringLiteral("widgets"), widgetsVar);
    return result;
}
