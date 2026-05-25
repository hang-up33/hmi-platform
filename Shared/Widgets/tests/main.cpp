// Qt Quick Test 用ハーネス。
// QUICK_TEST_SOURCE_DIR（CMake で -D 定義）で指定されたディレクトリを
// 再帰的に走査し、tst_*.qml を TestCase として実行する。
//
// 新しい QML テストを追加するときは、同じディレクトリに tst_<name>.qml を
// 置くだけで自動的にこのハーネスから実行される（C++ 側の修正は不要）。
#include <QtQuickTest>

QUICK_TEST_MAIN(hmi_widgets_qml)
