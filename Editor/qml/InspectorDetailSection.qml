import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「詳細（Tag / 最小値・最大値。既定で閉）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: detailSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null

    // このセクション内の入力欄が編集フォーカス中か。InspectorPanel の
    // widgetEditFieldFocused（Canvas undo の 1 操作境界）がこれを OR する。
    readonly property bool editFieldFocused:
        inspectorTagField.activeFocus
        || inspectorMinValueField.activeFocus
        || inspectorMaxValueField.activeFocus
    objectName: "inspectorDetailSection"
    title: qsTr("詳細")
    expanded: false

    // Task 54: 数値範囲（min / max）。NumericField のときだけ可視
    //（他種別では visible:false。型出し分けは visible のみ＝objectName・
    // 編集ロジック・Schema 不変）。空欄 = 未指定（has*=false）、値を入れると
    // has*=true。**負値・小数も許す**ため validator は「空 または 数値」を許可する
    // RegularExpressionValidator にする（DoubleValidator は空文字を弾くため不可）。
    // 2 本立て：onTextEdited で live Item へ書き戻し（widgetMin/MaxValue + has*）、
    // Connections.onSelectedItemChanged で表示同期。
    Label {
        text: qsTr("範囲 最小値")
        visible: editorInspector.selectedIsNumericField
    }
    TextField {
        id: inspectorMinValueField
        objectName: "inspectorMinValueField"
        width: parent.width
        visible: editorInspector.selectedIsNumericField
        placeholderText: qsTr("(未指定)")
        onActiveFocusChanged: if (activeFocus) selectAll()
        // 空 または 任意符号付き整数 / 小数（先頭 `-`・小数点・指数なし）。
        validator: RegularExpressionValidator {
            regularExpression: /^(-?\d*\.?\d*)$/
        }
        ToolTip.text: qsTr("入力可能な最小値。空欄で未指定（下限なし）。確定時に範囲外は境界へ丸めます")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                // 空 / 符号のみ / 小数点のみは「未指定」（has=false）扱い。
                var t = text.trim()
                var n = Number(t)
                if (t === "" || t === "-" || t === "." || isNaN(n)) {
                    editorInspector.editorCanvas.selectedItem.widgetHasMin = false
                } else {
                    editorInspector.editorCanvas.selectedItem.widgetMinValue = n
                    editorInspector.editorCanvas.selectedItem.widgetHasMin = true
                }
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorMinValueField.text =
                    (editorInspector.editorCanvas.selectedItem && editorInspector.editorCanvas.selectedItem.widgetHasMin)
                        ? String(editorInspector.editorCanvas.selectedItem.widgetMinValue) : ""
            }
        }
    }

    Label {
        text: qsTr("範囲 最大値")
        visible: editorInspector.selectedIsNumericField
    }
    TextField {
        id: inspectorMaxValueField
        objectName: "inspectorMaxValueField"
        width: parent.width
        visible: editorInspector.selectedIsNumericField
        placeholderText: qsTr("(未指定)")
        onActiveFocusChanged: if (activeFocus) selectAll()
        validator: RegularExpressionValidator {
            regularExpression: /^(-?\d*\.?\d*)$/
        }
        ToolTip.text: qsTr("入力可能な最大値。空欄で未指定（上限なし）。確定時に範囲外は境界へ丸めます")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                var t = text.trim()
                var n = Number(t)
                if (t === "" || t === "-" || t === "." || isNaN(n)) {
                    editorInspector.editorCanvas.selectedItem.widgetHasMax = false
                } else {
                    editorInspector.editorCanvas.selectedItem.widgetMaxValue = n
                    editorInspector.editorCanvas.selectedItem.widgetHasMax = true
                }
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorMaxValueField.text =
                    (editorInspector.editorCanvas.selectedItem && editorInspector.editorCanvas.selectedItem.widgetHasMax)
                        ? String(editorInspector.editorCanvas.selectedItem.widgetMaxValue) : ""
            }
        }
    }

    Label {
        objectName: "inspectorIdLabel"
        color: "#555555"
        text: qsTr("ID: ") + (editorInspector.editorCanvas.selectedItem
            ? editorInspector.editorCanvas.selectedItem.widgetId : "")
    }

    // Task 45: 旧ラベル「Tag」は何に使うか不明瞭だったため
    //「外部タグ（PLC等）」へ明確化。現状は保存（round-trip）のみで
    // 描画・動作には未使用＝将来の PLC アドレス連携用フィールド。
    Label { text: qsTr("外部タグ（PLC等）") }
    TextField {
        id: inspectorTagField
        objectName: "inspectorTagField"
        width: parent.width
        placeholderText: qsTr("例: PLC.D100（任意）")
        ToolTip.text: qsTr("PLC アドレス等の外部識別子。現在は保存されるだけで描画・動作には使われません（将来の連携用）")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetTag = text
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorTagField.text = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetTag : ""
            }
        }
    }
}
