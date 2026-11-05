import QtQuick

// Task RF-E: Label 種別版の ButtonHost（コメントの詳細は ButtonHost.qml
// 参照）。Label は表示専用のため checkable / checked / tag / border / cornerRadius
// を持たない（HmiLabel 自体が持たないのと対称）。
Item {
    id: hostRoot

    // HmiLabel の入力名をキーに持つ静的値の束。
    required property var widget

    // binding 追従の読み取りフック。null（既定）なら追従しない（Editor）。
    // 渡す場合は function(propertyName) -> 変数の生の値 or undefined（Simulator）。
    property var resolveBound: null

    // 選択中継（Editor）用のクリック通知。Simulator の Label は表示専用のため
    // 呼び出し側で接続しない（HmiLabel.clicked は発火するが誰も聞いていない no-op）。
    signal clicked(int modifiers)

    function resolvedText(prop, staticValue) {
        if (hostRoot.resolveBound !== null) {
            const v = hostRoot.resolveBound(prop)
            if (v !== undefined) {
                return String(v)
            }
        }
        return staticValue !== undefined ? staticValue : ""
    }

    HmiLabel {
        // Task 47 由来の objectName（ButtonHost の hmiButton と対）。
        objectName: "hmiLabel"
        anchors.fill: parent

        text: hostRoot.resolvedText("text", hostRoot.widget.text)
        backgroundColor: hostRoot.resolvedText("backgroundColor", hostRoot.widget.backgroundColor)
        textColor: hostRoot.resolvedText("textColor", hostRoot.widget.textColor)
        fontSize: hostRoot.widget.fontSize !== undefined ? hostRoot.widget.fontSize : 0
        fontBold: hostRoot.widget.fontBold !== undefined ? hostRoot.widget.fontBold : false
        fontItalic: hostRoot.widget.fontItalic !== undefined ? hostRoot.widget.fontItalic : false
        fontFamily: hostRoot.widget.fontFamily !== undefined ? hostRoot.widget.fontFamily : ""
        hAlign: hostRoot.widget.hAlign !== undefined ? hostRoot.widget.hAlign : ""
        vAlign: hostRoot.widget.vAlign !== undefined ? hostRoot.widget.vAlign : ""
        widgetOpacity: hostRoot.widget.widgetOpacity !== undefined ? hostRoot.widget.widgetOpacity : -1
        widgetEnabled: hostRoot.widget.widgetEnabled !== undefined ? hostRoot.widget.widgetEnabled : true

        onClicked: function(modifiers) { hostRoot.clicked(modifiers) }
    }
}
