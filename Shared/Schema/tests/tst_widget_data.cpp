#include "hmi/schema/WidgetData.h"

#include <QJsonObject>
#include <QTest>

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
    void fromJsonFillsDefaultsForMissingKeys();

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
