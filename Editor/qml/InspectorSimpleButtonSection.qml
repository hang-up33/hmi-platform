import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「シンプルボタン詳細（形状 / テーマ / 差し色 / 長押し時間）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: simpleButtonSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null

    // このセクション内の入力欄が編集フォーカス中か。InspectorPanel の
    // widgetEditFieldFocused（Canvas undo の 1 操作境界）がこれを OR する。
    readonly property bool editFieldFocused:
        inspectorShapeCombo.activeFocus
        || inspectorThemeCombo.activeFocus
        || inspectorAccentColorField.activeFocus
        || inspectorHoldMsSpin.activeFocus
    objectName: "inspectorSimpleButtonSection"
    title: qsTr("シンプルボタン詳細")
    visible: editorInspector.selectedIsSimpleButton

    Label { text: qsTr("形状") }
    ComboBox {
        id: inspectorShapeCombo
        objectName: "inspectorShapeCombo"
        width: parent.width
        readonly property var values: ["", "circle", "square"]
        model: [qsTr("(既定:円形)"), qsTr("円形"), qsTr("四角")]
        ToolTip.text: qsTr("ボタンの面の形。円形は進捗リング、四角は進捗バーで長押しを表します")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onActivated: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetShape = values[currentIndex]
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                const v = it ? it.widgetShape : ""
                const idx = inspectorShapeCombo.values.indexOf(v)
                inspectorShapeCombo.currentIndex = idx >= 0 ? idx : 0
            }
        }
    }

    Label { text: qsTr("テーマ") }
    ComboBox {
        id: inspectorThemeCombo
        objectName: "inspectorThemeCombo"
        width: parent.width
        readonly property var values: ["", "light", "dark"]
        model: [qsTr("(既定:ライト)"), qsTr("ライト"), qsTr("ダーク")]
        ToolTip.text: qsTr("面・文字・影の配色テーマ。背景色や枠はテーマが決めます")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onActivated: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetTheme = values[currentIndex]
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                const v = it ? it.widgetTheme : ""
                const idx = inspectorThemeCombo.values.indexOf(v)
                inspectorThemeCombo.currentIndex = idx >= 0 ? idx : 0
            }
        }
    }

    // 差し色（"#RRGGBB" hex の TextField + 色スウォッチ）。空 = 未指定＝
    // テーマ既定の緑（light #2fa563 / dark #56d68a）へ HmiSimpleButton 側で解決。
    Label { text: qsTr("差し色 (#RRGGBB)") }
    Row {
        width: parent.width - parent.leftPadding
        spacing: 6

        TextField {
            id: inspectorAccentColorField
            objectName: "inspectorAccentColorField"
            width: parent.width - editorInspector.colorSwatchReserve
            placeholderText: qsTr("(既定: テーマの緑)")
            validator: RegularExpressionValidator {
                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
            }
            ToolTip.text: qsTr("ランプ・進捗・ON 表示に使うアクセント色。空欄でテーマ既定の緑")
            ToolTip.visible: hovered
            ToolTip.delay: 600
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.widgetAccentColor = text
                }
            }
            Connections {
                target: editorInspector.editorCanvas
                function onSelectedItemChanged() {
                    inspectorAccentColorField.text = editorInspector.editorCanvas.selectedItem
                        ? editorInspector.editorCanvas.selectedItem.widgetAccentColor : ""
                }
            }
        }
        ColorSwatch {
            inspector: editorInspector
            objectName: "inspectorAccentColorSwatch"
            anchors.verticalCenter: parent.verticalCenter
            field: inspectorAccentColorField
            targetProperty: "widgetAccentColor"
            // HmiSimpleButton の light テーマ既定 accent と揃える。
            fallback: "#2fa563"
        }
    }

    // 長押し時間 [ms]。0 = 未指定＝HmiSimpleButton 側で既定 800ms へ解決
    //（tickCount と同じ 0 センチネル）。editable なし SpinBox（矢印で増減）。
    Label { text: qsTr("長押し時間 [ms]") }
    SpinBox {
        id: inspectorHoldMsSpin
        objectName: "inspectorHoldMsSpin"
        from: 0
        to: 10000
        stepSize: 100
        value: 0
        ToolTip.text: qsTr("押し続けて ON/OFF が確定するまでの時間。0 で既定（800ms）")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetHoldMs = value
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                // 0/未指定はそのまま 0（＝既定 800ms）を表示する。
                inspectorHoldMsSpin.value = (it && it.widgetHoldMs > 0)
                    ? it.widgetHoldMs : 0
            }
        }
    }
}
