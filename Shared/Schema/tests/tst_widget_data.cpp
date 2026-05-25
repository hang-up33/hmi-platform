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
