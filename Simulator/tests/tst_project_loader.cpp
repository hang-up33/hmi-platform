#include "ProjectLoader.h"

#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

namespace {

constexpr auto kValidProjectJson = R"({
  "project": "Sample",
  "screens": [
    {
      "name": "Main",
      "widgets": [
        {
          "id": "btn001",
          "type": "Button",
          "x": 10,
          "y": 20,
          "width": 120,
          "height": 40,
          "text": "Start",
          "tag": "PLC.START"
        }
      ]
    }
  ]
})";

QString writeFile(const QTemporaryDir &dir, const QString &name, const QByteArray &contents)
{
    const QString path = dir.filePath(name);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return {};
    }
    file.write(contents);
    file.close();
    return path;
}

} // namespace

class ProjectLoaderTest : public QObject
{
    Q_OBJECT

private slots:
    void loadsValidProject();
    void loadAcceptsScreenWithEmptyWidgets();
    void loadRejectsMalformedJson();
    void loadRejectsSchemaMismatchedJson();
    void loadRejectsMissingFile();
    void loadRejectsEmptyUrl();
};

void ProjectLoaderTest::loadsValidProject()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = writeFile(dir, "sample.json", QByteArray(kValidProjectJson));
    QVERIFY(!path.isEmpty());

    ProjectLoader loader;
    const QVariantMap result = loader.load(QUrl::fromLocalFile(path));

    QCOMPARE(result.value("ok").toBool(), true);
    QCOMPARE(result.value("project").toString(), QStringLiteral("Sample"));
    QCOMPARE(result.value("screen").toString(), QStringLiteral("Main"));

    const QVariantList widgets = result.value("widgets").toList();
    QCOMPARE(widgets.size(), 1);
    const QVariantMap w = widgets.first().toMap();
    QCOMPARE(w.value("id").toString(), QStringLiteral("btn001"));
    QCOMPARE(w.value("type").toString(), QStringLiteral("Button"));
    QCOMPARE(w.value("x").toInt(), 10);
    QCOMPARE(w.value("y").toInt(), 20);
    QCOMPARE(w.value("width").toInt(), 120);
    QCOMPARE(w.value("height").toInt(), 40);
    QCOMPARE(w.value("text").toString(), QStringLiteral("Start"));
    QCOMPARE(w.value("tag").toString(), QStringLiteral("PLC.START"));
}

void ProjectLoaderTest::loadAcceptsScreenWithEmptyWidgets()
{
    constexpr auto kJson = R"({
      "project": "Empty",
      "screens": [
        { "name": "Main", "widgets": [] }
      ]
    })";

    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = writeFile(dir, "empty.json", QByteArray(kJson));
    QVERIFY(!path.isEmpty());

    ProjectLoader loader;
    const QVariantMap result = loader.load(QUrl::fromLocalFile(path));

    QCOMPARE(result.value("ok").toBool(), true);
    QCOMPARE(result.value("project").toString(), QStringLiteral("Empty"));
    QCOMPARE(result.value("screen").toString(), QStringLiteral("Main"));
    QCOMPARE(result.value("widgets").toList().size(), 0);
}

void ProjectLoaderTest::loadRejectsMalformedJson()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = writeFile(dir, "bad.json", QByteArrayLiteral("{ not json"));
    QVERIFY(!path.isEmpty());

    ProjectLoader loader;
    const QVariantMap result = loader.load(QUrl::fromLocalFile(path));
    QCOMPARE(result.value("ok").toBool(), false);
    QCOMPARE(result.value("widgets").toList().size(), 0);
}

void ProjectLoaderTest::loadRejectsSchemaMismatchedJson()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    const QString path = writeFile(dir, "mismatched.json",
                                   QByteArrayLiteral(R"({"foo": "bar", "screens": []})"));
    QVERIFY(!path.isEmpty());

    ProjectLoader loader;
    const QVariantMap result = loader.load(QUrl::fromLocalFile(path));
    QCOMPARE(result.value("ok").toBool(), false);
}

void ProjectLoaderTest::loadRejectsMissingFile()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    ProjectLoader loader;
    const QVariantMap result = loader.load(QUrl::fromLocalFile(dir.filePath("does_not_exist.json")));
    QCOMPARE(result.value("ok").toBool(), false);
}

void ProjectLoaderTest::loadRejectsEmptyUrl()
{
    ProjectLoader loader;
    const QVariantMap result = loader.load(QUrl{});
    QCOMPARE(result.value("ok").toBool(), false);
}

QTEST_APPLESS_MAIN(ProjectLoaderTest)
#include "tst_project_loader.moc"
