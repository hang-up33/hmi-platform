#include "ProjectIo.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

namespace {

QVariantMap makeWidgetVariant(const QString &id,
                              int x, int y,
                              int w, int h,
                              const QString &text = QString(),
                              const QString &tag = QString(),
                              const QString &backgroundColor = QString(),
                              const QString &textColor = QString(),
                              int fontSize = 0,
                              const QString &borderColor = QString(),
                              int borderWidth = -1,
                              int radius = -1,
                              bool fontBold = false,
                              bool fontItalic = false,
                              const QString &fontFamily = QString(),
                              const QString &hAlign = QString(),
                              const QString &vAlign = QString(),
                              qreal opacity = -1.0)
{
    QVariantMap m;
    m.insert("id", id);
    m.insert("type", "Button");
    m.insert("x", x);
    m.insert("y", y);
    m.insert("width", w);
    m.insert("height", h);
    m.insert("text", text);
    m.insert("tag", tag);
    // Task 28: スタイル属性も QML（QVariantMap）→ save → load を往復する。
    m.insert("backgroundColor", backgroundColor);
    m.insert("textColor", textColor);
    m.insert("fontSize", fontSize);
    // Task 31: ボーダー＋角丸も往復する。数値は -1 = 未指定（0 は正当値）。
    m.insert("borderColor", borderColor);
    m.insert("borderWidth", borderWidth);
    m.insert("radius", radius);
    // Task 33: フォント詳細も QML（QVariantMap）→ save → load を往復する。
    m.insert("fontBold", fontBold);
    m.insert("fontItalic", fontItalic);
    m.insert("fontFamily", fontFamily);
    // Task 34: 配置 + 不透明度も QML（QVariantMap）→ save → load を往復する。
    // opacity は -1 = 未指定（0.0 は正当値 = 完全透明）。
    m.insert("hAlign", hAlign);
    m.insert("vAlign", vAlign);
    m.insert("opacity", opacity);
    return m;
}

QUrl urlForFile(const QTemporaryDir &dir, const QString &name)
{
    return QUrl::fromLocalFile(dir.filePath(name));
}

} // namespace

class ProjectIoTest : public QObject
{
    Q_OBJECT

private slots:
    void saveThenLoadRoundTrip();
    void zeroBorderRoundTripsThroughBridge();
    void saveOmitsBorderForWidgetWithoutBorderKeys();
    void saveProducesValidJsonOnDisk();
    void loadRejectsMalformedJson();
    void loadRejectsSchemaMismatchedJson();
    void loadRejectsMissingFile();
    void loadRejectsEmptyUrl();
    void saveRejectsEmptyUrl();
};

void ProjectIoTest::saveThenLoadRoundTrip()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    QVariantList widgets;
    widgets.append(makeWidgetVariant("btn001", 10, 20, 120, 40, "Start", "PLC.START",
                                     "#ff0000", "#00ff00", 22, "#112233", 3, 8,
                                     true, true, "Courier New", "left", "top", 0.5));
    widgets.append(makeWidgetVariant("btn002", 50, 80, 100, 30));

    ProjectIo io;
    const QUrl url = urlForFile(dir, "sample.json");
    QVERIFY(io.save(url, "Sample", "Main", widgets));

    const QVariantMap result = io.load(url);
    QCOMPARE(result.value("ok").toBool(), true);
    QCOMPARE(result.value("project").toString(), QStringLiteral("Sample"));
    QCOMPARE(result.value("screen").toString(), QStringLiteral("Main"));

    const QVariantList loaded = result.value("widgets").toList();
    QCOMPARE(loaded.size(), 2);

    const QVariantMap w0 = loaded.at(0).toMap();
    QCOMPARE(w0.value("id").toString(), QStringLiteral("btn001"));
    QCOMPARE(w0.value("type").toString(), QStringLiteral("Button"));
    QCOMPARE(w0.value("x").toInt(), 10);
    QCOMPARE(w0.value("y").toInt(), 20);
    QCOMPARE(w0.value("width").toInt(), 120);
    QCOMPARE(w0.value("height").toInt(), 40);
    QCOMPARE(w0.value("text").toString(), QStringLiteral("Start"));
    QCOMPARE(w0.value("tag").toString(), QStringLiteral("PLC.START"));
    // Task 28: スタイル属性も QML → save → load を往復して再現される。
    QCOMPARE(w0.value("backgroundColor").toString(), QStringLiteral("#ff0000"));
    QCOMPARE(w0.value("textColor").toString(), QStringLiteral("#00ff00"));
    QCOMPARE(w0.value("fontSize").toInt(), 22);
    // Task 31: ボーダー＋角丸も往復する。
    QCOMPARE(w0.value("borderColor").toString(), QStringLiteral("#112233"));
    QCOMPARE(w0.value("borderWidth").toInt(), 3);
    QCOMPARE(w0.value("radius").toInt(), 8);
    // Task 33: フォント詳細も往復する。
    QCOMPARE(w0.value("fontBold").toBool(), true);
    QCOMPARE(w0.value("fontItalic").toBool(), true);
    QCOMPARE(w0.value("fontFamily").toString(), QStringLiteral("Courier New"));
    // Task 34: 配置 + 不透明度も往復する。
    QCOMPARE(w0.value("hAlign").toString(), QStringLiteral("left"));
    QCOMPARE(w0.value("vAlign").toString(), QStringLiteral("top"));
    QCOMPARE(w0.value("opacity").toDouble(), 0.5);

    const QVariantMap w1 = loaded.at(1).toMap();
    QCOMPARE(w1.value("id").toString(), QStringLiteral("btn002"));
    QVERIFY(w1.value("text").toString().isEmpty());
    QVERIFY(w1.value("tag").toString().isEmpty());
    // 既定スタイル（未指定）の widget は空 / 0 で戻る（toJson 省略 → fromJson 既定埋め）。
    QVERIFY(w1.value("backgroundColor").toString().isEmpty());
    QVERIFY(w1.value("textColor").toString().isEmpty());
    QCOMPARE(w1.value("fontSize").toInt(), 0);
    // Task 31: 未指定の数値は -1（センチネル）で戻る（toJson 省略 → fromJson の toInt(-1)）。
    QVERIFY(w1.value("borderColor").toString().isEmpty());
    QCOMPARE(w1.value("borderWidth").toInt(), -1);
    QCOMPARE(w1.value("radius").toInt(), -1);
    // Task 33: 未指定のフォント詳細は false / 空で戻る（toJson 省略 → fromJson 既定埋め）。
    QCOMPARE(w1.value("fontBold").toBool(), false);
    QCOMPARE(w1.value("fontItalic").toBool(), false);
    QVERIFY(w1.value("fontFamily").toString().isEmpty());
    // Task 34: 未指定の配置は空、opacity は -1（センチネル）で戻る（toJson 省略 → fromJson 既定埋め）。
    QVERIFY(w1.value("hAlign").toString().isEmpty());
    QVERIFY(w1.value("vAlign").toString().isEmpty());
    QCOMPARE(w1.value("opacity").toDouble(), -1.0);
}

// Task 31: borderWidth=0（ボーダーなし）/ radius=0（角丸なし）が C++ ブリッジ
//（QVariantMap → save → JSON → load → QVariantMap）を往復しても 0 のまま保たれる
// ことを固定する。toJson の `>= 0` と fromJson の toInt(-1) が揃っていないと、0 が
// 落ちて未指定（既定外観）になる回帰が起きる。
void ProjectIoTest::zeroBorderRoundTripsThroughBridge()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    QVariantList widgets;
    // Task 34: opacity=0.0（完全透明）も 0 が正当値の real センチネル。borderWidth/radius=0 と
    // 同じく C++ ブリッジ往復で 0.0 のまま保たれること（落ちて未指定にならないこと）を併せて固定する。
    widgets.append(makeWidgetVariant("btn001", 0, 0, 120, 40, "NoBorder", QString(),
                                     QString(), QString(), 0, QString(), 0, 0,
                                     false, false, QString(), QString(), QString(), 0.0));

    ProjectIo io;
    const QUrl url = urlForFile(dir, "zero_border.json");
    QVERIFY(io.save(url, "Sample", "Main", widgets));

    const QVariantMap result = io.load(url);
    QCOMPARE(result.value("ok").toBool(), true);
    const QVariantList loaded = result.value("widgets").toList();
    QCOMPARE(loaded.size(), 1);
    const QVariantMap w0 = loaded.at(0).toMap();
    QCOMPARE(w0.value("borderWidth").toInt(), 0);
    QCOMPARE(w0.value("radius").toInt(), 0);
    QCOMPARE(w0.value("opacity").toDouble(), 0.0);
}

// Task 31（Codex PR #62 P2 の回帰固定）：border キーを **持たない** QVariantMap
//（Canvas を介さない呼び出し・旧経路を模す）を save すると、ディスク上の JSON は
// borderWidth / radius を **省略** しなければならない。save 側が `m.value(key, -1).toInt()`
// でなく `.toInt()` だとキー欠落が 0 になり、toJson の `>= 0` で「明示的なボーダーなし」
// として 0 が誤保存される。本テストはその回帰を検出する。
void ProjectIoTest::saveOmitsBorderForWidgetWithoutBorderKeys()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    // border キーを敢えて入れない最小 widget（makeWidgetVariant は border を入れるため使わない）。
    QVariantMap m;
    m.insert("id", "btn001");
    m.insert("type", "Button");
    m.insert("x", 0);
    m.insert("y", 0);
    m.insert("width", 120);
    m.insert("height", 40);

    ProjectIo io;
    const QString path = dir.filePath("no_border_keys.json");
    QVERIFY(io.save(QUrl::fromLocalFile(path), "Sample", "Main", QVariantList{m}));

    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly | QIODevice::Text));
    const QByteArray bytes = file.readAll();
    file.close();

    const QJsonDocument doc = QJsonDocument::fromJson(bytes);
    QVERIFY(doc.isObject());
    const QJsonObject widget = doc.object()
                                   .value("screens").toArray().at(0).toObject()
                                   .value("widgets").toArray().at(0).toObject();
    QVERIFY(!widget.contains("borderWidth"));
    QVERIFY(!widget.contains("radius"));
    QVERIFY(!widget.contains("borderColor"));
}

void ProjectIoTest::saveProducesValidJsonOnDisk()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    QVariantList widgets;
    widgets.append(makeWidgetVariant("btn001", 0, 0, 100, 30));

    ProjectIo io;
    const QString path = dir.filePath("on_disk.json");
    QVERIFY(io.save(QUrl::fromLocalFile(path), "OnDisk", "Main", widgets));

    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly | QIODevice::Text));
    const QByteArray bytes = file.readAll();
    file.close();

    QJsonParseError parseErr{};
    const QJsonDocument doc = QJsonDocument::fromJson(bytes, &parseErr);
    QCOMPARE(parseErr.error, QJsonParseError::NoError);
    QVERIFY(doc.isObject());

    const QJsonObject root = doc.object();
    QCOMPARE(root.value("project").toString(), QStringLiteral("OnDisk"));
    QVERIFY(root.value("screens").isArray());
    QCOMPARE(root.value("screens").toArray().size(), 1);
    QCOMPARE(root.value("screens").toArray().at(0).toObject().value("name").toString(),
             QStringLiteral("Main"));
}

void ProjectIoTest::loadRejectsMalformedJson()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    const QString path = dir.filePath("bad.json");
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Text));
    file.write("{ this is not json");
    file.close();

    ProjectIo io;
    const QVariantMap result = io.load(QUrl::fromLocalFile(path));
    QCOMPARE(result.value("ok").toBool(), false);
    QCOMPARE(result.value("widgets").toList().size(), 0);
}

void ProjectIoTest::loadRejectsSchemaMismatchedJson()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    const QString path = dir.filePath("mismatched.json");
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Text));
    file.write(R"({"foo": "bar", "screens": []})");
    file.close();

    ProjectIo io;
    const QVariantMap result = io.load(QUrl::fromLocalFile(path));
    QCOMPARE(result.value("ok").toBool(), false);
}

void ProjectIoTest::loadRejectsMissingFile()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    ProjectIo io;
    const QVariantMap result = io.load(urlForFile(dir, "does_not_exist.json"));
    QCOMPARE(result.value("ok").toBool(), false);
}

void ProjectIoTest::loadRejectsEmptyUrl()
{
    ProjectIo io;
    const QVariantMap result = io.load(QUrl{});
    QCOMPARE(result.value("ok").toBool(), false);
}

void ProjectIoTest::saveRejectsEmptyUrl()
{
    ProjectIo io;
    QVERIFY(!io.save(QUrl{}, "Sample", "Main", QVariantList{}));
}

QTEST_APPLESS_MAIN(ProjectIoTest)
#include "tst_project_io.moc"
