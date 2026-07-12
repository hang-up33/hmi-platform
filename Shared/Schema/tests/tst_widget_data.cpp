#include "hmi/schema/WidgetData.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QTest>

using hmi::schema::ActionData;
using hmi::schema::BindingData;
using hmi::schema::TrendSeriesData;
using hmi::schema::WidgetData;

namespace {

QJsonObject validWidgetJson()
{
    QJsonObject obj;
    obj["id"] = "btn001";
    obj["type"] = "Button";
    obj["x"] = 10;
    obj["y"] = 20;
    obj["width"] = 120;
    obj["height"] = 40;
    obj["text"] = "Start";
    obj["tag"] = "PLC.START";
    return obj;
}

} // namespace

class WidgetDataTest : public QObject
{
    Q_OBJECT

private slots:
    void roundTripFullFields();
    void roundTripOmitsEmptyTextAndTag();
    void roundTripOmitsDefaultStyleFields();
    void roundTripOmitsUnspecifiedBorderRadius();
    void zeroBorderWidthAndRadiusAreWrittenNotOmitted();
    void roundTripOmitsDefaultFontDetails();
    void trueFontFlagsAreWrittenFalseAreOmitted();
    void roundTripOmitsDefaultAlignOpacity();
    void zeroOpacityIsWrittenNotOmitted();
    void roundTripOmitsDefaultStates();
    void nonDefaultStatesAreWrittenAndRestored();
    // Task 54: 数値範囲 min/max（presence フラグ方式）の round-trip と、キー欠落時の
    // has*=false（後方互換）を固定する。負値が正当なので数値センチネル不可＝presence フラグ。
    void minMaxRoundTrip();
    void minMaxOmittedWhenUnspecified();
    void negativeMinMaxRoundTrip();
    // Task T-A（Phase 8）: Trend 固有フィールドの round-trip。pointCount / lineColor / sampleMs
    //（`0`/空センチネル）と yMin/yMax（presence フラグ方式・負値含む）の往復、および presence
    // false 時に yMin/yMax キーが現れない（後方互換）ことを固定する。
    void trendFieldsRoundTrip();
    void trendYAxisOmittedWhenUnspecified();
    void negativeTrendYAxisRoundTrip();
    // Task 8B-A（Phase 8-B）: Trend 拡張（複数系列 + 軸目盛り/凡例）の round-trip。
    // series（子型配列）+ showGrid/showLegend（既定 false の bool optional）+ yTickCount
    //（`0` センチネル）の往復、空 series + 既定フラグの省略（後方互換）、series の検証を固定する。
    void trendSeriesAndFlagsRoundTrip();
    void trendSeriesAndFlagsOmittedWhenEmpty();
    void isValidJsonRejectsInvalidSeries();
    // Task M-A（Phase 10）: Meter 固有フィールドの round-trip。meterMin/meterMax（presence
    // フラグ方式・負値含む）と arcColor/needleColor/tickCount/unit（空/`0` センチネル）の往復、
    // presence false 時に meterMin/meterMax キーが現れない（後方互換）ことを固定する。
    void meterFieldsRoundTrip();
    void meterRangeOmittedWhenUnspecified();
    void negativeMeterRangeRoundTrip();
    void actionsAndBindingsRoundTrip();
    void omitsEmptyActionsAndBindings();
    void isValidJsonRejectsInvalidActionsBindings();
    void fromJsonFillsDefaultsForMissingKeys();

    // C++ ブリッジ集約（refactoring）：QVariantMap 往復の全フィールド round-trip と、
    // キー欠落時のセンチネル既定（-1 / true）の充足を固定する。
    void variantMapRoundTripFullFields();
    void fromVariantMapFillsSentinelDefaults();
    void fromVariantMapNormalizesEmptyActionTrigger();

    void isValidJsonAcceptsMinimumRequiredFields();
    void isValidJsonRejectsMissingRequired_data();
    void isValidJsonRejectsMissingRequired();
    void isValidJsonRejectsWrongTypes_data();
    void isValidJsonRejectsWrongTypes();
};

void WidgetDataTest::roundTripFullFields()
{
    WidgetData src;
    src.id = "btn001";
    src.type = "Button";
    src.x = 10;
    src.y = 20;
    src.width = 120;
    src.height = 40;
    src.text = "Start";
    src.tag = "PLC.START";
    src.backgroundColor = "#ff0000";
    src.textColor = "#00ff00";
    src.fontSize = 22;
    src.borderColor = "#112233";
    src.borderWidth = 3;
    src.radius = 8;
    src.fontBold = true;
    src.fontItalic = true;
    src.fontFamily = "Courier New";
    src.hAlign = "left";
    src.vAlign = "top";
    src.opacity = 0.5;
    src.pointCount = 120;
    src.yMin = 0.0;
    src.yMax = 100.0;
    src.hasYMin = true;
    src.hasYMax = true;
    src.lineColor = "#4cc9f0";
    src.sampleMs = 250;

    const QJsonObject obj = src.toJson();
    const WidgetData restored = WidgetData::fromJson(obj);

    QCOMPARE(restored.id, src.id);
    QCOMPARE(restored.type, src.type);
    QCOMPARE(restored.x, src.x);
    QCOMPARE(restored.y, src.y);
    QCOMPARE(restored.width, src.width);
    QCOMPARE(restored.height, src.height);
    QCOMPARE(restored.text, src.text);
    QCOMPARE(restored.tag, src.tag);
    QCOMPARE(restored.backgroundColor, src.backgroundColor);
    QCOMPARE(restored.textColor, src.textColor);
    QCOMPARE(restored.fontSize, src.fontSize);
    QCOMPARE(restored.borderColor, src.borderColor);
    QCOMPARE(restored.borderWidth, src.borderWidth);
    QCOMPARE(restored.radius, src.radius);
    QCOMPARE(restored.fontBold, src.fontBold);
    QCOMPARE(restored.fontItalic, src.fontItalic);
    QCOMPARE(restored.fontFamily, src.fontFamily);
    QCOMPARE(restored.hAlign, src.hAlign);
    QCOMPARE(restored.vAlign, src.vAlign);
    QCOMPARE(restored.opacity, src.opacity);
    QCOMPARE(restored.pointCount, src.pointCount);
    QCOMPARE(restored.hasYMin, src.hasYMin);
    QCOMPARE(restored.hasYMax, src.hasYMax);
    QCOMPARE(restored.yMin, src.yMin);
    QCOMPARE(restored.yMax, src.yMax);
    QCOMPARE(restored.lineColor, src.lineColor);
    QCOMPARE(restored.sampleMs, src.sampleMs);
}

// Task 31: ボーダー＋角丸は未指定（色は空、数値は -1 センチネル）のとき toJson で
// 省略され、旧 JSON と後方互換になることを固定する（Task 28 の style 省略テストと対）。
void WidgetDataTest::roundTripOmitsUnspecifiedBorderRadius()
{
    WidgetData src;
    src.id = "btn004";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    // borderColor は既定の空、borderWidth / radius は既定の -1（未指定）。

    const QJsonObject obj = src.toJson();

    QVERIFY(!obj.contains("borderColor"));
    QVERIFY(!obj.contains("borderWidth"));
    QVERIFY(!obj.contains("radius"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QVERIFY(restored.borderColor.isEmpty());
    QCOMPARE(restored.borderWidth, -1);
    QCOMPARE(restored.radius, -1);
}

// Task 31 の新規ポイント：borderWidth=0（ボーダーなし）/ radius=0（角丸なし）は
// **正当値**であり、fontSize（0 = 未指定）と違って toJson で省略してはいけない。
// `>= 0` で書き出し、読み戻しても 0 のまま保たれることを固定する（`> 0` への
// デグレ＝0 を未指定扱いして落とす回帰を検出する）。
void WidgetDataTest::zeroBorderWidthAndRadiusAreWrittenNotOmitted()
{
    WidgetData src;
    src.id = "btn005";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    src.borderWidth = 0;
    src.radius = 0;

    const QJsonObject obj = src.toJson();

    QVERIFY(obj.contains("borderWidth"));
    QVERIFY(obj.contains("radius"));
    QCOMPARE(obj.value("borderWidth").toInt(-1), 0);
    QCOMPARE(obj.value("radius").toInt(-1), 0);

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.borderWidth, 0);
    QCOMPARE(restored.radius, 0);
}

// Task 33: フォント詳細は既定値（bold/italic=false、family=空 = 未指定）のとき
// toJson で省略され、旧 JSON と後方互換になることを固定する（Task 28/31 の省略テストと対）。
void WidgetDataTest::roundTripOmitsDefaultFontDetails()
{
    WidgetData src;
    src.id = "btn006";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    // fontBold / fontItalic は既定 false、fontFamily は既定の空（未指定）。

    const QJsonObject obj = src.toJson();

    QVERIFY(!obj.contains("fontBold"));
    QVERIFY(!obj.contains("fontItalic"));
    QVERIFY(!obj.contains("fontFamily"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.fontBold, false);
    QCOMPARE(restored.fontItalic, false);
    QVERIFY(restored.fontFamily.isEmpty());
}

// Task 33 の新規ポイント：bool は **既定値（false）と異なる時だけ書き出す**。
// true は書き、false は省略する。fontBold=true / fontItalic=false の片側ケースで
// 「true だけ書かれ false は省略され、読み戻しても保たれる」ことを固定する。
void WidgetDataTest::trueFontFlagsAreWrittenFalseAreOmitted()
{
    WidgetData src;
    src.id = "btn007";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    src.fontBold = true;     // 書かれる
    src.fontItalic = false;  // 省略される

    const QJsonObject obj = src.toJson();

    QVERIFY(obj.contains("fontBold"));
    QCOMPARE(obj.value("fontBold").toBool(), true);
    QVERIFY(!obj.contains("fontItalic"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.fontBold, true);
    QCOMPARE(restored.fontItalic, false);
}

// Task 34: 配置 + 不透明度は既定値（hAlign/vAlign=空 = 未指定、opacity=-1 = 未指定）
// のとき toJson で省略され、旧 JSON と後方互換になることを固定する（Task 28/31/33 の対）。
void WidgetDataTest::roundTripOmitsDefaultAlignOpacity()
{
    WidgetData src;
    src.id = "btn008";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    // hAlign / vAlign は既定の空（未指定）、opacity は既定 -1（未指定）。

    const QJsonObject obj = src.toJson();

    QVERIFY(!obj.contains("hAlign"));
    QVERIFY(!obj.contains("vAlign"));
    QVERIFY(!obj.contains("opacity"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QVERIFY(restored.hAlign.isEmpty());
    QVERIFY(restored.vAlign.isEmpty());
    QCOMPARE(restored.opacity, -1.0);
}

// Task 34 の新規ポイント：opacity は **real センチネル**（-1 = 未指定）。`0.0`（完全透明）は
// 正当値であり、borderWidth=0 と同じく **省略されず書き出される**ことを固定する
// （zeroBorderWidthAndRadius の real 版）。
void WidgetDataTest::zeroOpacityIsWrittenNotOmitted()
{
    WidgetData src;
    src.id = "btn009";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    src.opacity = 0.0;  // 完全透明（正当値）。-1 でないので書き出される。

    const QJsonObject obj = src.toJson();

    QVERIFY(obj.contains("opacity"));
    QCOMPARE(obj.value("opacity").toDouble(), 0.0);

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.opacity, 0.0);
}

// Task 42: 状態別スタイルが既定値（enabled=true / checkable=false / checked=false）の
// とき toJson で省略され、fromJson が既定へ復元することを固定する。**特に enabled は
// 既定 true なので省略され、欠落時 true で読み戻される**（旧 JSON 後方互換）。
void WidgetDataTest::roundTripOmitsDefaultStates()
{
    WidgetData src;
    src.id = "btn012";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    // enabled=true / checkable=false / checked=false は既定。

    const QJsonObject obj = src.toJson();

    QVERIFY(!obj.contains("enabled"));
    QVERIFY(!obj.contains("checkable"));
    QVERIFY(!obj.contains("checked"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.enabled, true);
    QCOMPARE(restored.checkable, false);
    QCOMPARE(restored.checked, false);
}

// Task 42 の新規ポイント：**enabled=false は既定 true と異なるので書き出され、round-trip で
// 保たれる**（既定 true のフラグを一律 true 書き出しすると false が失われる罠を防ぐ）。
// checkable=true / checked=true も同様に書かれ復元される。
void WidgetDataTest::nonDefaultStatesAreWrittenAndRestored()
{
    WidgetData src;
    src.id = "btn013";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    src.enabled = false;    // 既定 true と異なる → 書かれる
    src.checkable = true;   // 既定 false と異なる → 書かれる
    src.checked = true;     // 既定 false と異なる → 書かれる

    const QJsonObject obj = src.toJson();

    QVERIFY(obj.contains("enabled"));
    QCOMPARE(obj.value("enabled").toBool(), false);
    QVERIFY(obj.contains("checkable"));
    QCOMPARE(obj.value("checkable").toBool(), true);
    QVERIFY(obj.contains("checked"));
    QCOMPARE(obj.value("checked").toBool(), true);

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.enabled, false);
    QCOMPARE(restored.checkable, true);
    QCOMPARE(restored.checked, true);
}

// Task 54: 数値範囲（min/max）の round-trip。presence フラグ（hasMinValue/hasMaxValue）が
// true のとき minValue/maxValue が JSON に書かれ、fromJson でキーの有無から presence を復元する。
void WidgetDataTest::minMaxRoundTrip()
{
    WidgetData src;
    src.id = "num001";
    src.type = "NumericField";
    src.width = 120;
    src.height = 40;
    src.minValue = 0.0;     // 0 も正当値（has* で指定済みなので書かれる）
    src.maxValue = 100.5;   // real 境界も表せる
    src.hasMinValue = true;
    src.hasMaxValue = true;

    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("minValue"));
    QVERIFY(obj.contains("maxValue"));
    QCOMPARE(obj.value("minValue").toDouble(), 0.0);
    QCOMPARE(obj.value("maxValue").toDouble(), 100.5);

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.hasMinValue, true);
    QCOMPARE(restored.hasMaxValue, true);
    QCOMPARE(restored.minValue, 0.0);
    QCOMPARE(restored.maxValue, 100.5);
}

// Task 54: 未指定（has*=false）のとき min/max キーは省略され、旧 JSON（min/max キー無し）を
// 読むと has*=false に復元される（後方互換）。数値センチネルが使えない＝キーの有無が唯一の真実。
void WidgetDataTest::minMaxOmittedWhenUnspecified()
{
    WidgetData src;
    src.id = "num002";
    src.type = "NumericField";
    src.width = 120;
    src.height = 40;
    // hasMinValue / hasMaxValue は既定 false（未指定）。

    const QJsonObject obj = src.toJson();
    QVERIFY(!obj.contains("minValue"));
    QVERIFY(!obj.contains("maxValue"));

    // 旧 JSON（min/max キー無し）を読んでも has*=false で復元される。
    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.hasMinValue, false);
    QCOMPARE(restored.hasMaxValue, false);
}

// Task 54: 負値の min/max が round-trip する（センチネル方式では `-1` 等が未指定と衝突して
// 表せないが、presence フラグ方式なら負値も正当値として保存・復元できる）。
void WidgetDataTest::negativeMinMaxRoundTrip()
{
    WidgetData src;
    src.id = "num003";
    src.type = "NumericField";
    src.width = 120;
    src.height = 40;
    src.minValue = -100.0;  // 負の下限（センチネルでは表せない）
    src.maxValue = -1.0;    // -1 も正当値（presence フラグなので未指定と区別される）
    src.hasMinValue = true;
    src.hasMaxValue = true;

    const QJsonObject obj = src.toJson();
    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.hasMinValue, true);
    QCOMPARE(restored.hasMaxValue, true);
    QCOMPARE(restored.minValue, -100.0);
    QCOMPARE(restored.maxValue, -1.0);
}

// Task T-A（Phase 8）: Trend 固有フィールドの round-trip（JSON / QVariantMap 両方）。
// pointCount / lineColor / sampleMs（`0`/空センチネル）と yMin/yMax（presence フラグ true 側）が
// 往復で保たれることを固定する。
void WidgetDataTest::trendFieldsRoundTrip()
{
    WidgetData src;
    src.id = "trend001";
    src.type = "Trend";
    src.width = 320;
    src.height = 160;
    src.pointCount = 120;
    src.yMin = 0.0;     // 0 も正当値（has* で指定済みなので書かれる）
    src.yMax = 100.0;
    src.hasYMin = true;
    src.hasYMax = true;
    src.lineColor = "#4cc9f0";
    src.sampleMs = 250;

    // JSON round-trip
    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("pointCount"));
    QVERIFY(obj.contains("yMin"));
    QVERIFY(obj.contains("yMax"));
    QVERIFY(obj.contains("lineColor"));
    QVERIFY(obj.contains("sampleMs"));
    // presence は yMin/yMax キーの有無で表す → hasYMin/hasYMax という JSON キーは存在しない。
    QVERIFY(!obj.contains("hasYMin"));
    QVERIFY(!obj.contains("hasYMax"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.pointCount, 120);
    QCOMPARE(restored.hasYMin, true);
    QCOMPARE(restored.hasYMax, true);
    QCOMPARE(restored.yMin, 0.0);
    QCOMPARE(restored.yMax, 100.0);
    QCOMPARE(restored.lineColor, QStringLiteral("#4cc9f0"));
    QCOMPARE(restored.sampleMs, 250);

    // QVariantMap round-trip。C++↔QML ブリッジでは min/max と同じく明示 bool キー
    // hasYMin/hasYMax を持つ（QML 側が presence 判定に使う）。
    const QVariantMap m = src.toVariantMap();
    QCOMPARE(m.value("hasYMin").toBool(), true);
    QCOMPARE(m.value("hasYMax").toBool(), true);
    const WidgetData r = WidgetData::fromVariantMap(m);
    QCOMPARE(r.pointCount, 120);
    QCOMPARE(r.hasYMin, true);
    QCOMPARE(r.hasYMax, true);
    QCOMPARE(r.yMin, 0.0);
    QCOMPARE(r.yMax, 100.0);
    QCOMPARE(r.lineColor, QStringLiteral("#4cc9f0"));
    QCOMPARE(r.sampleMs, 250);
}

// Task T-A（Phase 8）: Trend の未指定（pointCount/sampleMs=0、lineColor=空、hasY*=false）の
// とき、pointCount/yMin/yMax/lineColor/sampleMs キーが JSON で省略され（後方互換）、
// QVariantMap では presence bool（hasYMin/hasYMax）が false になることを固定する。
void WidgetDataTest::trendYAxisOmittedWhenUnspecified()
{
    WidgetData src;
    src.id = "trend002";
    src.type = "Trend";
    src.width = 320;
    src.height = 160;
    // pointCount / sampleMs は既定 0、lineColor は既定の空、hasYMin / hasYMax は既定 false。

    const QJsonObject obj = src.toJson();
    QVERIFY(!obj.contains("pointCount"));
    QVERIFY(!obj.contains("yMin"));
    QVERIFY(!obj.contains("yMax"));
    QVERIFY(!obj.contains("lineColor"));
    QVERIFY(!obj.contains("sampleMs"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.pointCount, 0);
    QCOMPARE(restored.hasYMin, false);
    QCOMPARE(restored.hasYMax, false);
    QVERIFY(restored.lineColor.isEmpty());
    QCOMPARE(restored.sampleMs, 0);

    // QVariantMap では presence bool が false（min/max と同じ。値キーは常に入るが has*=false）。
    const QVariantMap m = src.toVariantMap();
    QCOMPARE(m.value("hasYMin").toBool(), false);
    QCOMPARE(m.value("hasYMax").toBool(), false);
    const WidgetData r = WidgetData::fromVariantMap(m);
    QCOMPARE(r.hasYMin, false);
    QCOMPARE(r.hasYMax, false);
}

// Task T-A（Phase 8）: 負値の yMin/yMax が round-trip する（presence フラグ方式なので
// `-1` 等の負値も正当値として保存・復元できる。minValue/maxValue の前例と同じ）。
void WidgetDataTest::negativeTrendYAxisRoundTrip()
{
    WidgetData src;
    src.id = "trend003";
    src.type = "Trend";
    src.width = 320;
    src.height = 160;
    src.yMin = -50.0;   // 負の下限（センチネルでは表せない）
    src.yMax = -1.0;    // -1 も正当値（presence フラグなので未指定と区別される）
    src.hasYMin = true;
    src.hasYMax = true;

    const QJsonObject obj = src.toJson();
    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.hasYMin, true);
    QCOMPARE(restored.hasYMax, true);
    QCOMPARE(restored.yMin, -50.0);
    QCOMPARE(restored.yMax, -1.0);

    const QVariantMap m = src.toVariantMap();
    const WidgetData r = WidgetData::fromVariantMap(m);
    QCOMPARE(r.hasYMin, true);
    QCOMPARE(r.hasYMax, true);
    QCOMPARE(r.yMin, -50.0);
    QCOMPARE(r.yMax, -1.0);
}

// Task M-A（Phase 10）: Meter 固有フィールドの round-trip（presence フラグ true 側 + 空/`0`
// センチネル）。meterMin/meterMax（値 + presence）と arcColor/needleColor/tickCount/unit が
// JSON / QVariantMap 両方で往復し、JSON は presence をキーの有無で表す（hasMeter* キー無し）
// ことを固定する。
void WidgetDataTest::meterFieldsRoundTrip()
{
    WidgetData src;
    src.id = "meter001";
    src.type = "Meter";
    src.width = 200;
    src.height = 200;
    src.meterMin = 0.0;     // 0 も正当値（has* で指定済みなので書かれる）
    src.meterMax = 180.0;
    src.hasMeterMin = true;
    src.hasMeterMax = true;
    src.arcColor = "#4cc9f0";
    src.needleColor = "#ff595e";
    src.tickCount = 10;
    src.unit = "km/h";

    // JSON round-trip
    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("meterMin"));
    QVERIFY(obj.contains("meterMax"));
    QVERIFY(obj.contains("arcColor"));
    QVERIFY(obj.contains("needleColor"));
    QVERIFY(obj.contains("tickCount"));
    QVERIFY(obj.contains("unit"));
    // presence は meterMin/meterMax キーの有無で表す → hasMeter* という JSON キーは存在しない。
    QVERIFY(!obj.contains("hasMeterMin"));
    QVERIFY(!obj.contains("hasMeterMax"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.hasMeterMin, true);
    QCOMPARE(restored.hasMeterMax, true);
    QCOMPARE(restored.meterMin, 0.0);
    QCOMPARE(restored.meterMax, 180.0);
    QCOMPARE(restored.arcColor, QStringLiteral("#4cc9f0"));
    QCOMPARE(restored.needleColor, QStringLiteral("#ff595e"));
    QCOMPARE(restored.tickCount, 10);
    QCOMPARE(restored.unit, QStringLiteral("km/h"));

    // QVariantMap round-trip。C++↔QML ブリッジでは min/max・yMin/yMax と同じく明示 bool キー
    // hasMeterMin/hasMeterMax を持つ（QML 側が presence 判定に使う）。
    const QVariantMap m = src.toVariantMap();
    QCOMPARE(m.value("hasMeterMin").toBool(), true);
    QCOMPARE(m.value("hasMeterMax").toBool(), true);
    const WidgetData r = WidgetData::fromVariantMap(m);
    QCOMPARE(r.hasMeterMin, true);
    QCOMPARE(r.hasMeterMax, true);
    QCOMPARE(r.meterMin, 0.0);
    QCOMPARE(r.meterMax, 180.0);
    QCOMPARE(r.arcColor, QStringLiteral("#4cc9f0"));
    QCOMPARE(r.needleColor, QStringLiteral("#ff595e"));
    QCOMPARE(r.tickCount, 10);
    QCOMPARE(r.unit, QStringLiteral("km/h"));
}

// Task M-A（Phase 10）: Meter の未指定（hasMeter*=false、arcColor/needleColor/unit=空、
// tickCount=0）のとき、meterMin/meterMax/arcColor/needleColor/tickCount/unit キーが JSON で
// 省略され（後方互換）、QVariantMap では presence bool（hasMeter*）が false になることを固定する。
void WidgetDataTest::meterRangeOmittedWhenUnspecified()
{
    WidgetData src;
    src.id = "meter002";
    src.type = "Meter";
    src.width = 200;
    src.height = 200;
    // meterMin/meterMax は既定 presence false、arcColor/needleColor/unit は空、tickCount は 0。

    const QJsonObject obj = src.toJson();
    QVERIFY(!obj.contains("meterMin"));
    QVERIFY(!obj.contains("meterMax"));
    QVERIFY(!obj.contains("arcColor"));
    QVERIFY(!obj.contains("needleColor"));
    QVERIFY(!obj.contains("tickCount"));
    QVERIFY(!obj.contains("unit"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.hasMeterMin, false);
    QCOMPARE(restored.hasMeterMax, false);
    QVERIFY(restored.arcColor.isEmpty());
    QVERIFY(restored.needleColor.isEmpty());
    QCOMPARE(restored.tickCount, 0);
    QVERIFY(restored.unit.isEmpty());

    // QVariantMap では presence bool が false（min/max と同じ。値キーは常に入るが has*=false）。
    const QVariantMap m = src.toVariantMap();
    QCOMPARE(m.value("hasMeterMin").toBool(), false);
    QCOMPARE(m.value("hasMeterMax").toBool(), false);
    const WidgetData r = WidgetData::fromVariantMap(m);
    QCOMPARE(r.hasMeterMin, false);
    QCOMPARE(r.hasMeterMax, false);
}

// Task M-A（Phase 10）: 負値の meterMin/meterMax が round-trip する（presence フラグ方式なので
// `-20` 等の負値も正当値として保存・復元できる。yMin/yMax の前例と同じ）。
void WidgetDataTest::negativeMeterRangeRoundTrip()
{
    WidgetData src;
    src.id = "meter003";
    src.type = "Meter";
    src.width = 200;
    src.height = 200;
    src.meterMin = -20.0;   // 負の下限（センチネルでは表せない）
    src.meterMax = -1.0;    // -1 も正当値（presence フラグなので未指定と区別される）
    src.hasMeterMin = true;
    src.hasMeterMax = true;

    const QJsonObject obj = src.toJson();
    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.hasMeterMin, true);
    QCOMPARE(restored.hasMeterMax, true);
    QCOMPARE(restored.meterMin, -20.0);
    QCOMPARE(restored.meterMax, -1.0);

    const QVariantMap m = src.toVariantMap();
    const WidgetData r = WidgetData::fromVariantMap(m);
    QCOMPARE(r.hasMeterMin, true);
    QCOMPARE(r.hasMeterMax, true);
    QCOMPARE(r.meterMin, -20.0);
    QCOMPARE(r.meterMax, -1.0);
}

// Task 8B-A（Phase 8-B）: 複数系列（series）+ 軸目盛り/凡例フラグの round-trip（JSON / QVariantMap 両方）。
void WidgetDataTest::trendSeriesAndFlagsRoundTrip()
{
    WidgetData src;
    src.id = "trend010";
    src.type = "Trend";
    src.width = 360;
    src.height = 180;
    src.showGrid = true;
    src.showLegend = true;
    src.yTickCount = 5;
    TrendSeriesData s0;
    s0.variable = "sensorTemp";
    s0.color = "#4cc9f0";
    s0.label = "Temp";
    TrendSeriesData s1;
    s1.variable = "sensorPressure";  // color / label は省略（未指定）
    src.series.append(s0);
    src.series.append(s1);

    // JSON round-trip
    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("series"));
    QVERIFY(obj.contains("showGrid"));
    QVERIFY(obj.contains("showLegend"));
    QVERIFY(obj.contains("yTickCount"));
    QCOMPARE(obj.value("series").toArray().size(), 2);
    // s1 は color / label 未指定 → そのキーは省略される（子型 toJson の規則）。
    const QJsonObject s1obj = obj.value("series").toArray().at(1).toObject();
    QVERIFY(s1obj.contains("variable"));
    QVERIFY(!s1obj.contains("color"));
    QVERIFY(!s1obj.contains("label"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.series.size(), 2);
    QCOMPARE(restored.series.at(0).variable, QStringLiteral("sensorTemp"));
    QCOMPARE(restored.series.at(0).color, QStringLiteral("#4cc9f0"));
    QCOMPARE(restored.series.at(0).label, QStringLiteral("Temp"));
    QCOMPARE(restored.series.at(1).variable, QStringLiteral("sensorPressure"));
    QVERIFY(restored.series.at(1).color.isEmpty());
    QVERIFY(restored.series.at(1).label.isEmpty());
    QCOMPARE(restored.showGrid, true);
    QCOMPARE(restored.showLegend, true);
    QCOMPARE(restored.yTickCount, 5);

    // QVariantMap round-trip
    const QVariantMap m = src.toVariantMap();
    QCOMPARE(m.value("series").toList().size(), 2);
    QCOMPARE(m.value("showGrid").toBool(), true);
    QCOMPARE(m.value("showLegend").toBool(), true);
    QCOMPARE(m.value("yTickCount").toInt(), 5);
    const WidgetData r = WidgetData::fromVariantMap(m);
    QCOMPARE(r.series.size(), 2);
    QCOMPARE(r.series.at(0).variable, QStringLiteral("sensorTemp"));
    QCOMPARE(r.series.at(0).color, QStringLiteral("#4cc9f0"));
    QCOMPARE(r.series.at(1).variable, QStringLiteral("sensorPressure"));
    QCOMPARE(r.showGrid, true);
    QCOMPARE(r.showLegend, true);
    QCOMPARE(r.yTickCount, 5);
}

// Task 8B-A（Phase 8-B）: series 空 + 既定フラグ（showGrid/showLegend=false、yTickCount=0）の
// とき、series/showGrid/showLegend/yTickCount キーが JSON で省略される（Phase 8 単系列 JSON の後方互換）。
void WidgetDataTest::trendSeriesAndFlagsOmittedWhenEmpty()
{
    WidgetData src;
    src.id = "trend011";
    src.type = "Trend";
    src.width = 360;
    src.height = 180;
    // series は既定の空、showGrid/showLegend は既定 false、yTickCount は既定 0。

    const QJsonObject obj = src.toJson();
    QVERIFY(!obj.contains("series"));
    QVERIFY(!obj.contains("showGrid"));
    QVERIFY(!obj.contains("showLegend"));
    QVERIFY(!obj.contains("yTickCount"));

    const WidgetData r = WidgetData::fromJson(obj);
    QVERIFY(r.series.isEmpty());
    QCOMPARE(r.showGrid, false);
    QCOMPARE(r.showLegend, false);
    QCOMPARE(r.yTickCount, 0);
}

// Task 8B-A（Phase 8-B）: series は存在するなら配列 + 各要素が子型として有効（variable 非空）で
// あることを isValidJson が要求する（不在は後方互換で許容）。
void WidgetDataTest::isValidJsonRejectsInvalidSeries()
{
    QJsonObject base;
    base["id"] = "trend001";
    base["type"] = "Trend";
    base["width"] = 360;
    base["height"] = 180;
    QVERIFY(WidgetData::isValidJson(base));

    // series が配列でない → 無効。
    {
        QJsonObject obj = base;
        obj["series"] = QStringLiteral("not-an-array");
        QVERIFY(!WidgetData::isValidJson(obj));
    }
    // series 要素に variable が無い → 無効。
    {
        QJsonObject badSeries;
        badSeries["color"] = "#4cc9f0";  // variable 欠落
        QJsonObject obj = base;
        obj["series"] = QJsonArray{ badSeries };
        QVERIFY(!WidgetData::isValidJson(obj));
    }
    // 妥当な series は有効。
    {
        QJsonObject series;
        series["variable"] = "sensorTemp";
        QJsonObject obj = base;
        obj["series"] = QJsonArray{ series };
        QVERIFY(WidgetData::isValidJson(obj));
    }
}

// Task 39: アクション / バインディング配列が round-trip で要素ごと再現される。
void WidgetDataTest::actionsAndBindingsRoundTrip()
{
    WidgetData src;
    src.id = "btn010";
    src.type = "Button";
    src.width = 120;
    src.height = 40;

    ActionData a;
    a.trigger = "onClick";
    a.op = "toggleVariable";
    a.target = "running";
    a.value = "";
    src.actions.append(a);

    BindingData b;
    b.property = "backgroundColor";
    b.variable = "runColor";
    src.bindings.append(b);

    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("actions"));
    QVERIFY(obj.contains("bindings"));

    const WidgetData r = WidgetData::fromJson(obj);
    QCOMPARE(r.actions.size(), 1);
    QCOMPARE(r.actions.at(0).trigger, QStringLiteral("onClick"));
    QCOMPARE(r.actions.at(0).op, QStringLiteral("toggleVariable"));
    QCOMPARE(r.actions.at(0).target, QStringLiteral("running"));
    QCOMPARE(r.bindings.size(), 1);
    QCOMPARE(r.bindings.at(0).property, QStringLiteral("backgroundColor"));
    QCOMPARE(r.bindings.at(0).variable, QStringLiteral("runColor"));
}

// Task 39: アクション / バインディングが空のとき toJson で省略され、後方互換になる。
void WidgetDataTest::omitsEmptyActionsAndBindings()
{
    WidgetData src;
    src.id = "btn011";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    // actions / bindings は既定の空。

    const QJsonObject obj = src.toJson();
    QVERIFY(!obj.contains("actions"));
    QVERIFY(!obj.contains("bindings"));

    const WidgetData r = WidgetData::fromJson(obj);
    QVERIFY(r.actions.isEmpty());
    QVERIFY(r.bindings.isEmpty());
}

// Task 39（Codex PR #78 [P2]）：actions / bindings は存在するなら配列 + 各要素が子型として
// 有効であることを isValidJson が要求する（不在は後方互換で許容）。
void WidgetDataTest::isValidJsonRejectsInvalidActionsBindings()
{
    // 基本は有効（必須集合を満たす）。
    QJsonObject base;
    base["id"] = "btn001";
    base["type"] = "Button";
    base["width"] = 120;
    base["height"] = 40;
    QVERIFY(WidgetData::isValidJson(base));

    // actions が配列でない → 無効。
    {
        QJsonObject obj = base;
        obj["actions"] = QStringLiteral("not-an-array");
        QVERIFY(!WidgetData::isValidJson(obj));
    }
    // action 要素に target が無い → 無効。
    {
        QJsonObject badAction;
        badAction["op"] = "toggleVariable";  // target 欠落
        QJsonObject obj = base;
        obj["actions"] = QJsonArray{ badAction };
        QVERIFY(!WidgetData::isValidJson(obj));
    }
    // binding 要素に variable が無い → 無効。
    {
        QJsonObject badBinding;
        badBinding["property"] = "text";  // variable 欠落
        QJsonObject obj = base;
        obj["bindings"] = QJsonArray{ badBinding };
        QVERIFY(!WidgetData::isValidJson(obj));
    }
    // 妥当な actions / bindings は有効。
    {
        QJsonObject action;
        action["op"] = "setVariable";
        action["target"] = "running";
        QJsonObject binding;
        binding["property"] = "visible";
        binding["variable"] = "running";
        QJsonObject obj = base;
        obj["actions"] = QJsonArray{ action };
        obj["bindings"] = QJsonArray{ binding };
        QVERIFY(WidgetData::isValidJson(obj));
    }
}

// Task 28: スタイル属性は既定値（空 / 0 = 未指定）のとき toJson で省略され、
// 旧 JSON と後方互換になることを固定する。
void WidgetDataTest::roundTripOmitsDefaultStyleFields()
{
    WidgetData src;
    src.id = "btn003";
    src.type = "Button";
    src.width = 120;
    src.height = 40;
    src.text = "Start";

    const QJsonObject obj = src.toJson();

    QVERIFY(!obj.contains("backgroundColor"));
    QVERIFY(!obj.contains("textColor"));
    QVERIFY(!obj.contains("fontSize"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QVERIFY(restored.backgroundColor.isEmpty());
    QVERIFY(restored.textColor.isEmpty());
    QCOMPARE(restored.fontSize, 0);
}

void WidgetDataTest::roundTripOmitsEmptyTextAndTag()
{
    WidgetData src;
    src.id = "btn002";
    src.type = "Button";
    src.width = 80;
    src.height = 30;

    const QJsonObject obj = src.toJson();

    QVERIFY(!obj.contains("text"));
    QVERIFY(!obj.contains("tag"));

    const WidgetData restored = WidgetData::fromJson(obj);
    QCOMPARE(restored.id, src.id);
    QCOMPARE(restored.type, src.type);
    QCOMPARE(restored.width, src.width);
    QCOMPARE(restored.height, src.height);
    QVERIFY(restored.text.isEmpty());
    QVERIFY(restored.tag.isEmpty());
}

void WidgetDataTest::fromJsonFillsDefaultsForMissingKeys()
{
    const QJsonObject empty;
    const WidgetData w = WidgetData::fromJson(empty);

    QVERIFY(w.id.isEmpty());
    QVERIFY(w.type.isEmpty());
    QCOMPARE(w.x, 0);
    QCOMPARE(w.y, 0);
    QCOMPARE(w.width, 0);
    QCOMPARE(w.height, 0);
    QVERIFY(w.text.isEmpty());
    QVERIFY(w.tag.isEmpty());
    QVERIFY(w.backgroundColor.isEmpty());
    QVERIFY(w.textColor.isEmpty());
    QCOMPARE(w.fontSize, 0);
    // Task 31: 数値は欠落時 -1（= 未指定センチネル）。0 に落ちると「ボーダーなし」と
    // 誤解されるため、`toInt(-1)` で読んでいることをここで固定する。
    QVERIFY(w.borderColor.isEmpty());
    QCOMPARE(w.borderWidth, -1);
    QCOMPARE(w.radius, -1);
    // Task 33: bool は欠落時 false、fontFamily は欠落時 空文字（= 未指定）。
    QCOMPARE(w.fontBold, false);
    QCOMPARE(w.fontItalic, false);
    QVERIFY(w.fontFamily.isEmpty());
    // Task 34: 配置は欠落時 空文字（= 未指定）。opacity は欠落時 -1（= 未指定センチネル）。
    // 0.0 に落ちると「完全透明」と誤解されるため `toDouble(-1)` で読むことを固定する。
    QVERIFY(w.hAlign.isEmpty());
    QVERIFY(w.vAlign.isEmpty());
    QCOMPARE(w.opacity, -1.0);
    // Task T-A（Phase 8）: Trend 固有フィールドの欠落時既定（pointCount/sampleMs=0、
    // lineColor=空、yMin/yMax presence=false）を固定する。
    QCOMPARE(w.pointCount, 0);
    QCOMPARE(w.hasYMin, false);
    QCOMPARE(w.hasYMax, false);
    QVERIFY(w.lineColor.isEmpty());
    QCOMPARE(w.sampleMs, 0);
}

// C++ ブリッジ集約（refactoring）：全フィールド（actions / bindings 含む）が
// toVariantMap → fromVariantMap で往復しても保たれることを固定する。従来 ProjectIo /
// ProjectLoader に重複していた手書き転写を Schema へ集約したため、その正しさをここで担保する。
void WidgetDataTest::variantMapRoundTripFullFields()
{
    WidgetData src;
    src.id = "btn020";
    src.type = "Button";
    src.x = 11;
    src.y = 22;
    src.width = 130;
    src.height = 44;
    src.text = "Run";
    src.tag = "PLC.RUN";
    src.backgroundColor = "#ff0000";
    src.textColor = "#00ff00";
    src.fontSize = 18;
    src.borderColor = "#112233";
    src.borderWidth = 0;   // 0 は正当値（ボーダーなし）
    src.radius = 6;
    src.fontBold = true;
    src.fontItalic = true;
    src.fontFamily = "Courier New";
    src.hAlign = "left";
    src.vAlign = "bottom";
    src.opacity = 0.0;     // 0.0 は正当値（完全透明）
    src.enabled = false;   // 既定 true と異なる値
    src.checkable = true;
    src.checked = true;
    src.minValue = -5.0;   // 負値も presence フラグ方式なら往復する
    src.maxValue = 250.0;
    src.hasMinValue = true;
    src.hasMaxValue = true;
    src.pointCount = 90;   // Task T-A: Trend 固有フィールドも QVariantMap で往復する
    src.yMin = -10.0;      // 負の Y 軸下限も presence フラグ方式なら往復する
    src.yMax = 200.0;
    src.hasYMin = true;
    src.hasYMax = true;
    src.lineColor = "#4cc9f0";
    src.sampleMs = 500;

    ActionData a;
    a.trigger = "onClick";
    a.op = "setVariable";
    a.target = "speed";
    a.value = "42";
    src.actions.append(a);

    BindingData b;
    b.property = "text";
    b.variable = "label";
    src.bindings.append(b);

    const QVariantMap m = src.toVariantMap();
    const WidgetData r = WidgetData::fromVariantMap(m);

    QCOMPARE(r.id, src.id);
    QCOMPARE(r.type, src.type);
    QCOMPARE(r.x, src.x);
    QCOMPARE(r.y, src.y);
    QCOMPARE(r.width, src.width);
    QCOMPARE(r.height, src.height);
    QCOMPARE(r.text, src.text);
    QCOMPARE(r.tag, src.tag);
    QCOMPARE(r.backgroundColor, src.backgroundColor);
    QCOMPARE(r.textColor, src.textColor);
    QCOMPARE(r.fontSize, src.fontSize);
    QCOMPARE(r.borderColor, src.borderColor);
    QCOMPARE(r.borderWidth, src.borderWidth);
    QCOMPARE(r.radius, src.radius);
    QCOMPARE(r.fontBold, src.fontBold);
    QCOMPARE(r.fontItalic, src.fontItalic);
    QCOMPARE(r.fontFamily, src.fontFamily);
    QCOMPARE(r.hAlign, src.hAlign);
    QCOMPARE(r.vAlign, src.vAlign);
    QCOMPARE(r.opacity, src.opacity);
    QCOMPARE(r.enabled, src.enabled);
    QCOMPARE(r.checkable, src.checkable);
    QCOMPARE(r.checked, src.checked);
    QCOMPARE(r.hasMinValue, src.hasMinValue);
    QCOMPARE(r.hasMaxValue, src.hasMaxValue);
    QCOMPARE(r.minValue, src.minValue);
    QCOMPARE(r.maxValue, src.maxValue);
    QCOMPARE(r.pointCount, src.pointCount);
    QCOMPARE(r.hasYMin, src.hasYMin);
    QCOMPARE(r.hasYMax, src.hasYMax);
    QCOMPARE(r.yMin, src.yMin);
    QCOMPARE(r.yMax, src.yMax);
    QCOMPARE(r.lineColor, src.lineColor);
    QCOMPARE(r.sampleMs, src.sampleMs);
    QCOMPARE(r.actions.size(), 1);
    QCOMPARE(r.actions.at(0).trigger, QStringLiteral("onClick"));
    QCOMPARE(r.actions.at(0).op, QStringLiteral("setVariable"));
    QCOMPARE(r.actions.at(0).target, QStringLiteral("speed"));
    QCOMPARE(r.actions.at(0).value, QStringLiteral("42"));
    QCOMPARE(r.bindings.size(), 1);
    QCOMPARE(r.bindings.at(0).property, QStringLiteral("text"));
    QCOMPARE(r.bindings.at(0).variable, QStringLiteral("label"));
}

// C++ ブリッジ集約（refactoring）：キーが欠落した QVariantMap（Canvas を介さない経路）でも、
// 数値センチネル（borderWidth / radius = -1、opacity = -1.0）と enabled = true を正しく
// 既定する。`.toInt()`（既定 0）や `.toBool()`（既定 false）へのデグレを検出する。
void WidgetDataTest::fromVariantMapFillsSentinelDefaults()
{
    QVariantMap m;
    m.insert(QStringLiteral("id"), QStringLiteral("btn021"));
    m.insert(QStringLiteral("type"), QStringLiteral("Button"));
    m.insert(QStringLiteral("width"), 120);
    m.insert(QStringLiteral("height"), 40);
    // borderWidth / radius / opacity / enabled / checkable / checked / actions / bindings は欠落。

    const WidgetData w = WidgetData::fromVariantMap(m);

    QCOMPARE(w.borderWidth, -1);
    QCOMPARE(w.radius, -1);
    QCOMPARE(w.opacity, -1.0);
    QCOMPARE(w.enabled, true);   // 欠落時 true（disabled へ誤読しない）
    QCOMPARE(w.checkable, false);
    QCOMPARE(w.checked, false);
    QCOMPARE(w.hasMinValue, false);  // Task 54: presence は欠落時 false（未指定）
    QCOMPARE(w.hasMaxValue, false);
    // Task T-A（Phase 8）: Trend 固有フィールドも欠落時に既定（0 / 空 / has*=false）になる。
    QCOMPARE(w.pointCount, 0);
    QCOMPARE(w.hasYMin, false);
    QCOMPARE(w.hasYMax, false);
    QVERIFY(w.lineColor.isEmpty());
    QCOMPARE(w.sampleMs, 0);
    // Task 8B-A（Phase 8-B）: Trend 拡張フィールドも欠落時に既定（空 / false / 0）になる
    //（CodeRabbit PR #132 — fromVariantMap 既定値の回帰を固定）。
    QVERIFY(w.series.isEmpty());
    QCOMPARE(w.showGrid, false);
    QCOMPARE(w.showLegend, false);
    QCOMPARE(w.yTickCount, 0);
    QVERIFY(w.actions.isEmpty());
    QVERIFY(w.bindings.isEmpty());
}

// C++ ブリッジ集約（CodeRabbit 指摘）：fromVariantMap は fromJson と同じく、空 / 欠落
// trigger を "onClick" へ正規化する。これを抜くと空 trigger が toJson で書き出され、再読込時に
// isValidJson（trigger != "onClick" を無効視）でプロジェクト全体の load が失敗する。
void WidgetDataTest::fromVariantMapNormalizesEmptyActionTrigger()
{
    QVariantMap action;  // trigger キーを意図的に欠落させる
    action.insert(QStringLiteral("op"), QStringLiteral("toggleVariable"));
    action.insert(QStringLiteral("target"), QStringLiteral("running"));

    QVariantMap m;
    m.insert(QStringLiteral("id"), QStringLiteral("btn022"));
    m.insert(QStringLiteral("type"), QStringLiteral("Button"));
    m.insert(QStringLiteral("width"), 120);
    m.insert(QStringLiteral("height"), 40);
    m.insert(QStringLiteral("actions"), QVariantList{action});

    const WidgetData w = WidgetData::fromVariantMap(m);
    QCOMPARE(w.actions.size(), 1);
    QCOMPARE(w.actions.at(0).trigger, QStringLiteral("onClick"));

    // 正規化された結果は toJson → isValidJson を通る（load が壊れないことを担保）。
    QVERIFY(WidgetData::isValidJson(w.toJson()));
}

void WidgetDataTest::isValidJsonAcceptsMinimumRequiredFields()
{
    QJsonObject obj;
    obj["id"] = "btn001";
    obj["type"] = "Button";
    obj["width"] = 120;
    obj["height"] = 40;
    QVERIFY(WidgetData::isValidJson(obj));

    QVERIFY(WidgetData::isValidJson(validWidgetJson()));
}

void WidgetDataTest::isValidJsonRejectsMissingRequired_data()
{
    QTest::addColumn<QString>("missingKey");
    QTest::newRow("id") << QStringLiteral("id");
    QTest::newRow("type") << QStringLiteral("type");
    QTest::newRow("width") << QStringLiteral("width");
    QTest::newRow("height") << QStringLiteral("height");
}

void WidgetDataTest::isValidJsonRejectsMissingRequired()
{
    QFETCH(QString, missingKey);

    QJsonObject obj = validWidgetJson();
    obj.remove(missingKey);
    QVERIFY(!WidgetData::isValidJson(obj));
}

void WidgetDataTest::isValidJsonRejectsWrongTypes_data()
{
    QTest::addColumn<QString>("key");
    QTest::addColumn<QJsonValue>("badValue");
    QTest::newRow("id as int") << QStringLiteral("id") << QJsonValue(1);
    QTest::newRow("type as int") << QStringLiteral("type") << QJsonValue(1);
    QTest::newRow("width as string") << QStringLiteral("width") << QJsonValue(QStringLiteral("120"));
    QTest::newRow("height as string") << QStringLiteral("height") << QJsonValue(QStringLiteral("40"));
}

void WidgetDataTest::isValidJsonRejectsWrongTypes()
{
    QFETCH(QString, key);
    QFETCH(QJsonValue, badValue);

    QJsonObject obj = validWidgetJson();
    obj[key] = badValue;
    QVERIFY(!WidgetData::isValidJson(obj));
}

QTEST_APPLESS_MAIN(WidgetDataTest)
#include "tst_widget_data.moc"
