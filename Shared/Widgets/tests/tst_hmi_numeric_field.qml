import QtQuick
import QtTest
import HmiWidgets

// Task 50: HmiNumericField（数値入力 Widget）のプロパティ反映・既定フォールバック・
// editable 切替・選択中継 clicked・commitValue()/valueCommitted の検証。
// HmiButton / HmiLabel（tst_hmi_button.qml / tst_hmi_label.qml）と同方式。
//
// 観点：
//   - デフォルトプロパティ（text="0", editable=true, width=120, height=40）
//   - resolved* 既定（背景=#ffffff / 文字色=#1d3557 / fontSize=14 / 枠=#9aa5b1・幅 1 /
//     角丸 4 / hAlign=右 / vAlign=中央 / opacity=1.0）が HmiNumericField 1 箇所に集約
//     されている（入力欄らしい既定。Button の塗り・Label の透明とは違う差分を固定）
//   - editable を切替えると内部 TextField の readOnly と選択用 MouseArea の enabled が反転
//   - editable:false（Editor）で選択用 MouseArea のクリックが clicked シグナルを発火する
//   - commitValue() で valueCommitted(text) が emit される（write 経路は delegate 側＝Task 51）
//
// 重要：TestCase に visible: true を明示する（tst_hmi_button.qml と同じ理由＝
//   MouseArea / TextField がクリック・フォーカスを受けるため）。
TestCase {
    id: testCase
    name: "HmiNumericField"
    when: windowShown
    visible: true
    width: 200
    height: 100

    HmiNumericField {
        id: field
        x: 0
        y: 0
    }

    SignalSpy {
        id: clickedSpy
        target: field
        signalName: "clicked"
    }

    SignalSpy {
        id: committedSpy
        target: field
        signalName: "valueCommitted"
    }

    function init() {
        // 各 test_* 実行前にプロパティをリセット
        field.text = "0";
        field.editable = true;
        field.width = 120;
        field.height = 40;
        field.backgroundColor = "";
        field.textColor = "";
        field.fontSize = 0;
        field.borderColor = "";
        field.borderWidth = -1;
        field.cornerRadius = -1;
        field.hAlign = "";
        field.vAlign = "";
        field.widgetOpacity = -1;
        field.widgetEnabled = true;
        clickedSpy.clear();
        committedSpy.clear();
    }

    function test_default_properties() {
        compare(field.text, "0");
        compare(field.editable, true);
        compare(field.width, 120);
        compare(field.height, 40);
    }

    // 未指定（空 / 0 / -1）のとき resolved* が **NumericField の既定**にフォールバックする。
    // 入力欄らしい既定（白背景 / 濃文字 / 細グレー枠 / 角丸 4 / 右寄せ）を固定する。
    function test_resolved_defaults_when_unspecified() {
        compare(field.resolvedBackgroundColor, Qt.color("#ffffff"));
        compare(field.resolvedTextColor, Qt.color("#1d3557"));
        compare(field.resolvedFontSize, 14);
        compare(field.resolvedBorderColor, Qt.color("#9aa5b1"));
        compare(field.resolvedBorderWidth, 1);
        compare(field.resolvedCornerRadius, 4);
        // 数値入力の既定配置は右寄せ / 中央（Button=中央/中央・Label=左/中央 とは違う）。
        compare(field.resolvedHAlign, Text.AlignRight);
        compare(field.resolvedVAlign, Text.AlignVCenter);
        compare(field.resolvedOpacity, 1.0);
    }

    // 明示値が resolved* へ反映される（配置の文字列 → enum マップを含む）。
    function test_explicit_values_are_resolved() {
        field.backgroundColor = "#222222";
        field.textColor = "#ffffff";
        field.fontSize = 20;
        field.borderColor = "#ff0000";
        field.borderWidth = 3;
        field.cornerRadius = 8;
        field.hAlign = "left";
        field.vAlign = "top";

        compare(field.resolvedBackgroundColor, Qt.color("#222222"));
        compare(field.resolvedTextColor, Qt.color("#ffffff"));
        compare(field.resolvedFontSize, 20);
        compare(field.resolvedBorderColor, Qt.color("#ff0000"));
        compare(field.resolvedBorderWidth, 3);
        compare(field.resolvedCornerRadius, 8);
        compare(field.resolvedHAlign, Text.AlignLeft);
        compare(field.resolvedVAlign, Text.AlignTop);
    }

    // text を変更すると内部の TextField にも反映される。
    function test_text_property_is_reflected() {
        field.text = "42";
        compare(field.text, "42");
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null);
        compare(tf.text, "42");
    }

    // editable を切替えると内部 TextField の readOnly と選択用 MouseArea の enabled が反転する。
    //   editable:true（Simulator）→ TextField 入力可（readOnly:false）・選択 MouseArea 無効
    //   editable:false（Editor）  → TextField 読取専用（readOnly:true）・選択 MouseArea 有効
    function test_editable_toggles_readonly_and_select_area() {
        const tf = findByObjectName(field, "numericTextField");
        const ma = findByObjectName(field, "numericSelectArea");
        verify(tf !== null, "内部 TextField が見つからない");
        verify(ma !== null, "選択用 MouseArea が見つからない");

        // 既定 editable:true（Simulator）
        compare(tf.readOnly, false);
        compare(ma.enabled, false);

        // editable:false（Editor）に切替
        field.editable = false;
        compare(tf.readOnly, true);
        compare(ma.enabled, true);
    }

    // editable:false（Editor）のとき選択用 MouseArea のクリックで clicked が発火する
    //（Button / Label と一様の選択中継）。
    function test_click_emits_clicked_signal_when_not_editable() {
        field.editable = false;
        compare(clickedSpy.count, 0);
        mouseClick(field, field.width / 2, field.height / 2);
        compare(clickedSpy.count, 1);
    }

    // commitValue() は現在の TextField テキストを確定し valueCommitted(text) を emit する
    //（delegate がこれを受けて変数へ write する＝Task 51。Task 50 では口だけ用意）。
    function test_commit_value_emits_value_committed() {
        field.text = "7";
        compare(committedSpy.count, 0);
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "7");
    }

    // QQuickItem ツリーから指定された objectName の子を再帰的に探す
    //（tst_canvas.qml / tst_simulator_canvas.qml と同じ流儀）。
    function findByObjectName(node, name) {
        if (!node)
            return null;
        if (node.objectName === name)
            return node;
        const kids = node.children;
        if (kids) {
            for (let i = 0; i < kids.length; ++i) {
                const found = findByObjectName(kids[i], name);
                if (found)
                    return found;
            }
        }
        return null;
    }
}
