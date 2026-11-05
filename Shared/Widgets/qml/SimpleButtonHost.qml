import QtQuick

// Task RF-E: SimpleButton 版の ButtonHost（コメントの詳細は ButtonHost.qml 参照）。
// ButtonHost / LabelHost と同じ「resolveBound フックで Editor(静的)/Simulator(binding
// 追従) の非対称性を吸収する」設計をそのまま踏襲する。SimpleButton 固有の差分は 2 点：
//   - `live`（長押し進捗を動かすか）は Schema 由来の値ではなく delegate が持つ
//     「設計面 vs 実行面」のモード切替なので、widget オブジェクトに含めず Host の
//     独立プロパティにする（Editor は false のまま・Simulator は true を渡す）。
//   - クリックで選択中継する `clicked` に加え、長押し確定の「次値」を通知する
//     `toggled(bool value)` を中継する（Simulator だけが onToggled を接続して
//     writeBoundValue で変数へ書き戻す。Editor は接続しなくてよい）。
Item {
    id: hostRoot

    // HmiSimpleButton の入力名をキーに持つ静的値の束
    // （text, shape, theme, accentColor, holdMs, checked, widgetOpacity, widgetEnabled）。
    required property var widget

    // 長押し進捗を動かすか（Editor=false 固定 / Simulator=true）。Schema 値ではないため
    // widget オブジェクトに含めない。
    property bool live: false

    // binding 追従の読み取りフック。null（既定）なら追従しない（Editor）。
    // 渡す場合は function(propertyName) -> 変数の生の値 or undefined（Simulator）。
    property var resolveBound: null

    // 選択中継（Editor）用のクリック通知。Simulator の SimpleButton は clicked を
    // 接続しない（runClickActions は使わず toggled 経由の書き戻し一本化のため）。
    signal clicked(int modifiers)

    // 長押し確定で得た「次値」の通知（Simulator が checked binding 先へ書き戻すのに使う）。
    signal toggled(bool value)

    function resolvedText(prop, staticValue) {
        if (hostRoot.resolveBound !== null) {
            const v = hostRoot.resolveBound(prop)
            if (v !== undefined) {
                return String(v)
            }
        }
        return staticValue !== undefined ? staticValue : ""
    }

    function resolvedBool(prop, staticValue) {
        if (hostRoot.resolveBound !== null) {
            const v = hostRoot.resolveBound(prop)
            if (v !== undefined) {
                return VariableStore.coerce("bool", v)
            }
        }
        return staticValue !== undefined ? staticValue : false
    }

    HmiSimpleButton {
        // Task W-B 由来の objectName（ButtonHost の hmiButton と対）。
        objectName: "hmiSimpleButton"
        anchors.fill: parent
        live: hostRoot.live

        text: hostRoot.resolvedText("text", hostRoot.widget.text)
        shape: hostRoot.widget.shape !== undefined ? hostRoot.widget.shape : ""
        theme: hostRoot.widget.theme !== undefined ? hostRoot.widget.theme : ""
        accentColor: hostRoot.widget.accentColor !== undefined ? hostRoot.widget.accentColor : ""
        holdMs: hostRoot.widget.holdMs !== undefined ? hostRoot.widget.holdMs : 0
        checked: hostRoot.resolvedBool("checked", hostRoot.widget.checked)
        widgetOpacity: hostRoot.widget.widgetOpacity !== undefined ? hostRoot.widget.widgetOpacity : -1
        widgetEnabled: hostRoot.widget.widgetEnabled !== undefined ? hostRoot.widget.widgetEnabled : true

        onClicked: function(modifiers) { hostRoot.clicked(modifiers) }
        onToggled: function(value) { hostRoot.toggled(value) }
    }
}
