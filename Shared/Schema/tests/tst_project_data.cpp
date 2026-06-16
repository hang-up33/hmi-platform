#include "hmi/schema/ConnectionData.h"
#include "hmi/schema/ProjectData.h"
#include "hmi/schema/ScreenData.h"
#include "hmi/schema/SourceData.h"
#include "hmi/schema/VariableData.h"
#include "hmi/schema/WidgetData.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTest>

using hmi::schema::ConnectionData;
using hmi::schema::ProjectData;
using hmi::schema::ScreenData;
using hmi::schema::SourceData;
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

    // Phase 7 / MB-1: connections[] + variable.source.connection 参照
    void connectionsAndSourceRoundTrip();
    void omitsEmptyConnections();
    void isValidJsonRejectsInvalidConnections();

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

// Phase 7 / MB-1: connections[] と variable.source.connection 参照が round-trip し、
// source.connection が ConnectionData.id を正しく指す（計画書の正準 JSON 形）。
void ProjectDataTest::connectionsAndSourceRoundTrip()
{
    ProjectData src;
    src.project = "Sample";
    src.screens.append(makeScreen("Main"));

    ConnectionData conn;
    conn.id = "plc1";
    conn.proto = "modbusTcp";
    conn.host = "192.168.0.10";
    conn.port = 502;
    conn.unitId = 1;
    src.connections.append(conn);

    VariableData var;
    var.name = "tankLevel";
    var.type = "int";
    var.initial = "0";
    SourceData s;
    s.connection = "plc1";
    s.reg = "holding";
    s.address = 0;
    s.poll = 1000;
    var.source = s;
    src.variables.append(var);

    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("connections"));
    // 計画書の正準 JSON：variable.source は接続詳細を持たず id 参照のみ。
    {
        const QJsonObject varObj = obj.value("variables").toArray().at(0).toObject();
        const QJsonObject srcObj = varObj.value("source").toObject();
        QCOMPARE(srcObj.value("connection").toString(), QStringLiteral("plc1"));
        QVERIFY(!srcObj.contains("host"));  // 接続詳細は connections[] 側
    }

    const ProjectData r = ProjectData::fromJson(obj);
    QCOMPARE(r.connections.size(), 1);
    QCOMPARE(r.connections.at(0).id, QStringLiteral("plc1"));
    QCOMPARE(r.connections.at(0).host, QStringLiteral("192.168.0.10"));
    QCOMPARE(r.connections.at(0).port, 502);
    QCOMPARE(r.connections.at(0).unitId, 1);

    QCOMPARE(r.variables.size(), 1);
    QVERIFY(r.variables.at(0).source.has_value());
    // source.connection が ConnectionData.id を指す（参照が round-trip）。
    QCOMPARE(r.variables.at(0).source->connection, r.connections.at(0).id);
    QCOMPARE(r.variables.at(0).source->reg, QStringLiteral("holding"));
    QCOMPARE(r.variables.at(0).source->address, 0);

    // connections / source を含んでも isValidJson を通る。
    QVERIFY(ProjectData::isValidJson(obj));
}

// Phase 7 / MB-1: connections が空のとき toJson で省略（後方互換）。
void ProjectDataTest::omitsEmptyConnections()
{
    ProjectData src;
    src.project = "Sample";
    src.screens.append(makeScreen("Main"));
    // connections は既定の空。

    const QJsonObject obj = src.toJson();
    QVERIFY(!obj.contains("connections"));

    const ProjectData r = ProjectData::fromJson(obj);
    QVERIFY(r.connections.isEmpty());
    // connections を持たない（＝旧）JSON も従来どおり有効。
    QVERIFY(ProjectData::isValidJson(obj));
}

// Phase 7 / MB-1: connections は存在するなら配列 + 各要素が ConnectionData として
// 有効（id 非空）であることを要求する（不在は後方互換で許容）。
void ProjectDataTest::isValidJsonRejectsInvalidConnections()
{
    // connections が配列でない → 無効。
    {
        QJsonObject obj = validProjectJson();
        obj["connections"] = QStringLiteral("not-an-array");
        QVERIFY(!ProjectData::isValidJson(obj));
    }
    // id が空の接続 → 無効。
    {
        QJsonObject badConn;
        badConn["id"] = "";
        QJsonObject obj = validProjectJson();
        obj["connections"] = QJsonArray{ badConn };
        QVERIFY(!ProjectData::isValidJson(obj));
    }
    // 妥当な connections は有効。
    {
        QJsonObject conn;
        conn["id"] = "plc1";
        conn["host"] = "192.168.0.10";
        QJsonObject obj = validProjectJson();
        obj["connections"] = QJsonArray{ conn };
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
