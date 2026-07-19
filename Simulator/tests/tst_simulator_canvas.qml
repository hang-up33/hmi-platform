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
        // canvas は Component.onCompleted で非同期生成されるため、低速 / headless
        // 環境での生成レースを避けて tryVerify で生成完了を待つ（CodeRabbit 指摘）。
        tryVerify(function() { return canvas !== null; }, 1000, "SimulatorCanvas が未ロード");
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

    // Task 42: enabled=false の Button はクリックしてもアクションを実行しない
    //（runClickActions が enabled を見て早期 return する）。
    function test_disabled_button_does_not_run_actions() {
        canvas.variableModel = [{ name: "n", type: "int", initial: "0" }];
        canvas.widgetModel = [{
            id: "b1", type: "Button", x: 0, y: 0, width: 120, height: 40, text: "X",
            enabled: false,
            actions: [{ trigger: "onClick", op: "setVariable", target: "n", value: "9" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_b1");
            return wrapper !== null;
        }, 1000, "delegate widget_b1 が生成されない");

        compare(VariableStore.get("n"), 0);
        wrapper.runClickActions();   // disabled なので何も起きない
        compare(VariableStore.get("n"), 0);

        // HmiButton 側は淡色表示（widgetEnabled=false）になっている。
        const button = findByObjectName(wrapper, "hmiButton");
        compare(button.widgetEnabled, false);
    }

    // Task 42: checked が binding で bool 変数へ追従する（toggleVariable + Binding(checked) の連動）。
    function test_checked_follows_binding() {
        canvas.variableModel = [{ name: "on", type: "bool", initial: "false" }];
        canvas.widgetModel = [{
            id: "b1", type: "Button", x: 0, y: 0, width: 120, height: 40, text: "T",
            checkable: true,
            bindings: [{ property: "checked", variable: "on" }],
            actions: [{ trigger: "onClick", op: "toggleVariable", target: "on" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_b1");
            return wrapper !== null;
        }, 1000, "delegate widget_b1 が生成されない");

        const button = findByObjectName(wrapper, "hmiButton");
        compare(button.checked, false);   // on=false に追従

        wrapper.runClickActions();         // on を反転 → checked 追従
        compare(VariableStore.get("on"), true);
        compare(button.checked, true);
    }

    // Task 47: 型分岐の足場。type:"Button"（既定）の delegate は HmiButton を描く。
    function test_delegate_renders_button_for_button_type() {
        canvas.variableModel = [];
        canvas.widgetModel = [{
            id: "b1", type: "Button", x: 0, y: 0, width: 120, height: 40, text: "B"
        }];
        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_b1");
            return wrapper !== null;
        }, 1000, "delegate widget_b1 が生成されない");

        tryVerify(function() { return findByObjectName(wrapper, "hmiButton") !== null; },
                  1000, "Button type で HmiButton が描かれない");
        verify(findByObjectName(wrapper, "hmiLabel") === null,
               "Button type なのに HmiLabel も生成された");
    }

    // Task 47: type:"Label" の delegate は HmiLabel を描き、text binding を追従させる
    //（Label は表示専用＝binding 追従はあるが click action は無い）。
    function test_delegate_renders_label_and_follows_text_binding() {
        canvas.variableModel = [{ name: "label", type: "string", initial: "hi" }];
        canvas.widgetModel = [{
            id: "b1", type: "Label", x: 0, y: 0, width: 120, height: 40, text: "static",
            bindings: [{ property: "text", variable: "label" }]
        }];
        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_b1");
            return wrapper !== null;
        }, 1000, "delegate widget_b1 が生成されない");

        var labelItem = null;
        tryVerify(function() {
            labelItem = findByObjectName(wrapper, "hmiLabel");
            return labelItem !== null;
        }, 1000, "Label type で HmiLabel が描かれない");
        verify(findByObjectName(wrapper, "hmiButton") === null,
               "Label type なのに HmiButton も生成された");

        // 初期は変数 label の値 "hi" に追従（静的 text "static" ではない）。
        compare(labelItem.text, "hi");

        // 変数を更新すると Label の text も追従する（binding は全 Widget 共通）。
        VariableStore.setValue("label", "bye");
        compare(labelItem.text, "bye");
    }

    // Task 50 / 51: type:"NumericField" の delegate は HmiNumericField を描き、
    // boundValue("value") で変数値を表示に追従させる（読み）。Task 51 で Simulator は
    // editable:true（live 編集）へ切替わった。
    function test_delegate_renders_numeric_and_follows_value_binding() {
        canvas.variableModel = [{ name: "setpoint", type: "int", initial: 10 }];
        canvas.widgetModel = [{
            id: "b1", type: "NumericField", x: 0, y: 0, width: 120, height: 40, text: "0",
            bindings: [{ property: "value", variable: "setpoint" }]
        }];
        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_b1");
            return wrapper !== null;
        }, 1000, "delegate widget_b1 が生成されない");

        var fld = null;
        tryVerify(function() {
            fld = findByObjectName(wrapper, "hmiNumericField");
            return fld !== null;
        }, 1000, "NumericField type で HmiNumericField が描かれない");
        verify(findByObjectName(wrapper, "hmiButton") === null,
               "NumericField type なのに HmiButton も生成された");
        verify(findByObjectName(wrapper, "hmiLabel") === null,
               "NumericField type なのに HmiLabel も生成された");

        // Task 51: Simulator は live 編集＝editable:true（write 経路を結線済み）。
        compare(fld.editable, true);

        // 初期は変数 setpoint の値 10 に追従（静的 text "0" ではない）。
        compare(fld.text, "10");

        // 変数を更新すると表示も追従する（読み）。
        VariableStore.setValue("setpoint", 25);
        compare(fld.text, "25");
    }

    // Task 51: 入力確定（commitValue → valueCommitted）で binding {property:"value"} の指す
    // 変数へ書き戻され（書き）、同じ変数を読む他 binding も追従する（読み書き両用 binding）。
    // Spix は実テキスト入力を発火できないため、E2E と同様に text を直接セットして
    // commitValue() を呼ぶことで「ユーザーが入力して確定」を模す。
    function test_numeric_commit_writes_variable_and_other_binding_follows() {
        canvas.variableModel = [{ name: "setpoint", type: "int", initial: 10 }];
        canvas.widgetModel = [
            {
                id: "in1", type: "NumericField", x: 0, y: 0, width: 120, height: 40, text: "0",
                bindings: [{ property: "value", variable: "setpoint" }]
            },
            // 同じ変数 setpoint を text で読む Label（書き戻しの追従を観測する相手）。
            {
                id: "out1", type: "Label", x: 0, y: 60, width: 120, height: 40, text: "?",
                bindings: [{ property: "text", variable: "setpoint" }]
            }
        ];

        var inWrap = null;
        tryVerify(function() {
            inWrap = findByObjectName(canvas, "widget_in1");
            return inWrap !== null;
        }, 1000, "NumericField delegate widget_in1 が生成されない");
        var outWrap = null;
        tryVerify(function() {
            outWrap = findByObjectName(canvas, "widget_out1");
            return outWrap !== null;
        }, 1000, "Label delegate widget_out1 が生成されない");

        var fld = null;
        tryVerify(function() {
            fld = findByObjectName(inWrap, "hmiNumericField");
            return fld !== null;
        }, 1000, "HmiNumericField が描かれない");
        const lbl = findByObjectName(outWrap, "hmiLabel");
        verify(lbl !== null, "観測用 HmiLabel が見つからない");

        // 初期：両 Widget とも setpoint=10 を表示。
        compare(fld.text, "10");
        compare(lbl.text, "10");

        // ユーザー入力を模す：内部 TextField に "42" を入れて commitValue() で確定。
        const tf = findByObjectName(fld, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        tf.text = "42";
        fld.commitValue();

        // 確定で setpoint=42（int に coerce）へ書き戻され、Label も追従する。
        compare(VariableStore.get("setpoint"), 42);
        compare(lbl.text, "42");
        // NumericField 自身の表示も boundValue 再評価で 42 に揃う（読み書き両用）。
        compare(fld.text, "42");
    }

    // Task 51: binding が無い NumericField の確定は no-op（書き戻し先が無い）。
    // 例外を投げず、変数ストアも変化しないこと。
    function test_numeric_commit_without_binding_is_noop() {
        canvas.variableModel = [{ name: "setpoint", type: "int", initial: 5 }];
        canvas.widgetModel = [{
            id: "in1", type: "NumericField", x: 0, y: 0, width: 120, height: 40, text: "0"
        }];
        var inWrap = null;
        tryVerify(function() {
            inWrap = findByObjectName(canvas, "widget_in1");
            return inWrap !== null;
        }, 1000, "NumericField delegate widget_in1 が生成されない");
        const fld = findByObjectName(inWrap, "hmiNumericField");
        verify(fld !== null, "HmiNumericField が描かれない");

        const tf = findByObjectName(fld, "numericTextField");
        tf.text = "99";
        fld.commitValue();  // binding 無し＝書き戻し先が無い＝no-op
        compare(VariableStore.get("setpoint"), 5);  // 変化なし
    }

    // Task 53: real 変数を bind した NumericField は isReal が導出され、小数を保ったまま
    // 変数へ書き戻す（int の丸めと違う）。"36.5" → real 変数 36.5 に更新され表示も追従。
    function test_numeric_real_commit_writes_decimal() {
        canvas.variableModel = [{ name: "temperature", type: "real", initial: "20.0" }];
        canvas.widgetModel = [{
            id: "in1", type: "NumericField", x: 0, y: 0, width: 120, height: 40, text: "0",
            bindings: [{ property: "value", variable: "temperature" }]
        }];

        var inWrap = null;
        tryVerify(function() {
            inWrap = findByObjectName(canvas, "widget_in1");
            return inWrap !== null;
        }, 1000, "NumericField delegate widget_in1 が生成されない");
        var fld = null;
        tryVerify(function() {
            fld = findByObjectName(inWrap, "hmiNumericField");
            return fld !== null;
        }, 1000, "HmiNumericField が描かれない");

        // bound 変数が real 型なので isReal が true に導出される。
        compare(fld.isReal, true);

        const tf = findByObjectName(fld, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        tf.forceActiveFocus();  // 編集セッション開始
        // real 経路は commitValue / DoubleValidator を C locale（ASCII の "."）固定で解釈するため、
        // 入力も ASCII 小数点で固定する（Codex PR #112 [P2]：locale.decimalPoint 由来だと
        // 小数点カンマ環境で "36,5" が 36.5 として扱われずテストが locale 依存で落ちる）。
        tf.text = "36.5";
        fld.commitValue();

        // real に coerce され小数が保たれる（int だと 36 に丸まる）。
        compare(VariableStore.get("temperature"), 36.5);
        // 表示も boundValue 再評価で 36.5 に揃う。
        compare(fld.text, "36.5");
    }

    // Task T-B（Phase 8）: type:"Trend" の delegate は HmiTrend を描き（他種別は描かない）、
    // live:true でサンプリングする。binding {property:"value"} の指す変数を更新すると
    // サンプルが取り込まれ、公開 sampleCount / lastValue が追従する（Canvas ピクセルは見ない）。
    function test_delegate_renders_trend_and_samples_bound_value() {
        canvas.variableModel = [{ name: "sensorTemp", type: "int", initial: 10 }];
        canvas.widgetModel = [{
            id: "t1", type: "Trend", x: 0, y: 0, width: 320, height: 160,
            pointCount: 60,
            bindings: [{ property: "value", variable: "sensorTemp" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_t1");
            return wrapper !== null;
        }, 1000, "Trend delegate widget_t1 が生成されない");

        var trend = null;
        tryVerify(function() {
            trend = findByObjectName(wrapper, "hmiTrend");
            return trend !== null;
        }, 1000, "Trend type で HmiTrend が描かれない");
        // 型分岐：他種別の Widget は生成されない。
        verify(findByObjectName(wrapper, "hmiButton") === null,
               "Trend type なのに HmiButton も生成された");
        verify(findByObjectName(wrapper, "hmiLabel") === null,
               "Trend type なのに HmiLabel も生成された");
        verify(findByObjectName(wrapper, "hmiNumericField") === null,
               "Trend type なのに HmiNumericField も生成された");

        // Simulator はライブ実行＝live:true。
        compare(trend.live, true);
        compare(trend.resolvedPointCount, 60);

        // 初期サンプル：value が初期値 10 へバインドされた瞬間に 1 点取り込まれている可能性が
        // ある（onValueChanged）。ここでは初期 sampleCount を基準に、以降の変数更新で
        // 取り込みが増えることを観測する（初期分の有無に依存しない）。
        const baseCount = trend.sampleCount;

        // 変数を複数回更新するとサンプルが取り込まれ sampleCount / lastValue が追従する。
        VariableStore.setValue("sensorTemp", 20);
        compare(trend.sampleCount, baseCount + 1);
        compare(trend.lastValue, 20);

        VariableStore.setValue("sensorTemp", 35);
        compare(trend.sampleCount, baseCount + 2);
        compare(trend.lastValue, 35);
    }

    // Task M-B（Phase 10）: type:"Meter" の delegate は HmiMeter を描き（他種別は描かない）、
    // live:true で binding {property:"value"} の指す変数へ針が追従する。変数を更新すると
    // 公開 displayValue / needleAngle が追従する（Canvas ピクセルは見ない）。
    function test_delegate_renders_meter_and_follows_value_binding() {
        canvas.variableModel = [{ name: "vehicleSpeed", type: "int", initial: 0 }];
        canvas.widgetModel = [{
            id: "m1", type: "Meter", x: 0, y: 0, width: 200, height: 200,
            meterMin: 0, hasMeterMin: true, meterMax: 100, hasMeterMax: true,
            bindings: [{ property: "value", variable: "vehicleSpeed" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_m1");
            return wrapper !== null;
        }, 1000, "Meter delegate widget_m1 が生成されない");

        var meter = null;
        tryVerify(function() {
            meter = findByObjectName(wrapper, "hmiMeter");
            return meter !== null;
        }, 1000, "Meter type で HmiMeter が描かれない");
        // 型分岐：他種別の Widget は生成されない。
        verify(findByObjectName(wrapper, "hmiButton") === null,
               "Meter type なのに HmiButton も生成された");
        verify(findByObjectName(wrapper, "hmiLabel") === null,
               "Meter type なのに HmiLabel も生成された");
        verify(findByObjectName(wrapper, "hmiTrend") === null,
               "Meter type なのに HmiTrend も生成された");

        // Simulator はライブ実行＝live:true。
        compare(meter.live, true);
        compare(meter.resolvedMeterMin, 0);
        compare(meter.resolvedMeterMax, 100);

        // 変数を更新すると displayValue / needleAngle が追従する。
        VariableStore.setValue("vehicleSpeed", 50);
        compare(meter.displayValue, 50);
        fuzzyCompare(meter.needleAngle, meter.startAngle + meter.spanAngle / 2, 0.001);

        VariableStore.setValue("vehicleSpeed", 100);
        compare(meter.displayValue, 100);
        fuzzyCompare(meter.needleAngle, meter.endAngle, 0.001);

        // 範囲外は clamp される。
        VariableStore.setValue("vehicleSpeed", 200);
        compare(meter.displayValue, 100);
    }

    // Task W-B（Phase 11）: type:"SimpleButton" の delegate は HmiSimpleButton を描き（他種別は
    // 描かない）、live:true でライブ実行する。checked は binding {property:"checked"} の指す変数へ
    // 追従（読み）し、長押し確定の toggled は writeBoundValue で同変数へ書き戻す（書き）。
    // Spix は実長押しを発火できないため、E2E と同様に toggled(value) シグナルを直接 emit して
    // 「押し続けて確定」を模す（widget は状態を持たず consumer が onToggled で書き戻す設計）。
    function test_delegate_renders_simple_button_and_toggle_writes_back() {
        canvas.variableModel = [{ name: "pumpRunning", type: "bool", initial: "false" }];
        canvas.widgetModel = [{
            id: "sb1", type: "SimpleButton", x: 0, y: 0, width: 180, height: 180,
            text: "TEST", shape: "circle", theme: "light", holdMs: 400,
            bindings: [{ property: "checked", variable: "pumpRunning" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_sb1");
            return wrapper !== null;
        }, 1000, "SimpleButton delegate widget_sb1 が生成されない");

        var sb = null;
        tryVerify(function() {
            sb = findByObjectName(wrapper, "hmiSimpleButton");
            return sb !== null;
        }, 1000, "SimpleButton type で HmiSimpleButton が描かれない");
        // 型分岐：他種別の Widget は生成されない。
        verify(findByObjectName(wrapper, "hmiButton") === null,
               "SimpleButton type なのに HmiButton も生成された");
        verify(findByObjectName(wrapper, "hmiMeter") === null,
               "SimpleButton type なのに HmiMeter も生成された");

        // Simulator はライブ実行＝live:true。
        compare(sb.live, true);

        // checked は変数 pumpRunning（false）に追従（読み）。
        compare(sb.checked, false);

        // 長押し確定を模す：toggled(true) を emit → onToggled が writeBoundValue で変数へ書き戻す。
        sb.toggled(true);
        compare(VariableStore.get("pumpRunning"), true);
        // 変数が変われば checked 表示も boundValue 再評価で追従する（読み書き両用 binding）。
        compare(sb.checked, true);

        // もう一度確定すると false へ戻る（トグル）。
        sb.toggled(false);
        compare(VariableStore.get("pumpRunning"), false);
        compare(sb.checked, false);
    }

    // Task W-B（Codex PR #164 [P2]）: enabled=false の SimpleButton は長押し確定（toggled）でも
    // checked binding 先の変数へ書き戻さない（Button の runClickActions と同じ「無効＝操作で変数を
    // 更新しない」契約。writeBoundValue が runClickActions より前に走るため onToggled 先頭でガードする）。
    function test_disabled_simple_button_toggle_is_noop() {
        canvas.variableModel = [{ name: "pumpRunning", type: "bool", initial: "false" }];
        canvas.widgetModel = [{
            id: "sb1", type: "SimpleButton", x: 0, y: 0, width: 180, height: 180,
            text: "TEST", enabled: false,
            bindings: [{ property: "checked", variable: "pumpRunning" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_sb1");
            return wrapper !== null;
        }, 1000, "SimpleButton delegate widget_sb1 が生成されない");
        var sb = null;
        tryVerify(function() {
            sb = findByObjectName(wrapper, "hmiSimpleButton");
            return sb !== null;
        }, 1000, "HmiSimpleButton が描かれない");

        compare(VariableStore.get("pumpRunning"), false);
        sb.toggled(true);   // disabled なので書き戻さない（no-op）
        compare(VariableStore.get("pumpRunning"), false);  // 変化なし
    }

    // Task W-B（Codex PR #164 [P2]）: checked binding と同じ変数を指す toggleVariable アクションを
    // 併記しても、長押し確定（toggled）は writeBoundValue だけで書き戻し **二重トグルで打ち消さない**。
    // onToggled が runClickActions を呼ばない設計の回帰固定（呼ぶと writeBoundValue の次値を action の
    // toggleVariable が直後に再反転し、最終値が元へ戻って操作が実質無効になる）。
    function test_simple_button_toggle_does_not_double_toggle() {
        canvas.variableModel = [{ name: "pumpRunning", type: "bool", initial: "false" }];
        canvas.widgetModel = [{
            id: "sb1", type: "SimpleButton", x: 0, y: 0, width: 180, height: 180, text: "TEST",
            bindings: [{ property: "checked", variable: "pumpRunning" }],
            actions: [{ trigger: "onClick", op: "toggleVariable", target: "pumpRunning" }]
        }];

        var wrapper = null;
        tryVerify(function() {
            wrapper = findByObjectName(canvas, "widget_sb1");
            return wrapper !== null;
        }, 1000, "SimpleButton delegate widget_sb1 が生成されない");
        var sb = null;
        tryVerify(function() {
            sb = findByObjectName(wrapper, "hmiSimpleButton");
            return sb !== null;
        }, 1000, "HmiSimpleButton が描かれない");

        // 長押し確定 → writeBoundValue のみで pumpRunning=true。action の toggleVariable は
        // 実行されない（＝再反転しない）ので最終値は true のまま。
        sb.toggled(true);
        compare(VariableStore.get("pumpRunning"), true);
        compare(sb.checked, true);
    }
}
