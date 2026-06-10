#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/VariableData.h"
#include "hmi/schema/WidgetData.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTest>

using hmi::schema::ProjectData;
using hmi::schema::ScreenData;
using hmi::schema::VariableData;
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
    void variablesRoundTrip();
    void omitsEmptyVariables();
    void isValidJsonRejectsInvalidVariables();

    void isValidJsonAcceptsNormalProject();
    void isValidJsonRejectsEmptyScreensArray();
    void isValidJsonRejectsMissingScreensKey();
    void isValidJsonRejectsNonArrayScreens();
    void isValidJsonRejectsInvalidScreenElement();
    void isValidJsonRejectsNonObjectScreenElement();

    // parseValidated（refactoring）：検証付きパースが有効 JSON を通し、不正 JSON /
    // 構造無効 JSON を nullopt で弾くことを固定する。
    void parseValidatedAcceptsValidJson();
    void parseValidatedRejectsMalformedJson();
    void parseValidatedRejectsStructurallyInvalidJson();
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

// Task 39: Project レベルの変数定義配列が round-trip で要素ごと再現される。
void ProjectDataTest::variablesRoundTrip()
{
    ProjectData src;
    src.project = "Sample";
    src.screens.append(makeScreen("Main"));

    VariableData v1;
    v1.name = "running";
    v1.type = "bool";
    v1.initial = "false";
    src.variables.append(v1);

    VariableData v2;
    v2.name = "count";
    v2.type = "int";
    v2.initial = "3";
    src.variables.append(v2);

    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("variables"));

    const ProjectData r = ProjectData::fromJson(obj);
    QCOMPARE(r.variables.size(), 2);
    QCOMPARE(r.variables.at(0).name, QStringLiteral("running"));
    QCOMPARE(r.variables.at(0).type, QStringLiteral("bool"));
    QCOMPARE(r.variables.at(0).initial, QStringLiteral("false"));
    QCOMPARE(r.variables.at(1).name, QStringLiteral("count"));
    QCOMPARE(r.variables.at(1).type, QStringLiteral("int"));
    QCOMPARE(r.variables.at(1).initial, QStringLiteral("3"));
}

// Task 39: 変数が空のとき toJson で省略され、後方互換になる（旧 JSON は variables を持たない）。
void ProjectDataTest::omitsEmptyVariables()
{
    ProjectData src;
    src.project = "Sample";
    src.screens.append(makeScreen("Main"));
    // variables は既定の空。

    const QJsonObject obj = src.toJson();
    QVERIFY(!obj.contains("variables"));

    const ProjectData r = ProjectData::fromJson(obj);
    QVERIFY(r.variables.isEmpty());
    // 変数を持たない JSON も従来どおり有効（必須集合は据え置き）。
    QVERIFY(ProjectData::isValidJson(obj));
}

// Task 39（Codex PR #78 [P2]）：variables は存在するなら配列 + 各要素が VariableData として
// 有効であることを isValidJson が要求する（不在は後方互換で許容）。
void ProjectDataTest::isValidJsonRejectsInvalidVariables()
{
    // variables が配列でない → 無効。
    {
        QJsonObject obj = validProjectJson();
        obj["variables"] = QStringLiteral("not-an-array");
        QVERIFY(!ProjectData::isValidJson(obj));
    }
    // 未知の type → 無効。
    {
        QJsonObject badVar;
        badVar["name"] = "x";
        badVar["type"] = "float";  // 3 種に無い
        QJsonObject obj = validProjectJson();
        obj["variables"] = QJsonArray{ badVar };
        QVERIFY(!ProjectData::isValidJson(obj));
    }
    // 妥当な variables は有効。
    {
        QJsonObject var;
        var["name"] = "running";
        var["type"] = "bool";
        var["initial"] = "false";
        QJsonObject obj = validProjectJson();
        obj["variables"] = QJsonArray{ var };
        QVERIFY(ProjectData::isValidJson(obj));
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

// parseValidated（refactoring）：有効な Project JSON のバイト列は ProjectData を返す。
void ProjectDataTest::parseValidatedAcceptsValidJson()
{
    const QByteArray bytes = QJsonDocument(validProjectJson()).toJson();

    const std::optional<ProjectData> parsed = ProjectData::parseValidated(bytes);
    QVERIFY(parsed.has_value());
    QVERIFY(!parsed->screens.isEmpty());
}

// parseValidated（refactoring）：JSON として壊れたバイト列は nullopt（読込側が ok=false へ）。
void ProjectDataTest::parseValidatedRejectsMalformedJson()
{
    const QByteArray bytes = QByteArrayLiteral("{ this is not valid json ");

    QVERIFY(!ProjectData::parseValidated(bytes).has_value());
}

// parseValidated（refactoring）：JSON としては正しいが Project 形式として無効（screens 無し）
// なら nullopt。「isValidJson を通してから fromJson」を 1 箇所に強制していることを固定する。
void ProjectDataTest::parseValidatedRejectsStructurallyInvalidJson()
{
    const QByteArray bytes = QByteArrayLiteral("{\"project\":\"X\"}");

    QVERIFY(!ProjectData::parseValidated(bytes).has_value());
}

QTEST_APPLESS_MAIN(ProjectDataTest)
#include "tst_project_data.moc"
