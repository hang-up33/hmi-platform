import QtQuick
import QtTest

// Task 14: EditableWidget の検証。
//
// 観点：
//   - メタプロパティ（widgetId / widgetType / widgetText / widgetTag）の
//     デフォルト値と設定可否
//   - dragging のデフォルト false
//   - mouseDrag で x/y が更新される（drag.filterChildren が効いていること）
//   - drag.minimumX/Y / drag.maximumX/Y による親領域内クランプ
//
// 配置：
//   EditableWidget.qml を Qt.createComponent + createObject で stage の子として
//   生成する。Loader だと EditableWidget が Loader と同サイズになり
//   drag.maximumX = parent.width - root.width = 0 でドラッグ不能になるため。
//   stage は 400x400、EditableWidget は 100x50 でドラッグ可動領域を確保する。
//
// 注意：TestCase に visible: true を必ず明示する（Task 13 で確立）。
TestCase {
    id: testCase
    name: "EditableWidget"
    when: windowShown
    visible: true
    width: 400
    height: 400

    property var editable: null

    Item {
        id: stage
        anchors.fill: parent
    }

    Component.onCompleted: {
        const comp = Qt.createComponent(Qt.resolvedUrl("../qml/EditableWidget.qml"));
        if (comp.status !== Component.Ready) {
            console.error("EditableWidget の読込に失敗:", comp.errorString());
            return;
        }
        editable = comp.createObject(stage, {
            x: 50, y: 50, width: 100, height: 50
        });
    }

    function init() {
        verify(editable !== null, "EditableWidget が未ロード");
        editable.widgetId = "";
        editable.widgetType = "Button";
        editable.widgetText = "";
        editable.widgetTag = "";
        editable.x = 50;
        editable.y = 50;
        editable.width = 100;
        editable.height = 50;
    }

    function test_default_meta_properties() {
        // init で初期化済み + Item ベースなので追加の妥当性を確認
        compare(editable.widgetType, "Button");
        compare(editable.widgetId, "");
        compare(editable.widgetText, "");
        compare(editable.widgetTag, "");
        compare(editable.dragging, false);
    }

    function test_meta_properties_are_settable() {
        editable.widgetId = "btn001";
        editable.widgetType = "Button";
        editable.widgetText = "Start";
        editable.widgetTag = "PLC.START";

        compare(editable.widgetId, "btn001");
        compare(editable.widgetType, "Button");
        compare(editable.widgetText, "Start");
        compare(editable.widgetTag, "PLC.START");
    }

    function test_drag_updates_position() {
        const startX = editable.x;
        const startY = editable.y;

        // mouseDrag は (x, y) 起点から (x+dx, y+dy) へドラッグ動作を生成する。
        // drag.filterChildren が効いているので、しきい値超過で MouseArea が
        // drag を発動し、EditableWidget root の x/y が連動する。
        mouseDrag(editable, editable.width / 2, editable.height / 2, 80, 40);

        verify(editable.x > startX, "ドラッグで x が増えていない: " + editable.x);
        verify(editable.y > startY, "ドラッグで y が増えていない: " + editable.y);
    }

    function test_drag_clamps_to_parent_bounds_min() {
        // 200,200 を起点に大きく左上方向へドラッグ → minimumX/Y=0 でクランプ
        editable.x = 200;
        editable.y = 200;

        mouseDrag(editable, editable.width / 2, editable.height / 2, -500, -500);

        compare(editable.x, 0);
        compare(editable.y, 0);
    }

    function test_drag_clamps_to_parent_bounds_max() {
        // 200,200 を起点に大きく右下方向へドラッグ →
        // maximumX = parent.width - root.width = 400 - 100 = 300
        // maximumY = parent.height - root.height = 400 - 50 = 350
        editable.x = 200;
        editable.y = 200;

        mouseDrag(editable, editable.width / 2, editable.height / 2, 500, 500);

        compare(editable.x, 300);
        compare(editable.y, 350);
    }
}
