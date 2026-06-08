import QtQuick
import QtTest
import HmiWidgets

// Task 41: Simulator / Runtime の「実行」検証。
//
// 観点：
//   - 読込時に variableModel から VariableStore が初期値で初期化される
//   - Button クリックでアクション（toggleVariable / setVariable）が実行され変数が変わる
//   - binding（{property, variable}）で widget プロパティが変数へ追従する
//     （visible / text の最小デモ）
//
// 配置：
//   SimulatorCanvas.qml は内部で `import HmiWidgets` する。テスト実行体に
//   hmi_widgetsplugin がリンクされていれば解決される（Editor 側 tst_canvas と同方式）。
//   SimulatorCanvas を createComponent + createObject で stage の子として生成し、
//   delegate（objectName "widget_<id>"）を再帰探索して観察する。
TestCase {
    id: testCase
    name: "SimulatorCanvas"
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
        const comp = Qt.createComponent(Qt.resolvedUrl("../qml/SimulatorCanvas.qml"));
        if (comp.status !== Component.Ready) {
            console.error("SimulatorCanvas の読込に失敗:", comp.errorString());
            return;
        }
        canvas = comp.createObject(stage);
    }

    // objectName で子孫を再帰探索する（SimulatorCanvas は widgetItems alias を
    // 持たないため。Repeater の delegate も含めて辿る）。
    function findByObjectName(node, name) {
        if (!node) {
            return null;
        }
        if (node.objectName === name) {
            return node;
        }
        const kids = node.children;
        if (kids) {
            for (let i = 0; i < kids.length; ++i) {
                const found = findByObjectName(kids[i], name);
                if (found) {
                    return found;
                }
            }
        }
        return null;
    }

    function init() {
        verify(canvas !== null, "SimulatorCanvas が未ロード");
        // singleton の VariableStore はテスト間で状態を共有するため空へ戻す。
        VariableStore.clear();
        canvas.variableModel = [];
        canvas.widgetModel = [];
        tryVerify(function() {
            return findByObjectName(canvas, "widget_b1") === null;
        }, 1000, "init: 前テストの delegate が残っている");
    }

    // 読込時に variableModel から VariableStore が初期化される。
    function test_load_initializes_variable_store() {
        canvas.variableModel = [
            { name: "running", type: "bool",   initial: "true" },
            { name: "label",   type: "string", initial: "hello" }
        ];
        compare(VariableStore.get("running"), true);
        compare(VariableStore.get("label"), "hello");
    }

    // toggleVariable アクション → bool 変数が反転し、visible binding が追従する。
    function test_toggle_action_drives_visible_binding() {
        canvas.variableModel = [{ name: "running", type: "bool", initial: "false" }];
        canvas.widgetModel = [{
            id: "b1", type: "Button", x: 0, y: 0, width: 120, height: 40, text: "X",
            bindings: [{ property: "visible", variable: "running" }],
            actions: [{ trigger: "onClick", op: "toggleVariable", target: "running" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_b1");
            return wrapper !== null;
        }, 1000, "delegate widget_b1 が生成されない");

        // running=false → visible binding が false に追従。
        compare(VariableStore.get("running"), false);
        compare(wrapper.visible, false);

        // クリック相当（onClick アクション実行）→ running 反転 → visible 追従。
        wrapper.runClickActions();
        compare(VariableStore.get("running"), true);
        compare(wrapper.visible, true);
    }

    // setVariable アクション → string 変数が更新され、text binding が追従する。
    function test_set_variable_action_drives_text_binding() {
        canvas.variableModel = [{ name: "label", type: "string", initial: "hi" }];
        canvas.widgetModel = [{
            id: "b1", type: "Button", x: 0, y: 0, width: 120, height: 40, text: "static",
            bindings: [{ property: "text", variable: "label" }],
            actions: [{ trigger: "onClick", op: "setVariable", target: "label", value: "bye" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_b1");
            return wrapper !== null;
        }, 1000, "delegate widget_b1 が生成されない");

        const button = findByObjectName(wrapper, "hmiButton");
        verify(button !== null, "hmiButton が見つからない");

        // 初期は変数 label の値 "hi" に追従（静的 text "static" ではない）。
        compare(button.text, "hi");

        // setVariable 実行 → label = "bye" → text 追従。
        wrapper.runClickActions();
        compare(VariableStore.get("label"), "bye");
        compare(button.text, "bye");
    }

    // binding が無い property は modelData の静的値を使う（後方互換）。
    function test_no_binding_uses_static_value() {
        canvas.variableModel = [];
        canvas.widgetModel = [{
            id: "b1", type: "Button", x: 0, y: 0, width: 120, height: 40, text: "plain"
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_b1");
            return wrapper !== null;
        }, 1000, "delegate widget_b1 が生成されない");

        compare(wrapper.visible, true);
        const button = findByObjectName(wrapper, "hmiButton");
        compare(button.text, "plain");
    }
}
