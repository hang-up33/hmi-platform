import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「状態（有効 / トグル / 初期オン）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: stateSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null
    title: qsTr("状態")
    visible: !editorInspector.selectedIsLabel

    // Task 42 / 45: 状態別スタイル（有効 / トグルボタンにする / 初期状態をオン）。
    // フォント CheckBox と同じ 2 本立て + 明示 beginEdit/commitEdit。
    // Task 45: 直訳ラベル（チェック可能 / チェック状態）は意味が伝わりにくいため
    // 動作ベースの語へ言い換え、ToolTip で 1 行の補足を付ける（hover で表示）。
    CheckBox {
        id: inspectorEnabledCheck
        objectName: "inspectorEnabledCheck"
        text: qsTr("有効")
        ToolTip.text: qsTr("OFF にすると淡色表示になり、実行時（Simulator / Runtime）はクリックを受け付けません")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onToggled: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.beginEdit()
                editorInspector.editorCanvas.selectedItem.widgetEnabled = checked
                editorInspector.editorCanvas.commitEdit()
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                // enabled は既定 true。未選択時も true 表示にする。
                inspectorEnabledCheck.checked = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetEnabled : true
            }
        }
    }

    CheckBox {
        id: inspectorCheckableCheck
        objectName: "inspectorCheckableCheck"
        text: qsTr("トグルボタンにする")
        // Task 51: トグル / 初期オンは Button 専用（NumericField は「有効」のみ）。
        visible: editorInspector.selectedSupportsClickAction
        ToolTip.text: qsTr("ON にすると、クリックのたびに押下状態（オン / オフ）が切り替わるトグルボタンになります")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onToggled: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.beginEdit()
                editorInspector.editorCanvas.selectedItem.widgetCheckable = checked
                editorInspector.editorCanvas.commitEdit()
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorCheckableCheck.checked = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetCheckable : false
            }
        }
    }

    CheckBox {
        id: inspectorCheckedCheck
        objectName: "inspectorCheckedCheck"
        text: qsTr("状態をオン")
        // Task 51: トグル / 状態オンは Button 専用（NumericField は「有効」のみ）。
        // Task W-E: SimpleButton も ON/OFF（checked）を持つため出す（クリック
        // アクション非対応でも checked は編集できる。トグル化 checkable は
        // SimpleButton では常時トグルなので出さない）。
        visible: editorInspector.selectedSupportsClickAction
                 || editorInspector.selectedIsSimpleButton
        // PR #110: checked の ON 外観は checkable 非依存になった（PR #109 修正）。
        // よって checked 編集も checkable でゲートしない（checkable:false の
        // 状態表示〔ランプ/インジケータ〕用 JSON でも直接 ON/OFF を編集できる）。
        ToolTip.text: qsTr("ボタンを押下状態（オン）の外観にします。変数にバインドすればランプ／インジケータの状態表示にも使えます")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onToggled: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.beginEdit()
                editorInspector.editorCanvas.selectedItem.widgetChecked = checked
                editorInspector.editorCanvas.commitEdit()
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorCheckedCheck.checked = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetChecked : false
            }
        }
    }
}
