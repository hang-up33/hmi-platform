// Editor QML 用 Qt Quick Test ハーネス（Task 14）。
// 同ディレクトリの tst_*.qml を QUICK_TEST_SOURCE_DIR から走査して実行する。
//
// Editor の QML は HmiEditor モジュール（実行体内に閉じた qt_add_qml_module）
// として登録されているため、外部から `import HmiEditor` で参照する経路が
// 確保されていない。代わりにテスト QML 側で Qt.resolvedUrl("../qml/<file>.qml")
// を使い、本体 QML ファイルを直接 Loader 経由で読み込む方式を採る。
// この方式なら本体の構造（実行体ベースの qt_add_qml_module）を変更せずに
// テストが書ける（Phase 2 plan「テストのために本体を変えない」原則）。
#include <QtQuickTest>

QUICK_TEST_MAIN(hmi_editor_qml)
