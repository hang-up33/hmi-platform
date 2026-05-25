#include "hmi/schema/ScreenData.h"
#include "hmi/schema/WidgetData.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QTest>

using hmi::schema::ScreenData;
using hmi::schema::WidgetData;

namespace {

WidgetData makeWidget(const QString &id)
{
    WidgetData w;
    w.id = id;
    w.type = "Button";
    w.x = 10;
    w.y = 20;
    w.width = 100;
    w.height = 30;
    w.text = "Label";
    return w;
}

QJsonObject validScreenJson()
{
    QJsonObject screen;
    screen["name"] = "Main";
    QJsonArray widgets;
    widgets.append(makeWidget("btn001").toJson());
    widgets.append(makeWidget("btn002").toJson());
    screen["widgets"] = widgets;
    return screen;
}

} // namespace

class ScreenDataTest : public QObject
{
    Q_OBJECT

private slots:
    void roundTripWithWidgets();
    void roundTripWithEmptyWidgets();

    void isValidJsonAcceptsEmptyWidgetsArray();
    void isValidJsonAcceptsNormalScreen();
    void isValidJsonRejectsMissingWidgetsKey();
    void isValidJsonRejectsNonArrayWidgets();
    void isValidJsonRejectsInvalidWidgetElement();
    void isValidJsonRejectsNonObjectWidgetElement();
};

void ScreenDataTest::roundTripWithWidgets()
{
    ScreenData src;
    src.name = "Main";
    src.widgets.append(makeWidget("btn001"));
    src.widgets.append(makeWidget("btn002"));

    const QJsonObject obj = src.toJson();
    const ScreenData restored = ScreenData::fromJson(obj);

    QCOMPARE(restored.name, src.name);
    QCOMPARE(restored.widgets.size(), src.widgets.size());
    for (int i = 0; i < src.widgets.size(); ++i) {
        QCOMPARE(restored.widgets[i].id, src.widgets[i].id);
        QCOMPARE(restored.widgets[i].type, src.widgets[i].type);
        QCOMPARE(restored.widgets[i].x, src.widgets[i].x);
        QCOMPARE(restored.widgets[i].y, src.widgets[i].y);
        QCOMPARE(restored.widgets[i].width, src.widgets[i].width);
        QCOMPARE(restored.widgets[i].height, src.widgets[i].height);
        QCOMPARE(restored.widgets[i].text, src.widgets[i].text);
        QCOMPARE(restored.widgets[i].tag, src.widgets[i].tag);
    }
}

void ScreenDataTest::roundTripWithEmptyWidgets()
{
    ScreenData src;
    src.name = "Empty";

    const QJsonObject obj = src.toJson();
    QVERIFY(obj.value("widgets").isArray());
    QCOMPARE(obj.value("widgets").toArray().size(), 0);

    const ScreenData restored = ScreenData::fromJson(obj);
    QCOMPARE(restored.name, src.name);
    QVERIFY(restored.widgets.isEmpty());
}

void ScreenDataTest::isValidJsonAcceptsEmptyWidgetsArray()
{
    QJsonObject obj;
    obj["name"] = "Empty";
    obj["widgets"] = QJsonArray{};
    QVERIFY(ScreenData::isValidJson(obj));
}

void ScreenDataTest::isValidJsonAcceptsNormalScreen()
{
    QVERIFY(ScreenData::isValidJson(validScreenJson()));
}

void ScreenDataTest::isValidJsonRejectsMissingWidgetsKey()
{
    QJsonObject obj;
    obj["name"] = "NoWidgets";
    QVERIFY(!ScreenData::isValidJson(obj));
}

void ScreenDataTest::isValidJsonRejectsNonArrayWidgets()
{
    QJsonObject obj = validScreenJson();
    obj["widgets"] = QStringLiteral("not-an-array");
    QVERIFY(!ScreenData::isValidJson(obj));
}

void ScreenDataTest::isValidJsonRejectsInvalidWidgetElement()
{
    QJsonObject obj = validScreenJson();
    QJsonArray widgets = obj.value("widgets").toArray();

    QJsonObject brokenWidget = makeWidget("brokenId").toJson();
    brokenWidget.remove("width");
    widgets.append(brokenWidget);
    obj["widgets"] = widgets;

    QVERIFY(!ScreenData::isValidJson(obj));
}

void ScreenDataTest::isValidJsonRejectsNonObjectWidgetElement()
{
    QJsonObject obj = validScreenJson();
    QJsonArray widgets = obj.value("widgets").toArray();
    widgets.append(QJsonValue("not-an-object"));
    obj["widgets"] = widgets;

    QVERIFY(!ScreenData::isValidJson(obj));
}

QTEST_APPLESS_MAIN(ScreenDataTest)
#include "tst_screen_data.moc"
