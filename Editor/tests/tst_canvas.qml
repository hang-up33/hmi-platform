import QtQuick
import QtTest

// Task 14: Canvas の検証。
//
// 観点：
//   - canvasWidth / canvasHeight のデフォルト（800 / 600）
//   - 初期 widgetModel から EditableWidget が 1 個生成される
//   - widgetModel を別の配列に差し替えると children が再生成される
//   - 空配列にすると children が 0 件になる
//
// 配置：
//   Canvas.qml は内部で `import HmiWidgets` する。テスト実行体に
//   hmi_widgetsplugin がリンクされていれば解決される（Task 13 で確立）。
//   Canvas を Qt.createComponent + createObject で stage の子として生成し、
//   widgetItems プロパティ（widgetLayer.children alias）を通じて配下を観察する。
//
// 注意：widgetItems には Repeater 自身も含まれる（QQuickRepeater）。
//   widgetId プロパティの有無で EditableWidget だけを数える。
TestCase {
    id: testCase
    name: "Canvas"
    when: windowShown
    visible: true
    width: 900
    height: 700

    property var canvas: null

    Item {
        id: stage
        anchors.fill: parent
    }

    Component.onCompleted: {
        const comp = Qt.createComponent(Qt.resolvedUrl("../qml/Canvas.qml"));
        if (comp.status !== Component.Ready) {
            console.error("Canvas の読込に失敗:", comp.errorString());
            return;
        }
        canvas = comp.createObject(stage);
    }

    function init() {
        verify(canvas !== null, "Canvas が未ロード");
        // 各テストの前に既定状態へ戻す（test 関数は alphabetical 実行のため
        // 前の test が変更した状態が次に漏れないように）
        canvas.canvasWidth = 800;
        canvas.canvasHeight = 600;
        canvas.selectedWidgetId = "";
        canvas.widgetModel = [
            { id: "btn001", type: "Button", x: 100, y: 50, width: 120, height: 40,
              text: "Start", tag: "PLC.START" }
        ];
        // Repeater の delegate 生成は非同期/段階的なので、初期 model の
        // 反映完了を待ってから各 test_* に渡す。
        tryVerify(function() { return editableChildren().length === 1; }, 1000,
                  "init: 初期 widgetModel が Repeater に反映されない");
    }

    // widgetItems から EditableWidget だけを抽出する（Repeater 自身を除く）
    function editableChildren() {
        const items = canvas.widgetItems;
        const result = [];
        for (let i = 0; i < items.length; ++i) {
            if (items[i].widgetId !== undefined)
                result.push(items[i]);
        }
        return result;
    }

    function test_default_canvas_size() {
        compare(canvas.canvasWidth, 800);
        compare(canvas.canvasHeight, 600);
        compare(canvas.width, 800);
        compare(canvas.height, 600);
    }

    function test_initial_model_creates_one_editable_widget() {
        // init() で初期 model 反映完了を待っているが、本テストは件数を
        // 直接検証するため tryVerify をここでも明示する。
        tryVerify(function() { return editableChildren().length === 1; }, 1000);
        const widgets = editableChildren();
        compare(widgets.length, 1);

        const w = widgets[0];
        compare(w.widgetId, "btn001");
        compare(w.widgetType, "Button");
        compare(w.widgetText, "Start");
        compare(w.widgetTag, "PLC.START");
        compare(w.x, 100);
        compare(w.y, 50);
        compare(w.width, 120);
        compare(w.height, 40);
    }

    function test_replace_model_recreates_widgets() {
        canvas.widgetModel = [
            { id: "a", type: "Button", x:   0, y: 0, width: 80, height: 30, text: "A", tag: "" },
            { id: "b", type: "Button", x: 100, y: 0, width: 80, height: 30, text: "B", tag: "" },
            { id: "c", type: "Button", x: 200, y: 0, width: 80, height: 30, text: "C", tag: "" }
        ];

        // Repeater の delegate 生成/破棄は段階的に進むため、件数が安定する
        // まで tryVerify で待つ。即時 length 比較は CI 負荷次第で flaky になる
        // （Codex P2 指摘より）。
        tryVerify(function() { return editableChildren().length === 3; }, 1000,
                  "widgetModel 差替後 3 件にならない");
        const widgets = editableChildren();

        const ids = widgets.map(function(w) { return w.widgetId; });
        verify(ids.indexOf("a") !== -1, "a が無い: " + ids);
        verify(ids.indexOf("b") !== -1, "b が無い: " + ids);
        verify(ids.indexOf("c") !== -1, "c が無い: " + ids);
    }

    function test_empty_model_creates_no_widgets() {
        canvas.widgetModel = [];

        // 空配列への差替も Repeater の破棄完了を tryVerify で待つ。
        tryVerify(function() { return editableChildren().length === 0; }, 1000,
                  "widgetModel 空配列差替後 0 件にならない");
    }

    function test_canvas_size_can_be_overridden() {
        canvas.canvasWidth = 640;
        canvas.canvasHeight = 480;

        compare(canvas.width, 640);
        compare(canvas.height, 480);
    }

    // Task 25: 選択状態は selectedWidgetId（Canvas が所有）に集約され、
    // 既定は未選択（空文字）。
    function test_selected_widget_id_defaults_empty() {
        compare(canvas.selectedWidgetId, "");
    }

    // Task 25: selectedWidgetId を設定すると一致する delegate だけが
    // selected になる（delegate 側 `selected: widgetId === selectedWidgetId`
    // バインドの結線確認）。
    function test_selecting_id_marks_matching_delegate() {
        canvas.widgetModel = [
            { id: "a", type: "Button", x:   0, y: 0, width: 80, height: 30, text: "A", tag: "" },
            { id: "b", type: "Button", x: 100, y: 0, width: 80, height: 30, text: "B", tag: "" }
        ];
        tryVerify(function() { return editableChildren().length === 2; }, 1000,
                  "2 件モデルが反映されない");

        canvas.selectedWidgetId = "b";
        tryVerify(function() {
            const ws = editableChildren();
            if (ws.length !== 2) return false;
            for (let i = 0; i < ws.length; ++i) {
                if (ws[i].selected !== (ws[i].widgetId === "b")) return false;
            }
            return true;
        }, 1000, "選択状態が selectedWidgetId に追従しない");
    }

    // Task 25: 選択解除（空文字）で全 delegate の selected が false に戻る。
    function test_clearing_selection_unmarks_all() {
        canvas.selectedWidgetId = "btn001";
        tryVerify(function() {
            const ws = editableChildren();
            return ws.length === 1 && ws[0].selected === true;
        }, 1000, "btn001 が選択状態にならない");

        canvas.selectedWidgetId = "";
        tryVerify(function() {
            const ws = editableChildren();
            return ws.length === 1 && ws[0].selected === false;
        }, 1000, "選択解除後も selected が残る");
    }
}
