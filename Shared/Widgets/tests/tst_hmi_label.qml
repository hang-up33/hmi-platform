import QtQuick
import QtTest
import HmiWidgets

// Task 47: HmiLabel（表示専用 Widget）のプロパティ反映・既定フォールバック・
// クリックシグナル検証。HmiButton（tst_hmi_button.qml）と同方式。
//
// 観点：
//   - デフォルトプロパティ（text="Label", width=120, height=40）
//   - resolved* 既定（背景=透明 / 文字色=#1d3557 / fontSize=14 / hAlign=左 / vAlign=中央 /
//     opacity=1.0）が HmiLabel 1 箇所に集約されている（Button と違う既定差分を固定）
//   - text を変更すると内部の Text 要素にも反映される
//   - MouseArea のクリックで clicked シグナルが発火する（選択中継用）
//
// 重要：TestCase に visible: true を明示する（tst_hmi_button.qml と同じ理由＝
//   MouseArea がクリックを受けるため）。
TestCase {
    id: testCase
    name: "HmiLabel"
    when: windowShown
    visible: true
    width: 200
    height: 100

    HmiLabel {
        id: label
        x: 0
        y: 0
    }

    SignalSpy {
        id: clickedSpy
        target: label
        signalName: "clicked"
    }

    function init() {
        // 各 test_* 実行前にプロパティをリセット
        label.text = "Label";
        label.width = 120;
        label.height = 40;
        label.backgroundColor = "";
        label.textColor = "";
        label.fontSize = 0;
        label.hAlign = "";
        label.vAlign = "";
        label.widgetOpacity = -1;
        label.widgetEnabled = true;
        clickedSpy.clear();
    }

    function test_default_properties() {
        compare(label.text, "Label");
        compare(label.width, 120);
        compare(label.height, 40);
    }

    // 未指定（空 / 0 / -1）のとき resolved* が **Label の既定**にフォールバックする。
    // Button との既定差分（背景=透明 / 文字色=濃色 / hAlign=左寄せ）を固定する。
    function test_resolved_defaults_when_unspecified() {
        // 背景は透明（Button の #4cc9f0 とは違う）。
        compare(label.resolvedBackgroundColor, Qt.color("transparent"));
        // 文字色は濃色 #1d3557（Button の white とは違う）。
        compare(label.resolvedTextColor, Qt.color("#1d3557"));
        compare(label.resolvedFontSize, 14);
        // 配置の既定は左寄せ / 中央（Button は中央 / 中央）。
        compare(label.resolvedHAlign, Text.AlignLeft);
        compare(label.resolvedVAlign, Text.AlignVCenter);
        compare(label.resolvedOpacity, 1.0);
        // 既定はフラット（ボーダーなし）。
        compare(label.border.width, 0);
    }

    // 明示値が resolved* と描画へ反映される（配置の文字列 → enum マップを含む）。
    function test_explicit_values_are_resolved() {
        label.backgroundColor = "#ffeeaa";
        label.textColor = "#222222";
        label.fontSize = 20;
        label.hAlign = "center";
        label.vAlign = "top";

        compare(label.resolvedBackgroundColor, Qt.color("#ffeeaa"));
        compare(label.resolvedTextColor, Qt.color("#222222"));
        compare(label.resolvedFontSize, 20);
        compare(label.resolvedHAlign, Text.AlignHCenter);
        compare(label.resolvedVAlign, Text.AlignTop);
    }

    function test_text_property_is_reflected() {
        label.text = "Temperature";
        compare(label.text, "Temperature");

        const innerText = findChildOfType(label, "QQuickText");
        verify(innerText !== null);
        compare(innerText.text, "Temperature");

        label.text = "Pressure";
        compare(innerText.text, "Pressure");
    }

    // 選択中継用の clicked シグナルがクリックで発火する（Editor の選択に使う）。
    function test_click_emits_clicked_signal() {
        compare(clickedSpy.count, 0);

        mouseClick(label, label.width / 2, label.height / 2);
        compare(clickedSpy.count, 1);

        mouseClick(label, label.width / 2, label.height / 2);
        compare(clickedSpy.count, 2);
    }

    // QQuickItem ツリーから指定された型名の最初の子を再帰的に探す（tst_hmi_button と同じ）。
    function findChildOfType(item, typeName) {
        if (!item)
            return null;
        const items = item.children;
        for (let i = 0; i < items.length; ++i) {
            const c = items[i];
            if (c.toString().indexOf(typeName) === 0)
                return c;
            const nested = findChildOfType(c, typeName);
            if (nested)
                return nested;
        }
        return null;
    }
}
