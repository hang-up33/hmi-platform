#include "hmi/schema/ActionData.h"
#include "hmi/schema/BindingData.h"
#include "hmi/schema/ConnectionData.h"
#include "hmi/schema/SourceData.h"
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

    // Phase 7 / MB-1: 変数ソース（SourceData）+ 接続（ConnectionData）
    void variableSourceBackwardCompat();
    void variableSourceRoundTrip();
    void variableSourceInvalidRejected();
    void sourceDefaults();
    void sourceAddressZeroRoundTrip();
    void sourceIsValidJson_data();
    void sourceIsValidJson();
    void connectionDefaults();
    void connectionRoundTrip();
    void connectionIsValidJson_data();
    void connectionIsValidJson();

    // Phase 9 / OP-1: OPC-UA proto 2 本目（endpoint + nodeId）
    void opcuaConnectionRoundTrip();
    void opcuaSourceRoundTrip();
    void sourceProtoIsValidJson_data();
    void sourceProtoIsValidJson();
    void sourceNodeIdTypeValidation();
    void modbusConnectionBackwardCompat();

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
    {
        // Codex PR #112 [P2]：高精度の real 初期値が既定 6 桁で丸められず保たれる。
        // `0.123456789`（9 有効桁）は `QString::number(d)` 既定だと "0.123457" に丸まり
        // round-trip が壊れるが、最短 round-trip 桁探索で元値に戻る表現を保持する。
        const double precise = 0.123456789;
        QJsonObject obj;
        obj["name"] = "ratio";
        obj["type"] = "real";
        obj["initial"] = precise;  // JSON number（高精度小数）
        const VariableData v = VariableData::fromJson(obj);
        // 文字列が元の double へ正確に戻る（丸め損失なし）。
        QCOMPARE(v.initial.toDouble(), precise);
        // 冗長表現でなく入力どおりの最短表現になっている。
        QCOMPARE(v.initial, QStringLiteral("0.123456789"));
    }
    {
        // CodeRabbit PR #112 [Major]：qlonglong の範囲外（1e100）でも UB を起こさず、
        // 値を失わず round-trip する（整数表現化を試みず小数経路で文字列化される）。
        const double huge = 1e100;
        QJsonObject obj;
        obj["name"] = "big";
        obj["type"] = "real";
        obj["initial"] = huge;
        const VariableData v = VariableData::fromJson(obj);
        QCOMPARE(v.initial.toDouble(), huge);
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

// Phase 7 / MB-1: source 無しの変数は従来どおり（後方互換）。toJson に "source" が出ず、
// 既存の source を持たない JSON を読んでも source は nullopt のまま。
void VariableDataTest::variableSourceBackwardCompat()
{
    VariableData src;
    src.name = "running";
    src.type = "bool";
    src.initial = "false";
    QVERIFY(!src.source.has_value());

    const QJsonObject json = src.toJson();
    QVERIFY(!json.contains("source"));  // source 無しは書き出さない

    const VariableData r = VariableData::fromJson(json);
    QVERIFY(!r.source.has_value());

    // QVariantMap 経路も同様（source キーを持たない）。
    const QVariantMap vm = src.toVariantMap();
    QVERIFY(!vm.contains("source"));
    QVERIFY(!VariableData::fromVariantMap(vm).source.has_value());

    // 旧 JSON（variables だけ・source 無し）が isValidJson を通る。
    QVERIFY(VariableData::isValidJson(json));
}

// Phase 7 / MB-1: source 付き変数の JSON / QVariantMap round-trip。
void VariableDataTest::variableSourceRoundTrip()
{
    VariableData src;
    src.name = "tankLevel";
    src.type = "int";
    src.initial = "0";
    SourceData s;
    s.connection = "plc1";
    s.reg = "holding";
    s.address = 0;
    s.poll = 1000;
    src.source = s;

    // JSON round-trip
    {
        const VariableData r = VariableData::fromJson(src.toJson());
        QVERIFY(r.source.has_value());
        QCOMPARE(r.source->connection, QStringLiteral("plc1"));
        QCOMPARE(r.source->reg, QStringLiteral("holding"));
        QCOMPARE(r.source->address, 0);
        QCOMPARE(r.source->poll, 1000);
    }
    // QVariantMap round-trip
    {
        const VariableData r = VariableData::fromVariantMap(src.toVariantMap());
        QVERIFY(r.source.has_value());
        QCOMPARE(r.source->connection, QStringLiteral("plc1"));
        QCOMPARE(r.source->reg, QStringLiteral("holding"));
        QCOMPARE(r.source->address, 0);
    }
    // source を持つ変数も isValidJson を通る（source は必須集合に入れない）。
    QVERIFY(VariableData::isValidJson(src.toJson()));
}

// Phase 7 / MB-1（Codex PR #119 [P2]）：source は optional だが、存在する場合は内容を
// 検証する。不正な source（非 object / reg 不正 / connection 空）を持つ変数は弾く。
void VariableDataTest::variableSourceInvalidRejected()
{
    // 正常な土台。
    QJsonObject base;
    base["name"] = "tankLevel";
    base["type"] = "int";
    base["initial"] = "0";

    // source 無しは通る（後方互換）。
    QVERIFY(VariableData::isValidJson(base));

    // source が object でない（文字列）→ 弾く。
    {
        QJsonObject o = base;
        o["source"] = QStringLiteral("bad");
        QVERIFY(!VariableData::isValidJson(o));
    }
    // reg が不正種別 → 弾く。
    {
        QJsonObject src;
        src["connection"] = "plc1";
        src["reg"] = "bad";
        QJsonObject o = base;
        o["source"] = src;
        QVERIFY(!VariableData::isValidJson(o));
    }
    // connection が空 → 弾く。
    {
        QJsonObject src;
        src["connection"] = "";
        src["reg"] = "holding";
        QJsonObject o = base;
        o["source"] = src;
        QVERIFY(!VariableData::isValidJson(o));
    }
    // 正常な source → 通る。
    {
        QJsonObject src;
        src["connection"] = "plc1";
        src["reg"] = "holding";
        src["address"] = 0;
        QJsonObject o = base;
        o["source"] = src;
        QVERIFY(VariableData::isValidJson(o));
    }
}

// Phase 7 / MB-1: SourceData の欠落時既定（address 0 / poll 1000）。
void VariableDataTest::sourceDefaults()
{
    QJsonObject obj;
    obj["connection"] = "plc1";
    obj["reg"] = "holding";
    // address / poll を省略 → 既定で埋まる。
    const SourceData s = SourceData::fromJson(obj);
    QCOMPARE(s.address, 0);
    QCOMPARE(s.poll, 1000);

    // QVariantMap 経路も同じ既定。
    QVariantMap m;
    m.insert("connection", "plc1");
    m.insert("reg", "coil");
    const SourceData s2 = SourceData::fromVariantMap(m);
    QCOMPARE(s2.address, 0);
    QCOMPARE(s2.poll, 1000);
}

// Phase 7 / MB-1: address は 0 ベースが正準。0 / 非 0 とも round-trip で保たれる
// （0 は省略書き出しせず常に書く）。
void VariableDataTest::sourceAddressZeroRoundTrip()
{
    for (int addr : {0, 1, 42}) {
        SourceData s;
        s.connection = "plc1";
        s.reg = "input";
        s.address = addr;
        s.poll = 500;
        const QJsonObject json = s.toJson();
        QVERIFY(json.contains("address"));  // 0 でも書き出す
        const SourceData r = SourceData::fromJson(json);
        QCOMPARE(r.address, addr);
        QCOMPARE(r.poll, 500);
    }
}

void VariableDataTest::sourceIsValidJson_data()
{
    QTest::addColumn<QString>("connection");
    QTest::addColumn<QString>("reg");
    QTest::addColumn<bool>("valid");

    QTest::newRow("coil ok") << "plc1" << "coil" << true;
    QTest::newRow("discrete ok") << "plc1" << "discrete" << true;
    QTest::newRow("input ok") << "plc1" << "input" << true;
    QTest::newRow("holding ok") << "plc1" << "holding" << true;
    QTest::newRow("empty connection") << "" << "holding" << false;
    QTest::newRow("bad reg") << "plc1" << "register" << false;
    QTest::newRow("empty reg") << "plc1" << "" << false;
}

void VariableDataTest::sourceIsValidJson()
{
    QFETCH(QString, connection);
    QFETCH(QString, reg);
    QFETCH(bool, valid);

    QJsonObject obj;
    obj["connection"] = connection;
    obj["reg"] = reg;
    QCOMPARE(SourceData::isValidJson(obj), valid);
}

// Phase 7 / MB-1: ConnectionData の欠落時既定（proto modbusTcp / port 502 / unitId 1）。
void VariableDataTest::connectionDefaults()
{
    QJsonObject obj;
    obj["id"] = "plc1";
    // proto / port / unitId を省略 → 既定で埋まる。
    const ConnectionData c = ConnectionData::fromJson(obj);
    QCOMPARE(c.proto, QStringLiteral("modbusTcp"));
    QCOMPARE(c.port, 502);
    QCOMPARE(c.unitId, 1);

    QVariantMap m;
    m.insert("id", "plc1");
    const ConnectionData c2 = ConnectionData::fromVariantMap(m);
    QCOMPARE(c2.proto, QStringLiteral("modbusTcp"));
    QCOMPARE(c2.port, 502);
    QCOMPARE(c2.unitId, 1);
}

void VariableDataTest::connectionRoundTrip()
{
    ConnectionData src;
    src.id = "plc1";
    src.proto = "modbusTcp";
    src.host = "192.168.0.10";
    src.port = 502;
    src.unitId = 1;

    {
        const ConnectionData r = ConnectionData::fromJson(src.toJson());
        QCOMPARE(r.id, src.id);
        QCOMPARE(r.proto, src.proto);
        QCOMPARE(r.host, src.host);
        QCOMPARE(r.port, src.port);
        QCOMPARE(r.unitId, src.unitId);
    }
    {
        const ConnectionData r = ConnectionData::fromVariantMap(src.toVariantMap());
        QCOMPARE(r.id, src.id);
        QCOMPARE(r.host, src.host);
        QCOMPARE(r.port, src.port);
        QCOMPARE(r.unitId, src.unitId);
    }
}

void VariableDataTest::connectionIsValidJson_data()
{
    QTest::addColumn<QString>("id");
    QTest::addColumn<bool>("valid");

    QTest::newRow("ok") << "plc1" << true;
    QTest::newRow("empty id") << "" << false;
}

void VariableDataTest::connectionIsValidJson()
{
    QFETCH(QString, id);
    QFETCH(bool, valid);

    QJsonObject obj;
    obj["id"] = id;
    QCOMPARE(ConnectionData::isValidJson(obj), valid);
}

// Phase 9 / OP-1: OPC-UA 接続（endpoint 有り）の round-trip。endpoint が保持され、
// Modbus フィールド（host/port/unitId）は既定のまま素通る。
void VariableDataTest::opcuaConnectionRoundTrip()
{
    ConnectionData src;
    src.id = "opc1";
    src.proto = "opcua";
    src.endpoint = "opc.tcp://192.168.0.20:4840";

    {
        const QJsonObject json = src.toJson();
        QVERIFY(json.contains("endpoint"));  // 非空なので書き出す
        const ConnectionData r = ConnectionData::fromJson(json);
        QCOMPARE(r.id, src.id);
        QCOMPARE(r.proto, QStringLiteral("opcua"));
        QCOMPARE(r.endpoint, src.endpoint);
    }
    {
        const ConnectionData r = ConnectionData::fromVariantMap(src.toVariantMap());
        QCOMPARE(r.id, src.id);
        QCOMPARE(r.proto, QStringLiteral("opcua"));
        QCOMPARE(r.endpoint, src.endpoint);
    }
    // opcua 接続も id 非空なら isValidJson を通る（endpoint は optional）。
    QVERIFY(ConnectionData::isValidJson(src.toJson()));
}

// Phase 9 / OP-1: OPC-UA source（reg 無し・nodeId 有り）の round-trip。nodeId が保持され、
// isValidJson を通る（reg 無しでも nodeId 非空なら有効）。
void VariableDataTest::opcuaSourceRoundTrip()
{
    VariableData src;
    src.name = "spindleTemp";
    src.type = "real";
    src.initial = "0";
    SourceData s;
    s.connection = "opc1";
    s.nodeId = "ns=2;s=Spindle.Temp";
    s.poll = 0;  // 0 = 購読のみ（フォールバック無し）
    src.source = s;

    // JSON round-trip：reg は空のまま、nodeId が保持される。
    {
        const QJsonObject json = src.toJson();
        const QJsonObject sjson = json.value("source").toObject();
        QVERIFY(sjson.contains("nodeId"));  // 非空なので書き出す
        const VariableData r = VariableData::fromJson(json);
        QVERIFY(r.source.has_value());
        QCOMPARE(r.source->connection, QStringLiteral("opc1"));
        QCOMPARE(r.source->nodeId, QStringLiteral("ns=2;s=Spindle.Temp"));
        QVERIFY(r.source->reg.isEmpty());
        QCOMPARE(r.source->poll, 0);
    }
    // QVariantMap round-trip
    {
        const VariableData r = VariableData::fromVariantMap(src.toVariantMap());
        QVERIFY(r.source.has_value());
        QCOMPARE(r.source->connection, QStringLiteral("opc1"));
        QCOMPARE(r.source->nodeId, QStringLiteral("ns=2;s=Spindle.Temp"));
    }
    // OPC-UA source（reg 無し・nodeId 有り）が isValidJson を通る。
    QVERIFY(SourceData::isValidJson(src.source->toJson()));
    // 変数全体としても isValidJson を通る（source の検証も連動）。
    QVERIFY(VariableData::isValidJson(src.toJson()));
}

// Phase 9 / OP-1: proto 種別を弁別する isValidJson。Modbus（reg 有効）/ OPC-UA（nodeId 非空）の
// いずれかを満たせば有効、双方欠落は不正。
void VariableDataTest::sourceProtoIsValidJson_data()
{
    QTest::addColumn<QString>("connection");
    QTest::addColumn<QString>("reg");
    QTest::addColumn<QString>("nodeId");
    QTest::addColumn<bool>("valid");

    // Modbus：reg 有効・nodeId 無し → 有効（従来どおり）。
    QTest::newRow("modbus holding") << "plc1" << "holding" << "" << true;
    // OPC-UA：reg 無し・nodeId 有り → 有効。
    QTest::newRow("opcua nodeId") << "opc1" << "" << "ns=2;s=Temp" << true;
    // 両方有り（混在）→ 有効（reg または nodeId のいずれかが有効なら通る OR 条件）。
    QTest::newRow("both reg+nodeId") << "plc1" << "holding" << "ns=2;s=Temp" << true;
    // reg 不正・nodeId 有り → nodeId 側で有効。
    QTest::newRow("bad reg but nodeId") << "opc1" << "register" << "ns=2;s=Temp" << true;
    // reg も nodeId も無い → 不正。
    QTest::newRow("neither reg nor nodeId") << "plc1" << "" << "" << false;
    // reg 不正・nodeId 無し → 不正。
    QTest::newRow("bad reg no nodeId") << "plc1" << "register" << "" << false;
    // connection 空・nodeId 有り → 不正（connection は必須）。
    QTest::newRow("empty connection opcua") << "" << "" << "ns=2;s=Temp" << false;
}

void VariableDataTest::sourceProtoIsValidJson()
{
    QFETCH(QString, connection);
    QFETCH(QString, reg);
    QFETCH(QString, nodeId);
    QFETCH(bool, valid);

    QJsonObject obj;
    obj["connection"] = connection;
    if (!reg.isEmpty()) {
        obj["reg"] = reg;
    }
    if (!nodeId.isEmpty()) {
        obj["nodeId"] = nodeId;
    }
    QCOMPARE(SourceData::isValidJson(obj), valid);
}

// Phase 9 / OP-1（Codex/CodeRabbit PR #140）：nodeId の型 / presence 検証。
//  ①nodeId が非文字列（JSON number 等）→ OPC-UA source として無効（reg も無いので弾く）。
//  ②reg 無し・nodeId 有り（文字列）→ 有効。
//  ③reg 無し・nodeId 空文字 → 無効。
void VariableDataTest::sourceNodeIdTypeValidation()
{
    // ①nodeId が数値（型不正）・reg 無し → 弾く。
    {
        QJsonObject obj;
        obj["connection"] = "opc1";
        obj["nodeId"] = 123;  // 文字列でない
        QVERIFY(!SourceData::isValidJson(obj));
    }
    // ②reg 無し・nodeId 文字列 → 有効。
    {
        QJsonObject obj;
        obj["connection"] = "opc1";
        obj["nodeId"] = "ns=2;s=Temp";
        QVERIFY(SourceData::isValidJson(obj));
    }
    // ③reg 無し・nodeId 空文字 → 無効。
    {
        QJsonObject obj;
        obj["connection"] = "opc1";
        obj["nodeId"] = "";
        QVERIFY(!SourceData::isValidJson(obj));
    }
}

// Phase 9 / OP-1: Modbus 既存 JSON（endpoint / nodeId を持たない）が無改変で動く。
// endpoint 無しは toJson で省略され、Modbus source は従来どおり有効。
void VariableDataTest::modbusConnectionBackwardCompat()
{
    // endpoint を設定しない Modbus 接続。
    ConnectionData c;
    c.id = "plc1";
    c.proto = "modbusTcp";
    c.host = "192.168.0.10";
    const QJsonObject cjson = c.toJson();
    QVERIFY(!cjson.contains("endpoint"));  // 空 endpoint は省略

    // nodeId を設定しない Modbus source。
    SourceData s;
    s.connection = "plc1";
    s.reg = "holding";
    s.address = 0;
    const QJsonObject sjson = s.toJson();
    QVERIFY(!sjson.contains("nodeId"));  // 空 nodeId は省略
    QVERIFY(SourceData::isValidJson(sjson));  // 従来どおり有効

    // round-trip で nodeId / endpoint は空のまま。
    QVERIFY(ConnectionData::fromJson(cjson).endpoint.isEmpty());
    QVERIFY(SourceData::fromJson(sjson).nodeId.isEmpty());
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
