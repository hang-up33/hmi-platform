// Simulator QML 用 Qt Quick Test ハーネス（Task 41）。
// 同ディレクトリの tst_*.qml を QUICK_TEST_SOURCE_DIR から走査して実行する。
//
// Simulator の QML は HmiSimulator モジュール（STATIC plugin）として登録されているが、
// Editor 側テストと同様にテスト QML 内で Qt.createComponent(Qt.resolvedUrl(
// "../qml/SimulatorCanvas.qml")) + createObject で本体 QML を動的生成する方式を採る
// （SimulatorCanvas は HmiWidgets だけを import するため、テスト実行体に
// hmi_widgetsplugin がリンクされていれば解決できる）。本体の構造を変えずに
// アクション実行 / バインディング追従を検証する。
#include <QtQuickTest>

QUICK_TEST_MAIN(hmi_simulator_qml)
