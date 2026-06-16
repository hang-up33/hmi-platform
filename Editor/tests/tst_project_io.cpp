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
    void actionsBindingsVariablesRoundTripThroughBridge();
    // Phase 7 / MB-1
    void variableSourceRoundTripsThroughBridge();
    void saveAggregatesConnectionsFromSources();
    void variableWithoutSourceStaysInternal();
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

// Task 39: アクション / バインディング（per-widget）+ 変数定義（Project レベル）が、
// QVariantMap → save → JSON → load → QVariantMap の C++ ブリッジを往復しても再現される。
void ProjectIoTest::actionsBindingsVariablesRoundTripThroughBridge()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    // widget に actions / bindings を QVariantList of QVariantMap で添える。
    QVariantMap action;
    action.insert("trigger", "onClick");
    action.insert("op", "toggleVariable");
    action.insert("target", "running");
    action.insert("value", "");

    QVariantMap binding;
    binding.insert("property", "backgroundColor");
    binding.insert("variable", "runColor");

    QVariantMap w = makeWidgetVariant("btn001", 0, 0, 120, 40, "Run", "PLC.RUN");
    w.insert("actions", QVariantList{ action });
    w.insert("bindings", QVariantList{ binding });

    // Project レベルの変数定義。
    QVariantMap var1;
    var1.insert("name", "running");
    var1.insert("type", "bool");
    var1.insert("initial", "false");

    ProjectIo io;
    const QUrl url = urlForFile(dir, "actions.json");
    QVERIFY(io.save(url, "Sample", "Main", QVariantList{ w }, QVariantList{ var1 }));

    const QVariantMap result = io.load(url);
    QCOMPARE(result.value("ok").toBool(), true);

    // 変数定義が往復する。
    const QVariantList vars = result.value("variables").toList();
    QCOMPARE(vars.size(), 1);
    QCOMPARE(vars.at(0).toMap().value("name").toString(), QStringLiteral("running"));
    QCOMPARE(vars.at(0).toMap().value("type").toString(), QStringLiteral("bool"));
    QCOMPARE(vars.at(0).toMap().value("initial").toString(), QStringLiteral("false"));

    // widget のアクション / バインディングが往復する。
    const QVariantList widgets = result.value("widgets").toList();
    QCOMPARE(widgets.size(), 1);
    const QVariantMap w0 = widgets.at(0).toMap();

    const QVariantList actions = w0.value("actions").toList();
    QCOMPARE(actions.size(), 1);
    QCOMPARE(actions.at(0).toMap().value("op").toString(), QStringLiteral("toggleVariable"));
    QCOMPARE(actions.at(0).toMap().value("target").toString(), QStringLiteral("running"));

    const QVariantList bindings = w0.value("bindings").toList();
    QCOMPARE(bindings.size(), 1);
    QCOMPARE(bindings.at(0).toMap().value("property").toString(), QStringLiteral("backgroundColor"));
    QCOMPARE(bindings.at(0).toMap().value("variable").toString(), QStringLiteral("runColor"));
}

// Phase 7 / MB-1: QML 側の variable.source（接続詳細インライン）が C++ ブリッジ
//（save: connections[] へ dedup 集約 + source は id 参照に絞る / load: connections[] を
// 引いて source へ接続詳細を戻す）を往復しても再現されることを固定する。
void ProjectIoTest::variableSourceRoundTripsThroughBridge()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    // QML 側の編集モデルを模す：source に接続詳細をインラインで持つ。
    QVariantMap source;
    source.insert("connection", "plc1");
    source.insert("host", "192.168.0.10");
    source.insert("port", 502);
    source.insert("unitId", 1);
    source.insert("reg", "holding");
    source.insert("address", 0);
    source.insert("poll", 1000);

    QVariantMap var;
    var.insert("name", "tankLevel");
    var.insert("type", "int");
    var.insert("initial", "0");
    var.insert("source", source);

    ProjectIo io;
    const QUrl url = urlForFile(dir, "source.json");
    QVERIFY(io.save(url, "Sample", "Main", QVariantList{}, QVariantList{ var }));

    const QVariantMap result = io.load(url);
    QCOMPARE(result.value("ok").toBool(), true);

    const QVariantList vars = result.value("variables").toList();
    QCOMPARE(vars.size(), 1);
    const QVariantMap loadedVar = vars.at(0).toMap();
    QCOMPARE(loadedVar.value("name").toString(), QStringLiteral("tankLevel"));

    // load 側で source に接続詳細が戻っている（Editor UI が再表示できる）。
    const QVariantMap loadedSource = loadedVar.value("source").toMap();
    QCOMPARE(loadedSource.value("connection").toString(), QStringLiteral("plc1"));
    QCOMPARE(loadedSource.value("reg").toString(), QStringLiteral("holding"));
    QCOMPARE(loadedSource.value("address").toInt(), 0);   // 0 ベース正準
    QCOMPARE(loadedSource.value("poll").toInt(), 1000);
    QCOMPARE(loadedSource.value("host").toString(), QStringLiteral("192.168.0.10"));
    QCOMPARE(loadedSource.value("port").toInt(), 502);
    QCOMPARE(loadedSource.value("unitId").toInt(), 1);
}

// Phase 7 / MB-1: ディスク上の JSON が計画書の正準形（connections[] 参照方式）になる。
// 同一接続を指す複数変数は connections[] に 1 件だけ dedup され、各 variable.source は
// 接続詳細（host 等）を持たず connection id だけを持つ。
void ProjectIoTest::saveAggregatesConnectionsFromSources()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    auto makeVar = [](const QString &name, const QString &reg, int address) {
        QVariantMap source;
        source.insert("connection", "plc1");
        source.insert("host", "192.168.0.10");
        source.insert("port", 502);
        source.insert("unitId", 1);
        source.insert("reg", reg);
        source.insert("address", address);
        source.insert("poll", 1000);
        QVariantMap var;
        var.insert("name", name);
        var.insert("type", "int");
        var.insert("initial", "0");
        var.insert("source", source);
        return var;
    };

    ProjectIo io;
    const QString path = dir.filePath("aggregate.json");
    QVERIFY(io.save(QUrl::fromLocalFile(path), "Sample", "Main", QVariantList{},
                    QVariantList{ makeVar("a", "holding", 0), makeVar("b", "input", 1) }));

    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly | QIODevice::Text));
    const QByteArray bytes = file.readAll();
    file.close();

    const QJsonDocument doc = QJsonDocument::fromJson(bytes);
    QVERIFY(doc.isObject());
    const QJsonObject root = doc.object();

    // connections[] は 1 件（同一 id を dedup）。
    const QJsonArray conns = root.value("connections").toArray();
    QCOMPARE(conns.size(), 1);
    QCOMPARE(conns.at(0).toObject().value("id").toString(), QStringLiteral("plc1"));
    QCOMPARE(conns.at(0).toObject().value("host").toString(), QStringLiteral("192.168.0.10"));
    QCOMPARE(conns.at(0).toObject().value("port").toInt(), 502);

    // 各 variable.source は接続詳細を持たず id 参照のみ。
    const QJsonArray vars = root.value("variables").toArray();
    QCOMPARE(vars.size(), 2);
    for (const QJsonValue &v : vars) {
        const QJsonObject srcObj = v.toObject().value("source").toObject();
        QCOMPARE(srcObj.value("connection").toString(), QStringLiteral("plc1"));
        QVERIFY(!srcObj.contains("host"));  // 接続詳細は connections[] へ集約
        QVERIFY(!srcObj.contains("port"));
        QVERIFY(!srcObj.contains("unitId"));
    }
}

// Phase 7 / MB-1: source を持たない変数は内部変数のまま（後方互換）。
// connections[] は生成されず、load 側で source キーも付かない。
void ProjectIoTest::variableWithoutSourceStaysInternal()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());

    QVariantMap var;
    var.insert("name", "running");
    var.insert("type", "bool");
    var.insert("initial", "false");
    // source キー無し（内部変数）。

    ProjectIo io;
    const QString path = dir.filePath("internal.json");
    QVERIFY(io.save(QUrl::fromLocalFile(path), "Sample", "Main", QVariantList{},
                    QVariantList{ var }));

    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly | QIODevice::Text));
    const QByteArray bytes = file.readAll();
    file.close();
    const QJsonObject root = QJsonDocument::fromJson(bytes).object();
    QVERIFY(!root.contains("connections"));  // 接続なし
    QVERIFY(!root.value("variables").toArray().at(0).toObject().contains("source"));

    const QVariantMap result = io.load(QUrl::fromLocalFile(path));
    QCOMPARE(result.value("ok").toBool(), true);
    const QVariantMap loadedVar = result.value("variables").toList().at(0).toMap();
    QVERIFY(!loadedVar.contains("source"));
}

QTEST_APPLESS_MAIN(ProjectIoTest)
#include "tst_project_io.moc"
