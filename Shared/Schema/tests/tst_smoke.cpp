#include <QTest>

class SmokeTest : public QObject
{
    Q_OBJECT

private slots:
    void frameworkRuns();
};

void SmokeTest::frameworkRuns()
{
    QCOMPARE(1 + 1, 2);
}

QTEST_APPLESS_MAIN(SmokeTest)
#include "tst_smoke.moc"
