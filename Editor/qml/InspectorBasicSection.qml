import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「基本（Text / 座標・サイズ）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: basicSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null

    // このセクション内の入力欄が編集フォーカス中か。InspectorPanel の
    // widgetEditFieldFocused（Canvas undo の 1 操作境界）がこれを OR する。
    readonly property bool editFieldFocused:
        inspectorTextField.activeFocus
        || fieldX.activeFocus
        || fieldY.activeFocus
        || fieldW.activeFocus
        || fieldH.activeFocus

    // Task 27: 座標・サイズ SpinBox の表示値を選択中 Item の現在値へ同期する。
    // 選択変更・移動ドラッグ・リサイズハンドルのいずれの経路でも呼ばれ、表示を
    // live 値に追従させる。プログラムからの value 代入は valueModified を発火
    // しないため書き戻しループは起きない。未選択時は既定値（from）に戻す。
    function syncGeometryFields() {
        const it = editorInspector.editorCanvas.selectedItem
        // 編集中（activeFocus）のフィールドは上書きしない。書き戻し → 幾何変化 →
        // 同期 でテキストを再代入するとカーソルが飛ぶため。非フォーカスの
        // フィールドは drag/handle 由来の変化に live 追従させる。
        if (!fieldX.activeFocus) {
            fieldX.text = it ? String(Math.round(it.x)) : ""
        }
        if (!fieldY.activeFocus) {
            fieldY.text = it ? String(Math.round(it.y)) : ""
        }
        if (!fieldW.activeFocus) {
            fieldW.text = it ? String(Math.round(it.width)) : ""
        }
        if (!fieldH.activeFocus) {
            fieldH.text = it ? String(Math.round(it.height)) : ""
        }
    }
    title: qsTr("基本")

    // Task T-C / M-C: Trend / Meter は文字を持たないため Text 入力（ラベル + 欄）を隠す。
    Label { text: qsTr("Text"); visible: !editorInspector.selectedIsTrend && !editorInspector.selectedIsMeter }
    TextField {
        id: inspectorTextField
        objectName: "inspectorTextField"
        visible: !editorInspector.selectedIsTrend && !editorInspector.selectedIsMeter
        width: parent.width
        // ユーザー入力のみ選択中 Item へ書き戻す
        // （textEdited はプログラム変更では発火しない）。
        // Item.widgetText 更新で HmiButton の text バインドが即追従する。
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetText = text
            }
        }
        // 選択が変わったら表示値を選択 Item の値へ更新する。
        // text を直接バインドするとユーザー入力でバインディングが
        // 切れ、選択切替時に追従しなくなるため明示更新する。
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorTextField.text = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetText : ""
            }
        }
    }

    // Task 27: 座標・サイズの数値編集。TextField + IntValidator
    //（QtQuick / QtQuick.Controls の既存 import で完結）で選択中 Item の
    // x/y/width/height を更新する。editable な SpinBox は value を
    // プログラム設定しても表示テキストが更新されない不具合があったため
    // （Windows / Qt 6.11 で確認）、表示を自前で制御できる TextField を採用。
    Label { text: qsTr("座標・サイズ") }
    Grid {
        objectName: "inspectorGeometryGrid"
        columns: 2
        rowSpacing: 6
        columnSpacing: 8
        verticalItemAlignment: Grid.AlignVCenter

        Label { text: qsTr("X") }
        TextField {
            id: fieldX
            objectName: "inspectorXField"
            width: 150
            inputMethodHints: Qt.ImhDigitsOnly
            // フォーカス取得時に全選択し、クリック / Tab 直後に
            // 数値をそのまま打ち直せるようにする（消す手間を省く）。
            onActiveFocusChanged: if (activeFocus) selectAll()
            validator: IntValidator { bottom: 0; top: 9999 }
            // 妥当な数値の時だけ選択中 Item へ書き戻す（acceptableInput）。
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.x = parseInt(text)
                }
            }
            Keys.onUpPressed: (event) => {
                editorInspector.nudgeGeometry(fieldX, "x", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                event.accepted = true
            }
            Keys.onDownPressed: (event) => {
                editorInspector.nudgeGeometry(fieldX, "x", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
                event.accepted = true
            }
        }

        Label { text: qsTr("Y") }
        TextField {
            id: fieldY
            objectName: "inspectorYField"
            width: 150
            inputMethodHints: Qt.ImhDigitsOnly
            onActiveFocusChanged: if (activeFocus) selectAll()
            validator: IntValidator { bottom: 0; top: 9999 }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.y = parseInt(text)
                }
            }
            Keys.onUpPressed: (event) => {
                editorInspector.nudgeGeometry(fieldY, "y", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                event.accepted = true
            }
            Keys.onDownPressed: (event) => {
                editorInspector.nudgeGeometry(fieldY, "y", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
                event.accepted = true
            }
        }

        Label { text: qsTr("幅") }
        TextField {
            id: fieldW
            objectName: "inspectorWidthField"
            width: 150
            inputMethodHints: Qt.ImhDigitsOnly
            onActiveFocusChanged: if (activeFocus) selectAll()
            // 最小幅 30（EditableWidget.minWidth と整合）。
            validator: IntValidator { bottom: 30; top: 9999 }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.width = parseInt(text)
                }
            }
            Keys.onUpPressed: (event) => {
                editorInspector.nudgeGeometry(fieldW, "width", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                event.accepted = true
            }
            Keys.onDownPressed: (event) => {
                editorInspector.nudgeGeometry(fieldW, "width", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
                event.accepted = true
            }
        }

        Label { text: qsTr("高さ") }
        TextField {
            id: fieldH
            objectName: "inspectorHeightField"
            width: 150
            inputMethodHints: Qt.ImhDigitsOnly
            onActiveFocusChanged: if (activeFocus) selectAll()
            // 最小高さ 24（EditableWidget.minHeight と整合）。
            validator: IntValidator { bottom: 24; top: 9999 }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.height = parseInt(text)
                }
            }
            Keys.onUpPressed: (event) => {
                editorInspector.nudgeGeometry(fieldH, "height", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                event.accepted = true
            }
            Keys.onDownPressed: (event) => {
                editorInspector.nudgeGeometry(fieldH, "height", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
                event.accepted = true
            }
        }
    }

    // Task 27: x/y/width/height は インスペクタ数値編集・移動ドラッグ・
    // リサイズハンドルの 3 経路で変わる。表示を value/text へ直接バインド
    // するとユーザー入力で切れて drag/handle 由来の更新を取りこぼすため、
    // 選択変更時（selectedItem 変化）と選択中 Item の幾何プロパティ変化
    //（drag/handle）の両方で明示同期する（syncGeometryFields）。
    Connections {
        target: editorInspector.editorCanvas
        function onSelectedItemChanged() {
            basicSection.syncGeometryFields()
        }
    }
    Connections {
        target: editorInspector.editorCanvas.selectedItem
        ignoreUnknownSignals: true
        function onXChanged() { basicSection.syncGeometryFields() }
        function onYChanged() { basicSection.syncGeometryFields() }
        function onWidthChanged() { basicSection.syncGeometryFields() }
        function onHeightChanged() { basicSection.syncGeometryFields() }
    }
}
