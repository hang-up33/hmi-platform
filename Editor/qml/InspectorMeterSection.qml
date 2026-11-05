import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「Meter 詳細（範囲 / 弧色 / 針色 / 目盛り数 / 単位）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: meterSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null

    // このセクション内の入力欄が編集フォーカス中か。InspectorPanel の
    // widgetEditFieldFocused（Canvas undo の 1 操作境界）がこれを OR する。
    readonly property bool editFieldFocused:
        inspectorMeterMinField.activeFocus
        || inspectorMeterMaxField.activeFocus
        || inspectorArcColorField.activeFocus
        || inspectorNeedleColorField.activeFocus
        || inspectorTickCountSpin.activeFocus
        || inspectorUnitField.activeFocus
    objectName: "inspectorMeterSection"
    title: qsTr("Meter 詳細")
    visible: editorInspector.selectedIsMeter

    // 範囲 最小値（presence 方式）。空欄 = 未指定（hasMeterMin=false → 既定 0）、
    // 値を入れると hasMeterMin=true。負値・小数も許す（Trend Y 軸 min と同型の
    // RegularExpressionValidator＝空 または 数値）。
    Label { text: qsTr("範囲 最小値") }
    TextField {
        id: inspectorMeterMinField
        objectName: "inspectorMeterMinField"
        width: parent.width
        placeholderText: qsTr("(既定 0)")
        onActiveFocusChanged: if (activeFocus) selectAll()
        validator: RegularExpressionValidator {
            regularExpression: /^(-?\d*\.?\d*)$/
        }
        ToolTip.text: qsTr("メーターの下限値（針が振れ始める値）。空欄で既定 0")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                var t = text.trim()
                var nv = Number(t)
                if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                    editorInspector.editorCanvas.selectedItem.widgetHasMeterMin = false
                } else {
                    editorInspector.editorCanvas.selectedItem.widgetMeterMin = nv
                    editorInspector.editorCanvas.selectedItem.widgetHasMeterMin = true
                }
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorMeterMinField.text =
                    (editorInspector.editorCanvas.selectedItem && editorInspector.editorCanvas.selectedItem.widgetHasMeterMin)
                        ? String(editorInspector.editorCanvas.selectedItem.widgetMeterMin) : ""
            }
        }
    }

    Label { text: qsTr("範囲 最大値") }
    TextField {
        id: inspectorMeterMaxField
        objectName: "inspectorMeterMaxField"
        width: parent.width
        placeholderText: qsTr("(既定 100)")
        onActiveFocusChanged: if (activeFocus) selectAll()
        validator: RegularExpressionValidator {
            regularExpression: /^(-?\d*\.?\d*)$/
        }
        ToolTip.text: qsTr("メーターの上限値（針が振り切る値）。空欄で既定 100")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                var t = text.trim()
                var nv = Number(t)
                if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                    editorInspector.editorCanvas.selectedItem.widgetHasMeterMax = false
                } else {
                    editorInspector.editorCanvas.selectedItem.widgetMeterMax = nv
                    editorInspector.editorCanvas.selectedItem.widgetHasMeterMax = true
                }
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorMeterMaxField.text =
                    (editorInspector.editorCanvas.selectedItem && editorInspector.editorCanvas.selectedItem.widgetHasMeterMax)
                        ? String(editorInspector.editorCanvas.selectedItem.widgetMeterMax) : ""
            }
        }
    }

    // 弧色（"#RRGGBB" hex の TextField + 色スウォッチ）。背景色等と同じ
    // 2 本立て + ColorDialog 起動（Task 46）。空 = 未指定＝既定弧色 #4cc9f0。
    Label { text: qsTr("弧色 (#RRGGBB)") }
    Row {
        width: parent.width - parent.leftPadding
        spacing: 6

        TextField {
            id: inspectorArcColorField
            objectName: "inspectorArcColorField"
            width: parent.width - editorInspector.colorSwatchReserve
            placeholderText: qsTr("#4cc9f0")
            validator: RegularExpressionValidator {
                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
            }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.widgetArcColor = text
                }
            }
            Connections {
                target: editorInspector.editorCanvas
                function onSelectedItemChanged() {
                    inspectorArcColorField.text = editorInspector.editorCanvas.selectedItem
                        ? editorInspector.editorCanvas.selectedItem.widgetArcColor : ""
                }
            }
        }
        ColorSwatch {
            inspector: editorInspector
            objectName: "inspectorArcColorSwatch"
            anchors.verticalCenter: parent.verticalCenter
            field: inspectorArcColorField
            targetProperty: "widgetArcColor"
            // HmiMeter.resolvedArcColor の既定と揃える。
            fallback: "#4cc9f0"
        }
    }

    // 針色（"#RRGGBB" hex の TextField + 色スウォッチ）。空 = 既定針色 #ff595e。
    Label { text: qsTr("針色 (#RRGGBB)") }
    Row {
        width: parent.width - parent.leftPadding
        spacing: 6

        TextField {
            id: inspectorNeedleColorField
            objectName: "inspectorNeedleColorField"
            width: parent.width - editorInspector.colorSwatchReserve
            placeholderText: qsTr("#ff595e")
            validator: RegularExpressionValidator {
                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
            }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.widgetNeedleColor = text
                }
            }
            Connections {
                target: editorInspector.editorCanvas
                function onSelectedItemChanged() {
                    inspectorNeedleColorField.text = editorInspector.editorCanvas.selectedItem
                        ? editorInspector.editorCanvas.selectedItem.widgetNeedleColor : ""
                }
            }
        }
        ColorSwatch {
            inspector: editorInspector
            objectName: "inspectorNeedleColorSwatch"
            anchors.verticalCenter: parent.verticalCenter
            field: inspectorNeedleColorField
            targetProperty: "widgetNeedleColor"
            // HmiMeter.resolvedNeedleColor の既定と揃える。
            fallback: "#ff595e"
        }
    }

    // 目盛り数。0/未指定は HmiMeter 側で既定 10 へ解決。SpinBox（editable なし）で
    // from を 0（=既定）にする。
    Label { text: qsTr("目盛り数") }
    SpinBox {
        id: inspectorTickCountSpin
        objectName: "inspectorTickCountSpin"
        from: 0
        to: 50
        value: 0
        ToolTip.text: qsTr("弧上の目盛り本数。0 で既定（10 本）")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetTickCount = value
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                // 0/未指定はそのまま 0（＝既定 10 本）を表示する。
                inspectorTickCountSpin.value = (it && it.widgetTickCount > 0)
                    ? it.widgetTickCount : 0
            }
        }
    }

    // 単位（中央数値に付く。例 "km/h"）。空 = 単位表示なし。素の TextField。
    Label { text: qsTr("単位") }
    TextField {
        id: inspectorUnitField
        objectName: "inspectorUnitField"
        width: parent.width
        placeholderText: qsTr("例: km/h（任意）")
        ToolTip.text: qsTr("中央の数値に付く単位ラベル。空欄で単位表示なし")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetUnit = text
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorUnitField.text = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetUnit : ""
            }
        }
    }
}
