#include "hmi/schema/ActionData.h"
#include "hmi/schema/BindingData.h"
#include "hmi/schema/VariableData.h"

#include <QJsonObject>
#include <QTest>

using namespace hmi::schema;

// Task 39: 変数定義 / アクション / バインディングの新スキーマ型の JSON I/O を固定する。
class VariableDataTest : public QObject {
    Q_OBJECT

private slots:
    void variableRoundTrip();
    void variableRealRoundTrip();
    void variableInitialNormalizesNonString();
    void variableIsValidJson_data();
    void variableIsValidJson();

    void actionRoundTrip();
    void actionIsValidJson_data();
    void actionIsValidJson();
    void actionTriggerValidation();

    void bindingRoundTrip();
    void bindingIsValidJson_data();
    void bindingIsValidJson();
};

void VariableDataTest::variableRoundTrip()
{
    VariableData src;
    src.name = "running";
    src.type = "bool";
    src.initial = "false";

    const VariableData r = VariableData::fromJson(src.toJson());
    QCOMPARE(r.name, src.name);
    QCOMPARE(r.type, src.type);
    QCOMPARE(r.initial, src.initial);
}

// Task 53: real 型変数の round-trip。type="real" が保たれ、小数の initial（文字列表現 /
// JSON number どちらでも）が値を失わず文字列保持される。
void VariableDataTest::variableRealRoundTrip()
{
    {
        VariableData src;
        src.name = "temperature";
        src.type = "real";
        src.initial = "36.5";

        const VariableData r = VariableData::fromJson(src.toJson());
        QCOMPARE(r.name, src.name);
        QCOMPARE(r.type, QStringLiteral("real"));
        QCOMPARE(r.initial, QStringLiteral("36.5"));
    }
    {
        // JSON number（小数）の initial も jsonValueToString で文字列正規化される。
        QJsonObject obj;
        obj["name"] = "temperature";
        obj["type"] = "real";
        obj["initial"] = 36.5;  // JSON number（小数）
        const VariableData v = VariableData::fromJson(obj);
        QCOMPARE(v.initial, QStringLiteral("36.5"));
    }
}

// Task 39（Codex PR #78 [P2]）：非文字列の initial（bool/int）も文字列へ正規化され、
// 値が静かに失われない（toString() 直読みだと bool/int は空文字に落ちる）。
void VariableDataTest::variableInitialNormalizesNonString()
{
    {
        QJsonObject obj;
        obj["name"] = "running";
        obj["type"] = "bool";
        obj["initial"] = true;  // JSON bool
        const VariableData v = VariableData::fromJson(obj);
        QCOMPARE(v.initial, QStringLiteral("true"));
    }
    {
        QJsonObject obj;
        obj["name"] = "count";
        obj["type"] = "int";
        obj["initial"] = 5;  // JSON number（整数）
        const VariableData v = VariableData::fromJson(obj);
        QCOMPARE(v.initial, QStringLiteral("5"));
    }
}

void VariableDataTest::variableIsValidJson_data()
{
    QTest::addColumn<QString>("name");
    QTest::addColumn<QString>("type");
    QTest::addColumn<bool>("valid");

    QTest::newRow("bool ok") << "v" << "bool" << true;
    QTest::newRow("int ok") << "v" << "int" << true;
    QTest::newRow("real ok") << "v" << "real" << true;  // Task 53
    QTest::newRow("string ok") << "v" << "string" << true;
    QTest::newRow("empty name") << "" << "bool" << false;
    QTest::newRow("bad type") << "v" << "float" << false;
}

void VariableDataTest::variableIsValidJson()
{
    QFETCH(QString, name);
    QFETCH(QString, type);
    QFETCH(bool, valid);

    QJsonObject obj;
    obj["name"] = name;
    obj["type"] = type;
    QCOMPARE(VariableData::isValidJson(obj), valid);
}

void VariableDataTest::actionRoundTrip()
{
    ActionData src;
    src.trigger = "onClick";
    src.op = "setVariable";
    src.target = "running";
    src.value = "true";

    const ActionData r = ActionData::fromJson(src.toJson());
    QCOMPARE(r.trigger, src.trigger);
    QCOMPARE(r.op, src.op);
    QCOMPARE(r.target, src.target);
    QCOMPARE(r.value, src.value);
}

void VariableDataTest::actionIsValidJson_data()
{
    QTest::addColumn<QString>("op");
    QTest::addColumn<QString>("target");
    QTest::addColumn<bool>("valid");

    QTest::newRow("setVariable ok") << "setVariable" << "running" << true;
    QTest::newRow("toggleVariable ok") << "toggleVariable" << "running" << true;
    QTest::newRow("empty op") << "" << "running" << false;
    QTest::newRow("unknown op") << "setVar" << "running" << false;  // 許可リスト外
    QTest::newRow("empty target") << "toggleVariable" << "" << false;
}

void VariableDataTest::actionIsValidJson()
{
    QFETCH(QString, op);
    QFETCH(QString, target);
    QFETCH(bool, valid);

    QJsonObject obj;
    obj["op"] = op;
    obj["target"] = target;
    QCOMPARE(ActionData::isValidJson(obj), valid);
}

// Task 39（Codex PR #78 [P2]）：trigger は欠落時 "onClick" を許容し、存在する場合は
// "onClick" のみ有効（onRelease 等の未対応 trigger は load 入口で弾く）。fromJson は
// 欠落 trigger を "onClick" へ正規化する。
void VariableDataTest::actionTriggerValidation()
{
    QJsonObject base;
    base["op"] = "toggleVariable";
    base["target"] = "running";

    // trigger 欠落 → 有効、fromJson で "onClick" に正規化。
    QVERIFY(ActionData::isValidJson(base));
    QCOMPARE(ActionData::fromJson(base).trigger, QStringLiteral("onClick"));

    // trigger "onClick" → 有効。
    {
        QJsonObject obj = base;
        obj["trigger"] = "onClick";
        QVERIFY(ActionData::isValidJson(obj));
    }
    // trigger "onRelease"（未対応）→ 無効。
    {
        QJsonObject obj = base;
        obj["trigger"] = "onRelease";
        QVERIFY(!ActionData::isValidJson(obj));
    }
}

void VariableDataTest::bindingRoundTrip()
{
    BindingData src;
    src.property = "backgroundColor";
    src.variable = "runColor";

    const BindingData r = BindingData::fromJson(src.toJson());
    QCOMPARE(r.property, src.property);
    QCOMPARE(r.variable, src.variable);
}

void VariableDataTest::bindingIsValidJson_data()
{
    QTest::addColumn<QString>("property");
    QTest::addColumn<QString>("variable");
    QTest::addColumn<bool>("valid");

    QTest::newRow("ok") << "visible" << "running" << true;
    QTest::newRow("empty property") << "" << "running" << false;
    QTest::newRow("empty variable") << "text" << "" << false;
}

void VariableDataTest::bindingIsValidJson()
{
    QFETCH(QString, property);
    QFETCH(QString, variable);
    QFETCH(bool, valid);

    QJsonObject obj;
    obj["property"] = property;
    obj["variable"] = variable;
    QCOMPARE(BindingData::isValidJson(obj), valid);
}

QTEST_APPLESS_MAIN(VariableDataTest)
#include "tst_variable_data.moc"
