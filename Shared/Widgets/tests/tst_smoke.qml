import QtQuick
import QtTest

// Qt Quick Test 基盤の smoke。
// このテストが緑なら Qt Quick Test の C++/QML ハーネスが正しく動いていること、
// および ctest 連携が機能していることを保証する。Widget 個別の検証は Task 13 で。
TestCase {
    name: "QuickSmoke"

    function test_truth() {
        compare(1 + 1, 2);
    }

    function test_qml_object_creation() {
        const item = Qt.createQmlObject(
            'import QtQuick; Item { width: 10; height: 20 }',
            this
        );
        verify(item !== null);
        compare(item.width, 10);
        compare(item.height, 20);
        item.destroy();
    }
}
