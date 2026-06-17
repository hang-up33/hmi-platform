#include "hmi/schema/TrendSeriesData.h"

#include <QJsonObject>
#include <QTest>

using hmi::schema::TrendSeriesData;

// Task 8B-A（Phase 8-B）: Trend の 1 系列（折れ線 1 本）の子型 TrendSeriesData の JSON I/O +
// QVariantMap 往復を固定する。ActionData / BindingData と同じ三点セット規約。
class TrendSeriesDataTest : public QObject {
    Q_OBJECT

private slots:
    void roundTripFullFields();
    void omitsEmptyColorLabel();
    void variantMapRoundTrip();
    void isValidJson_data();
    void isValidJson();
};

void TrendSeriesDataTest::roundTripFullFields()
{
    TrendSeriesData src;
    src.variable = "sensorTemp";
    src.color = "#4cc9f0";
    src.label = "Temp";

    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("variable"));
    QVERIFY(obj.contains("color"));
    QVERIFY(obj.contains("label"));

    const TrendSeriesData r = TrendSeriesData::fromJson(obj);
    QCOMPARE(r.variable, QStringLiteral("sensorTemp"));
    QCOMPARE(r.color, QStringLiteral("#4cc9f0"));
    QCOMPARE(r.label, QStringLiteral("Temp"));
}

// color / label は空（= 未指定）のとき省略され、欠落時は空文字で読まれる（後方互換）。
void TrendSeriesDataTest::omitsEmptyColorLabel()
{
    TrendSeriesData src;
    src.variable = "sensorPressure";
    // color / label は既定の空。

    const QJsonObject obj = src.toJson();
    QVERIFY(obj.contains("variable"));
    QVERIFY(!obj.contains("color"));
    QVERIFY(!obj.contains("label"));

    const TrendSeriesData r = TrendSeriesData::fromJson(obj);
    QCOMPARE(r.variable, QStringLiteral("sensorPressure"));
    QVERIFY(r.color.isEmpty());
    QVERIFY(r.label.isEmpty());
}

void TrendSeriesDataTest::variantMapRoundTrip()
{
    TrendSeriesData src;
    src.variable = "flow";
    src.color = "#f72585";
    src.label = "Flow";

    const QVariantMap m = src.toVariantMap();
    QCOMPARE(m.value("variable").toString(), QStringLiteral("flow"));
    QCOMPARE(m.value("color").toString(), QStringLiteral("#f72585"));
    QCOMPARE(m.value("label").toString(), QStringLiteral("Flow"));

    const TrendSeriesData r = TrendSeriesData::fromVariantMap(m);
    QCOMPARE(r.variable, QStringLiteral("flow"));
    QCOMPARE(r.color, QStringLiteral("#f72585"));
    QCOMPARE(r.label, QStringLiteral("Flow"));
}

void TrendSeriesDataTest::isValidJson_data()
{
    QTest::addColumn<QString>("variable");
    QTest::addColumn<bool>("valid");

    QTest::newRow("non-empty variable") << QStringLiteral("sensorTemp") << true;
    QTest::newRow("empty variable") << QString() << false;
}

void TrendSeriesDataTest::isValidJson()
{
    QFETCH(QString, variable);
    QFETCH(bool, valid);

    QJsonObject obj;
    if (!variable.isEmpty()) {
        obj["variable"] = variable;
    }
    QCOMPARE(TrendSeriesData::isValidJson(obj), valid);
}

QTEST_APPLESS_MAIN(TrendSeriesDataTest)
#include "tst_trend_series_data.moc"
