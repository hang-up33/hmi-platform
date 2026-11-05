import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「動作（クリック時アクション / バインディング）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: actionSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null

    // このセクション内の入力欄が編集フォーカス中か。InspectorPanel の
    // widgetEditFieldFocused（Canvas undo の 1 操作境界）がこれを OR する。
    readonly property bool editFieldFocused:
        inspectorActionOpCombo.activeFocus
        || inspectorActionTargetCombo.activeFocus
        || inspectorActionValueField.activeFocus
        || inspectorBindingPropCombo.activeFocus
        || inspectorBindingVarCombo.activeFocus

    // Task 40: アクション編集（onClick 1 件）。op ComboBox / target ComboBox / value から
    // 選択 Item の widgetActions を組み立てる。op "(なし)" は空配列（アクション無し）。
    function applyActionFromInspector() {
        if (!editorInspector.editorCanvas.selectedItem) {
            return
        }
        // 操作 "(なし)" または対象変数 "(未選択)" のときはアクション無し（空配列）。
        // **空 target のアクションを保存しない**：ActionData.isValidJson が空 target を
        // 無効としプロジェクト全体が再読込不能になるため（Codex PR #80 [P1]）。
        if (inspectorActionOpCombo.currentIndex === 0
                || inspectorActionTargetCombo.currentIndex === 0) {
            editorInspector.editorCanvas.selectedItem.widgetActions = []
            return
        }
        const op = inspectorActionOpCombo.currentText
        const target = inspectorActionTargetCombo.currentText
        const value = (op === "setVariable") ? inspectorActionValueField.text : ""
        editorInspector.editorCanvas.selectedItem.widgetActions = [{
            trigger: "onClick", op: op, target: target, value: value
        }]
    }

    // 選択切替時にアクション編集 UI を選択 Item の値へ同期する。
    function syncActionToInspector() {
        const it = editorInspector.editorCanvas.selectedItem
        const a = (it && it.widgetActions && it.widgetActions.length > 0)
            ? it.widgetActions[0] : null
        inspectorActionOpCombo.currentIndex = a
            ? Math.max(0, inspectorActionOpCombo.model.indexOf(a.op)) : 0
        const names = editorInspector.editorRoot.variableNameModel()
        inspectorActionTargetCombo.currentIndex = (a && a.target)
            ? Math.max(0, names.indexOf(a.target)) : 0
        inspectorActionValueField.text = (a && a.value !== undefined) ? a.value : ""
    }

    // Task 40: バインディング編集（1 件）。property ComboBox / variable ComboBox から
    // 選択 Item の widgetBindings を組み立てる。property "(なし)" or variable "(未選択)" は空。
    function applyBindingFromInspector() {
        if (!editorInspector.editorCanvas.selectedItem) {
            return
        }
        if (inspectorBindingPropCombo.currentIndex === 0
                || inspectorBindingVarCombo.currentIndex === 0) {
            editorInspector.editorCanvas.selectedItem.widgetBindings = []
            return
        }
        editorInspector.editorCanvas.selectedItem.widgetBindings = [{
            property: inspectorBindingPropCombo.currentText,
            variable: inspectorBindingVarCombo.currentText
        }]
    }

    function syncBindingToInspector() {
        const it = editorInspector.editorCanvas.selectedItem
        const b = (it && it.widgetBindings && it.widgetBindings.length > 0)
            ? it.widgetBindings[0] : null
        inspectorBindingPropCombo.currentIndex = b
            ? Math.max(0, inspectorBindingPropCombo.model.indexOf(b.property)) : 0
        const names = editorInspector.editorRoot.variableNameModel()
        inspectorBindingVarCombo.currentIndex = (b && b.variable)
            ? Math.max(0, names.indexOf(b.variable)) : 0
    }
    title: qsTr("動作")

    // Task 40: クリック時アクション（onClick 1 件）。op / target / value を選び
    // 選択 Item の widgetActions へ書き戻す。target は変数定義 ComboBox 由来。
    // Task 48 / 51: Label / NumericField はクリックアクションを持たないため、
    // このアクション編集 UI（見出し / 操作 / 対象変数 / 値 / 区切り線）を両型の
    // 選択時は隠す（派生 selectedSupportsClickAction = Button のみ true）。
    // **バインディング編集（読み）は全 Widget で残す**（役割分担：読み⊂全 Widget。
    // NumericField は binding を読み書き両用に使うため特に必須）。
    Label {
        text: qsTr("クリック時アクション"); font.bold: true; color: "#555555"
        visible: editorInspector.selectedSupportsClickAction
    }

    Label { text: qsTr("操作"); visible: editorInspector.selectedSupportsClickAction }
    ComboBox {
        id: inspectorActionOpCombo
        objectName: "inspectorActionOpCombo"
        width: parent.width
        visible: editorInspector.selectedSupportsClickAction
        model: ["(なし)", "setVariable", "toggleVariable"]
        // Task 45: クリック時の動作が分かりにくいため補足を付ける。
        ToolTip.text: qsTr("クリック時の動作。setVariable=値を代入 / toggleVariable=オン↔オフを反転")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onActivated: actionSection.applyActionFromInspector()
    }
    Label { text: qsTr("対象変数"); visible: editorInspector.selectedSupportsClickAction }
    ComboBox {
        id: inspectorActionTargetCombo
        objectName: "inspectorActionTargetCombo"
        width: parent.width
        visible: editorInspector.selectedSupportsClickAction
        model: editorInspector.editorRoot.variableNameModel()
        onActivated: actionSection.applyActionFromInspector()
    }
    // 値は setVariable のときだけ意味を持つ（toggleVariable では無視）。
    // Task 48 / 51: Label / NumericField 選択時はアクション部ごと隠す
    // （selectedSupportsClickAction と AND）。
    Label {
        text: qsTr("値")
        visible: editorInspector.selectedSupportsClickAction
               && inspectorActionOpCombo.currentText === "setVariable"
    }
    TextField {
        id: inspectorActionValueField
        objectName: "inspectorActionValueField"
        width: parent.width
        visible: editorInspector.selectedSupportsClickAction
               && inspectorActionOpCombo.currentText === "setVariable"
        placeholderText: qsTr("例: true / 10 / hello")
        onEditingFinished: actionSection.applyActionFromInspector()
    }

    // Task 40: データバインディング（1 件）。property を変数に追従させる。
    // Task 48 / 51: 区切り線はアクション部とバインディング部の境界なので、
    // アクション部が隠れる Label / NumericField 選択時は一緒に隠す。
    Rectangle {
        width: parent.width; height: 1; color: "#dddddd"
        visible: editorInspector.selectedSupportsClickAction
    }
    Label { text: qsTr("バインディング"); font.bold: true; color: "#555555" }

    Label { text: qsTr("プロパティ") }
    ComboBox {
        id: inspectorBindingPropCombo
        objectName: "inspectorBindingPropCombo"
        width: parent.width
        // Task 51: NumericField の「入力対象変数」を表す "value" を追加。
        // NumericField では binding {property:"value"} が読み（表示）と
        // 書き（入力確定）の両方の対象になる（読み書き両用 binding）。
        model: ["(なし)", "visible", "backgroundColor", "text", "textColor", "checked", "value"]
        // Task 45: 「バインディング」概念の補足（変数の値に表示を追従させる）。
        ToolTip.text: qsTr("選んだ表示プロパティを、下の変数の値に自動追従させます（実行時に反映）")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onActivated: actionSection.applyBindingFromInspector()
    }
    Label { text: qsTr("追従変数") }
    ComboBox {
        id: inspectorBindingVarCombo
        objectName: "inspectorBindingVarCombo"
        width: parent.width
        model: editorInspector.editorRoot.variableNameModel()
        onActivated: actionSection.applyBindingFromInspector()
    }

    // Task 40: 選択切替時にアクション / バインディング編集 UI を同期する。
    Connections {
        target: editorInspector.editorCanvas
        function onSelectedItemChanged() {
            actionSection.syncActionToInspector()
            actionSection.syncBindingToInspector()
        }
    }
}
