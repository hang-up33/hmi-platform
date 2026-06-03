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
                              int fontSize = 0)
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
                                     "#ff0000", "#00ff00", 22));
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

    const QVariantMap w1 = loaded.at(1).toMap();
    QCOMPARE(w1.value("id").toString(), QStringLiteral("btn002"));
    QVERIFY(w1.value("text").toString().isEmpty());
    QVERIFY(w1.value("tag").toString().isEmpty());
    // 既定スタイル（未指定）の widget は空 / 0 で戻る（toJson 省略 → fromJson 既定埋め）。
    QVERIFY(w1.value("backgroundColor").toString().isEmpty());
    QVERIFY(w1.value("textColor").toString().isEmpty());
    QCOMPARE(w1.value("fontSize").toInt(), 0);
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
