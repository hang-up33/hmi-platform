#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/WidgetData.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QTest>

using hmi::schema::ProjectData;
using hmi::schema::ScreenData;
using hmi::schema::WidgetData;

namespace {

WidgetData makeWidget(const QString &id)
{
    WidgetData w;
    w.id = id;
    w.type = "Button";
    w.x = 0;
    w.y = 0;
    w.width = 100;
    w.height = 30;
    return w;
}

ScreenData makeScreen(const QString &name)
{
    ScreenData s;
    s.name = name;
    s.widgets.append(makeWidget(name + ".btn1"));
    return s;
}

QJsonObject validProjectJson()
{
    QJsonObject obj;
    obj["project"] = "Sample";
    QJsonArray screens;
    screens.append(makeScreen("Main").toJson());
    screens.append(makeScreen("Sub").toJson());
    obj["screens"] = screens;
    return obj;
}

} // namespace

class ProjectDataTest : public QObject
{
    Q_OBJECT

private slots:
    void roundTripWithMultipleScreens();

    void isValidJsonAcceptsNormalProject();
    void isValidJsonRejectsEmptyScreensArray();
    void isValidJsonRejectsMissingScreensKey();
    void isValidJsonRejectsNonArrayScreens();
    void isValidJsonRejectsInvalidScreenElement();
    void isValidJsonRejectsNonObjectScreenElement();
};

void ProjectDataTest::roundTripWithMultipleScreens()
{
    ProjectData src;
    src.project = "Sample";
    src.screens.append(makeScreen("Main"));
    src.screens.append(makeScreen("Sub"));

    const QJsonObject obj = src.toJson();
    const ProjectData restored = ProjectData::fromJson(obj);

    QCOMPARE(restored.project, src.project);
    QCOMPARE(restored.screens.size(), src.screens.size());
    for (int i = 0; i < src.screens.size(); ++i) {
        QCOMPARE(restored.screens[i].name, src.screens[i].name);
        QCOMPARE(restored.screens[i].widgets.size(), src.screens[i].widgets.size());
        for (int j = 0; j < src.screens[i].widgets.size(); ++j) {
            QCOMPARE(restored.screens[i].widgets[j].id, src.screens[i].widgets[j].id);
            QCOMPARE(restored.screens[i].widgets[j].type, src.screens[i].widgets[j].type);
            QCOMPARE(restored.screens[i].widgets[j].width, src.screens[i].widgets[j].width);
            QCOMPARE(restored.screens[i].widgets[j].height, src.screens[i].widgets[j].height);
        }
    }
}

void ProjectDataTest::isValidJsonAcceptsNormalProject()
{
    QVERIFY(ProjectData::isValidJson(validProjectJson()));
}

void ProjectDataTest::isValidJsonRejectsEmptyScreensArray()
{
    QJsonObject obj;
    obj["project"] = "Empty";
    obj["screens"] = QJsonArray{};
    QVERIFY(!ProjectData::isValidJson(obj));
}

void ProjectDataTest::isValidJsonRejectsMissingScreensKey()
{
    QJsonObject obj;
    obj["project"] = "NoScreens";
    QVERIFY(!ProjectData::isValidJson(obj));
}

void ProjectDataTest::isValidJsonRejectsNonArrayScreens()
{
    QJsonObject obj = validProjectJson();
    obj["screens"] = QStringLiteral("not-an-array");
    QVERIFY(!ProjectData::isValidJson(obj));
}

void ProjectDataTest::isValidJsonRejectsInvalidScreenElement()
{
    QJsonObject obj = validProjectJson();
    QJsonArray screens = obj.value("screens").toArray();

    QJsonObject brokenScreen;
    brokenScreen["name"] = "Broken";
    screens.append(brokenScreen);
    obj["screens"] = screens;

    QVERIFY(!ProjectData::isValidJson(obj));
}

void ProjectDataTest::isValidJsonRejectsNonObjectScreenElement()
{
    QJsonObject obj = validProjectJson();
    QJsonArray screens = obj.value("screens").toArray();
    screens.append(QJsonValue("not-an-object"));
    obj["screens"] = screens;

    QVERIFY(!ProjectData::isValidJson(obj));
}

QTEST_APPLESS_MAIN(ProjectDataTest)
#include "tst_project_data.moc"
