import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import HmiEditor
import HmiWidgets

Window {
    id: rootWindow
    // Task 26: 右側インスペクタ（幅 260px）を足したぶん、キャンバス（800px）が
    // 隠れないようウィンドウ幅を広げる（1024 → 1280）。
    width: 1280
    height: 768
    visible: true
    title: qsTr("HMI Editor")
    // Task 18: Spix からのパス解決のため Window 自身に objectName を付与する。
    // Spix のテストランナーは `hmiEditorWindow/<objectName>` の形で操作対象
    // QML Item を指定する。
    objectName: "hmiEditorWindow"

    // Task 39 / 40: Project レベルの変数定義。T40 でインスペクタの変数パネルから編集する。
    // save() へそのまま渡し、読み込んだ定義を保存で失わない（Codex PR #78 [P1]）。
    property var projectVariables: []

    // Task 40: 変数パネルの動的 TextField（Repeater 由来で id 固定できない）の編集中フラグ。
    // Delete ショートカットの抑止に使う（各行が onActiveFocusChanged で増減する）。
    property int variableFieldFocusCount: 0

    // Task 40: 変数定義の編集ヘルパー。projectVariables は var 配列なので、編集は必ず
    // 新しい配列を再代入してバインディング（ComboBox model 等）へ通知する。
    function addVariable() {
        const next = projectVariables.slice()
        // 重複しない既定名を採番（var1, var2, ...）。
        let n = next.length + 1
        const existing = {}
        for (let i = 0; i < next.length; ++i) {
            existing[next[i].name] = true
        }
        while (existing["var" + n]) {
            ++n
        }
        next.push({ name: "var" + n, type: "bool", initial: "false" })
        projectVariables = next
    }
    function updateVariable(index, key, value) {
        if (index < 0 || index >= projectVariables.length) {
            return
        }
        const oldName = projectVariables[index].name
        const next = projectVariables.slice()
        const v = Object.assign({}, next[index])
        v[key] = value
        next[index] = v
        projectVariables = next
        // Task 40（Codex PR #80 [P2]）：変数名変更時は既存 Widget の参照（actions.target /
        // bindings.variable）も旧名→新名へ置換し、参照切れを防ぐ。
        if (key === "name") {
            canvas.renameVariableReferences(oldName, value)
        }
    }
    function removeVariable(index) {
        if (index < 0 || index >= projectVariables.length) {
            return
        }
        const removedName = projectVariables[index].name
        const next = projectVariables.slice()
        next.splice(index, 1)
        projectVariables = next
        // Task 40（Codex PR #80 [P2]）：削除した変数を参照している Widget の
        // actions/bindings も取り除き、未定義変数への dangling 参照を残さない。
        canvas.removeVariableReferences(removedName)
    }
    // ComboBox（アクション target / バインディング variable）の選択肢：先頭に "(未選択)"。
    function variableNameModel() {
        const names = ["(未選択)"]
        for (let i = 0; i < projectVariables.length; ++i) {
            names.push(projectVariables[i].name)
        }
        return names
    }

    // Task 40: アクション編集（onClick 1 件）。op ComboBox / target ComboBox / value から
    // 選択 Item の widgetActions を組み立てる。op "(なし)" は空配列（アクション無し）。
    function applyActionFromInspector() {
        if (!canvas.selectedItem) {
            return
        }
        // 操作 "(なし)" または対象変数 "(未選択)" のときはアクション無し（空配列）。
        // **空 target のアクションを保存しない**：ActionData.isValidJson が空 target を
        // 無効としプロジェクト全体が再読込不能になるため（Codex PR #80 [P1]）。
        if (inspectorActionOpCombo.currentIndex === 0
                || inspectorActionTargetCombo.currentIndex === 0) {
            canvas.selectedItem.widgetActions = []
            return
        }
        const op = inspectorActionOpCombo.currentText
        const target = inspectorActionTargetCombo.currentText
        const value = (op === "setVariable") ? inspectorActionValueField.text : ""
        canvas.selectedItem.widgetActions = [{
            trigger: "onClick", op: op, target: target, value: value
        }]
    }
    // 選択切替時にアクション編集 UI を選択 Item の値へ同期する。
    function syncActionToInspector() {
        const it = canvas.selectedItem
        const a = (it && it.widgetActions && it.widgetActions.length > 0)
            ? it.widgetActions[0] : null
        inspectorActionOpCombo.currentIndex = a
            ? Math.max(0, inspectorActionOpCombo.model.indexOf(a.op)) : 0
        const names = variableNameModel()
        inspectorActionTargetCombo.currentIndex = (a && a.target)
            ? Math.max(0, names.indexOf(a.target)) : 0
        inspectorActionValueField.text = (a && a.value !== undefined) ? a.value : ""
    }

    // Task 40: バインディング編集（1 件）。property ComboBox / variable ComboBox から
    // 選択 Item の widgetBindings を組み立てる。property "(なし)" or variable "(未選択)" は空。
    function applyBindingFromInspector() {
        if (!canvas.selectedItem) {
            return
        }
        if (inspectorBindingPropCombo.currentIndex === 0
                || inspectorBindingVarCombo.currentIndex === 0) {
            canvas.selectedItem.widgetBindings = []
            return
        }
        canvas.selectedItem.widgetBindings = [{
            property: inspectorBindingPropCombo.currentText,
            variable: inspectorBindingVarCombo.currentText
        }]
    }
    function syncBindingToInspector() {
        const it = canvas.selectedItem
        const b = (it && it.widgetBindings && it.widgetBindings.length > 0)
            ? it.widgetBindings[0] : null
        inspectorBindingPropCombo.currentIndex = b
            ? Math.max(0, inspectorBindingPropCombo.model.indexOf(b.property)) : 0
        const names = variableNameModel()
        inspectorBindingVarCombo.currentIndex = (b && b.variable)
            ? Math.max(0, names.indexOf(b.variable)) : 0
    }

    // Task 26: 選択中の live な EditableWidget はインスペクタの編集対象。
    // 解決ロジックと所有は Canvas に集約した（canvas.selectedItem）。Repeater
    // 再生成後も同一 id の新しい live Item に解決し直される（Codex PR #52 P2 指摘
    // への回答。詳細は Canvas.qml の selectedItem コメント）。インスペクタは
    // この live Item を直接 two-way 編集する（widgetModel の var 配列は据え置き
    // ＝Phase 4 設計指針、delegate 再生成を起こさない）。

    // Task 27: 座標・サイズ SpinBox の表示値を選択中 Item の現在値へ同期する。
    // 選択変更・移動ドラッグ・リサイズハンドルのいずれの経路でも呼ばれ、表示を
    // live 値に追従させる。プログラムからの value 代入は valueModified を発火
    // しないため書き戻しループは起きない。未選択時は既定値（from）に戻す。
    function syncGeometryFields() {
        const it = canvas.selectedItem
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

    // Task 19: E2E（Spix の invokeMethod）から呼ぶ JSON 保存ラッパー。
    // FileDialog は AppleScript / Spix から自動操作できないため、Canvas 上の
    // EditableWidget 群を Shared/Schema 互換のリストへ変換 → ProjectIo.save に
    // 直接渡す処理を関数化する。saveDialog.onAccepted と同じロジック。
    // 戻り値は ProjectIo.save の bool をそのまま返し、Spix 側で
    // <boolean>0/1</boolean> として受け取れる。
    function saveTo(path) {
        if (!path) {
            return false
        }
        // Task 26: live Item 群のスナップショット（インスペクタ編集を含む現在値）
        // を Canvas に集約した snapshotModel() で取得する。
        const widgets = canvas.snapshotModel()
        // ProjectIo.save は FileDialog 由来の `file:///` 形式 QUrl を期待する
        // ため、絶対パスを `file://` プレフィックス付きで URL 化して渡す。
        // E2E は macOS / Linux でのみ走る（Windows MinGW は HMI_ENABLE_E2E=OFF）
        // ため POSIX 絶対パス前提でよい。
        const url = Qt.resolvedUrl("file://" + path)
        // Task 39: 読み込んだ変数定義もそのまま保存へ渡す（失わないため）。
        return projectIo.save(url, "Sample", "Main", widgets, rootWindow.projectVariables)
    }

    // Task 19: 起動時自動ロード。`--open <path>` で初期 JSON URL が渡された
    // 場合のみ projectIo.load() を呼んで Canvas を再構築する。Simulator の
    // Main.qml と同じパターン（Task 8 で確立）。E2E の「保存 → 別プロセスで
    // 開いて再現」ループはこの分岐に依存する。
    Component.onCompleted: {
        if (initialJsonUrl && initialJsonUrl.toString() !== "") {
            const result = projectIo.load(initialJsonUrl)
            if (!result || !result.ok) {
                console.warn("起動時プロジェクト読込に失敗:", initialJsonUrl)
                return
            }
            // Task 40: 変数定義を **widgetModel より先に** 設定する。widgetModel 変更で
            // selectedItemChanged → アクション/バインディング sync が走るとき、target/variable
            // ComboBox の選択肢（variableNameModel）が揃っているようにするため。
            rootWindow.projectVariables = result.variables !== undefined ? result.variables : []
            canvas.widgetModel = result.widgets
            canvas.clearHistory()  // Task 38: 起動時読込後は undo 履歴を空にする
            console.log("起動時プロジェクト読込:", initialJsonUrl,
                        "widgets =", result.widgets.length)
        }
    }

    // Task 38: 選択中 Widget を編集するインスペクタ欄が編集フォーカス中か。これらの
    // 変更は Canvas の widgetModel に入る（snapshotModel が拾う）ため、Canvas undo の
    // 1 操作境界（beginEdit/commitEdit）のトリガにする。
    // Task 40: 変数定義欄（variableFieldFocusCount）は **ここに含めない**。変数編集は
    // rootWindow.projectVariables を変えるだけで Canvas の widgetModel には入らず、
    // Canvas undo スタックには載らない。リネーム時は widget 参照も書き換えるが、それも
    // beginEdit/commitEdit の外で行うため undo に載らず、変数定義と widget 参照が
    // 常に一致したまま動く（混ぜると Undo で widget 参照だけ旧名に戻り参照切れになる）。
    readonly property bool widgetEditFieldFocused:
        inspectorTextField.activeFocus
        || inspectorTagField.activeFocus
        || inspectorBgColorField.activeFocus
        || inspectorTextColorField.activeFocus
        || inspectorFontSizeSpin.activeFocus
        || inspectorBorderColorField.activeFocus
        || inspectorBorderWidthSpin.activeFocus
        || inspectorRadiusSpin.activeFocus
        || inspectorFontFamilyCombo.activeFocus
        || inspectorHAlignCombo.activeFocus
        || inspectorVAlignCombo.activeFocus
        || inspectorOpacitySpin.activeFocus
        || inspectorActionOpCombo.activeFocus
        || inspectorActionTargetCombo.activeFocus
        || inspectorActionValueField.activeFocus
        || inspectorBindingPropCombo.activeFocus
        || inspectorBindingVarCombo.activeFocus
        || fieldX.activeFocus || fieldY.activeFocus
        || fieldW.activeFocus || fieldH.activeFocus

    // Task 29 / 37: インスペクタのどれかの入力欄が編集フォーカス中か。Delete / Copy /
    // Paste / Duplicate のショートカットは、フィールド編集中（文字削除やテキストの
    // コピペに同じキーを使う）に奪うと困るため、このガードで無効化する。
    // Task 37 で Delete のインライン列挙をこの単一プロパティに集約した（重複排除）。
    // Task 40: 変数定義欄（variableFieldFocusCount）も Delete ガードには含める（変数名
    // を Backspace/Delete で消すときに widget が消えないように）が、Canvas undo の
    // widgetEditFieldFocused とは分離する（上のコメント参照）。
    readonly property bool inspectorFieldFocused:
        widgetEditFieldFocused
        || rootWindow.variableFieldFocusCount > 0

    // Task 38: インスペクタの Widget 編集を undo の 1 操作境界にする。どれかの入力欄が
    // フォーカスを得た時に前状態を保留（beginEdit）し、全フィールドからフォーカスが
    // 外れた時に確定（commitEdit、状態が変わっていれば 1 件積む）。これで「フィールドを
    // 触った 1 セッション = 1 undo」になり、キーストロークごとに積まれない。
    onWidgetEditFieldFocusedChanged: {
        if (widgetEditFieldFocused) {
            canvas.beginEdit()
        } else {
            canvas.commitEdit()
        }
    }

    // Task 29: Delete キーで選択中 Widget を削除する。Shortcut なら個別 Item の
    // フォーカス・Keys ハンドリングを増やさず Window 全体に効かせられる。
    Shortcut {
        sequence: StandardKey.Delete
        enabled: canvas.selectedWidgetIds.length > 0 && !rootWindow.inspectorFieldFocused
        onActivated: canvas.deleteWidgets(canvas.selectedWidgetIds)
    }

    // Task 37: コピー / ペースト / 複製のショートカット。コピペは StandardKey で OS 差
    // （macOS = Cmd / Win・Linux = Ctrl）を吸収する。複製は **Ctrl+D を避け Ctrl+Shift+D**
    // にする（Ctrl+D は KDE/GNOME で StandardKey.Delete に含まれ T29 削除と衝突するため）。
    // いずれもインスペクタ編集中は無効（テキストの copy/paste を妨げない）。
    Shortcut {
        sequence: StandardKey.Copy
        enabled: canvas.selectedWidgetIds.length > 0 && !rootWindow.inspectorFieldFocused
        onActivated: canvas.copySelected()
    }
    Shortcut {
        sequence: StandardKey.Paste
        enabled: canvas.clipboard.length > 0 && !rootWindow.inspectorFieldFocused
        onActivated: canvas.pasteClipboard()
    }
    Shortcut {
        sequence: "Ctrl+Shift+D"
        enabled: canvas.selectedWidgetIds.length > 0 && !rootWindow.inspectorFieldFocused
        onActivated: canvas.duplicateSelected()
    }

    // Task 38: undo / redo。StandardKey は OS 差（Cmd/Ctrl）を吸収する。フィールド編集中は
    // 無効（テキストの undo を妨げない）。redo は StandardKey.Redo（Ctrl+Y / Cmd+Shift+Z）に
    // 加え Ctrl+Shift+Z も受ける（Windows の Ctrl+Y に対する保険）。redo は **1 つの
    // Shortcut の `sequences`（複数）にまとめる**：別々の Shortcut にすると、macOS/KDE/GNOME
    // では StandardKey.Redo 自体が Ctrl+Shift+Z に解決され、同じキーに 2 つの有効な
    // Shortcut が存在して activatedAmbiguously になり onActivated（redo）が呼ばれない
    // （Codex PR #77 [P2]）。同一 Shortcut 内の重複シーケンスは曖昧化しない。
    Shortcut {
        sequence: StandardKey.Undo
        enabled: canvas.canUndo && !rootWindow.inspectorFieldFocused
        onActivated: canvas.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]
        enabled: canvas.canRedo && !rootWindow.inspectorFieldFocused
        onActivated: canvas.redo()
    }

    // 薄いグレーの余白背景
    Rectangle {
        anchors.fill: parent
        color: "#e0e0e0"

        // 上部ツールバー（Task 6: 保存 / Task 7: 開く / Task 18: 追加）
        Row {
            id: toolbar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            spacing: 8

            // Task 18: Widget 追加。E2E からは objectName で参照する。
            Button {
                objectName: "addWidgetButton"
                text: qsTr("追加")
                onClicked: canvas.addWidget()
            }

            Button {
                text: qsTr("開く")
                onClicked: openDialog.open()
            }

            Button {
                text: qsTr("保存")
                onClicked: saveDialog.open()
            }

            // Task 35: グリッドスナップ ON/OFF トグル。canvas.snapEnabled を駆動し、
            // ON でドラッグ / リサイズが格子に吸着しグリッド線も表示される。
            // 編集時の補助のみで JSON には保存しない。
            CheckBox {
                objectName: "snapToggle"
                text: qsTr("スナップ")
                checked: canvas.snapEnabled
                onToggled: canvas.snapEnabled = checked
            }

            // Task 37: コピー / ペースト / 複製。ショートカット（Cmd/Ctrl+C/V・Ctrl+Shift+D）
            // と同じ Canvas 関数を叩く（ボタンは発見性とヘッドレススクショ用）。
            Button {
                objectName: "copyButton"
                text: qsTr("コピー")
                enabled: canvas.selectedWidgetIds.length > 0
                onClicked: canvas.copySelected()
            }
            Button {
                objectName: "pasteButton"
                text: qsTr("ペースト")
                enabled: canvas.clipboard.length > 0
                onClicked: canvas.pasteClipboard()
            }
            Button {
                objectName: "duplicateButton"
                text: qsTr("複製")
                enabled: canvas.selectedWidgetIds.length > 0
                onClicked: canvas.duplicateSelected()
            }

            // Task 38: undo / redo ボタン（ショートカットと同じ Canvas 関数）。
            Button {
                objectName: "undoButton"
                text: qsTr("元に戻す")
                enabled: canvas.canUndo
                onClicked: canvas.undo()
            }
            Button {
                objectName: "redoButton"
                text: qsTr("やり直す")
                enabled: canvas.canRedo
                onClicked: canvas.redo()
            }
        }

        // Task 26: 右側インスペクタ。選択中 Widget の text / tag を編集する。
        // 編集対象は canvas.selectedWidgetId が指す live な EditableWidget
        // （canvas.selectedItem で解決）。Simulator / Runtime は読み取り専用の
        // ため、この編集 UI は Editor のみが持つ（Phase 4 ルール）。
        Rectangle {
            id: inspector
            objectName: "inspectorPanel"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 260
            color: "#f5f5f5"
            border.color: "#cccccc"
            border.width: 1

            // Task 31 (Codex PR #64 P2): border/radius でインスペクタ項目が増え、既定の
            // 1280x768 では角丸 SpinBox / 削除ボタンが下端に押し出されてアクセス不能に
            // なるため、フォーム全体を ScrollView に載せて縦スクロール可能にする。
            // contentWidth: availableWidth で横スクロールバーは出さない。
            ScrollView {
                id: inspectorScroll
                anchors.fill: parent
                anchors.margins: 12
                contentWidth: availableWidth
                clip: true

                Column {
                    width: inspectorScroll.availableWidth
                    spacing: 8

                    Label {
                        text: qsTr("インスペクタ")
                        font.pixelSize: 16
                        font.bold: true
                    }

                // Task 40: Project レベルの変数定義パネル（選択に依らず常時表示）。
                // 変数の追加 / 削除 / 名前・型・初期値の編集を行い、rootWindow.projectVariables を
                // 駆動する。アクション target / バインディング variable の ComboBox 選択肢になる。
                Column {
                    objectName: "variablePanel"
                    width: parent.width
                    spacing: 4

                    Label { text: qsTr("変数定義"); font.bold: true; color: "#555555" }

                    Repeater {
                        model: rootWindow.projectVariables
                        delegate: Row {
                            id: varRow
                            required property var modelData
                            required property int index
                            width: parent.width
                            spacing: 4

                            TextField {
                                id: varNameField
                                objectName: "variableName_" + varRow.index
                                width: 80
                                text: varRow.modelData.name !== undefined ? varRow.modelData.name : ""
                                placeholderText: qsTr("名前")
                                // **空名を保存しない**：VariableData.isValidJson が空 name を無効とし
                                // プロジェクト全体が再読込不能になるため、空のときは元の名前へ戻す
                                // （削除は × ボタンで行う。Codex PR #80 [P1]）。
                                onEditingFinished: {
                                    if (text.length > 0) {
                                        rootWindow.updateVariable(varRow.index, "name", text)
                                    } else {
                                        text = Qt.binding(function() {
                                            return varRow.modelData.name !== undefined
                                                ? varRow.modelData.name : ""
                                        })
                                    }
                                }
                                onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
                            }
                            ComboBox {
                                objectName: "variableType_" + varRow.index
                                width: 80
                                model: ["bool", "int", "string"]
                                currentIndex: Math.max(0, model.indexOf(varRow.modelData.type))
                                onActivated: rootWindow.updateVariable(varRow.index, "type", currentText)
                            }
                            TextField {
                                objectName: "variableInitial_" + varRow.index
                                width: 60
                                text: varRow.modelData.initial !== undefined ? varRow.modelData.initial : ""
                                placeholderText: qsTr("初期値")
                                onEditingFinished: rootWindow.updateVariable(varRow.index, "initial", text)
                                onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
                            }
                            Button {
                                objectName: "variableDelete_" + varRow.index
                                text: qsTr("×")
                                onClicked: rootWindow.removeVariable(varRow.index)
                            }
                        }
                    }

                    Button {
                        objectName: "addVariableButton"
                        text: qsTr("変数を追加")
                        onClicked: rootWindow.addVariable()
                    }

                    Rectangle { width: parent.width; height: 1; color: "#dddddd" }
                }

                // 未選択時の案内（Task 36: 0 個選択のときのみ）
                Label {
                    objectName: "inspectorEmptyLabel"
                    visible: canvas.selectedWidgetIds.length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#888888"
                    text: qsTr("Widget を選択してください")
                }

                // Task 36: 複数選択時のパネル。単一プロパティ編集は単一選択時のみとし、
                // 複数選択時は「N 個選択中」+ 一括整列 / 分布 / 削除のアクションを提供する。
                Column {
                    objectName: "inspectorMultiPanel"
                    visible: canvas.selectedWidgetIds.length > 1
                    width: parent.width
                    spacing: 8

                    Label {
                        objectName: "inspectorMultiLabel"
                        width: parent.width
                        font.bold: true
                        text: canvas.selectedWidgetIds.length + qsTr(" 個選択中")
                    }

                    Label { text: qsTr("整列"); color: "#555555" }
                    // 水平方向の整列（左 / 中央 / 右）
                    Row {
                        spacing: 4
                        Button { objectName: "alignLeftButton";    text: qsTr("左");   onClicked: canvas.alignSelected("left") }
                        Button { objectName: "alignHCenterButton"; text: qsTr("中央"); onClicked: canvas.alignSelected("hcenter") }
                        Button { objectName: "alignRightButton";   text: qsTr("右");   onClicked: canvas.alignSelected("right") }
                    }
                    // 垂直方向の整列（上 / 中央 / 下）
                    Row {
                        spacing: 4
                        Button { objectName: "alignTopButton";     text: qsTr("上");   onClicked: canvas.alignSelected("top") }
                        Button { objectName: "alignVCenterButton"; text: qsTr("中央"); onClicked: canvas.alignSelected("vcenter") }
                        Button { objectName: "alignBottomButton";  text: qsTr("下");   onClicked: canvas.alignSelected("bottom") }
                    }

                    Label { text: qsTr("等間隔分布（3 個以上）"); color: "#555555" }
                    Row {
                        spacing: 4
                        Button { objectName: "distributeHButton"; text: qsTr("水平"); onClicked: canvas.distributeSelected("h") }
                        Button { objectName: "distributeVButton"; text: qsTr("垂直"); onClicked: canvas.distributeSelected("v") }
                    }

                    Button {
                        objectName: "inspectorMultiDeleteButton"
                        text: qsTr("選択をすべて削除")
                        onClicked: canvas.deleteWidgets(canvas.selectedWidgetIds)
                    }
                }

                // 選択中の編集フォーム
                Column {
                    objectName: "inspectorForm"
                    visible: canvas.selectedItem !== null
                    width: parent.width
                    spacing: 8

                    Label {
                        objectName: "inspectorIdLabel"
                        color: "#555555"
                        text: qsTr("ID: ") + (canvas.selectedItem
                            ? canvas.selectedItem.widgetId : "")
                    }

                    Label { text: qsTr("Text") }
                    TextField {
                        id: inspectorTextField
                        objectName: "inspectorTextField"
                        width: parent.width
                        // ユーザー入力のみ選択中 Item へ書き戻す
                        // （textEdited はプログラム変更では発火しない）。
                        // Item.widgetText 更新で HmiButton の text バインドが即追従する。
                        onTextEdited: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetText = text
                            }
                        }
                        // 選択が変わったら表示値を選択 Item の値へ更新する。
                        // text を直接バインドするとユーザー入力でバインディングが
                        // 切れ、選択切替時に追従しなくなるため明示更新する。
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorTextField.text = canvas.selectedItem
                                    ? canvas.selectedItem.widgetText : ""
                            }
                        }
                    }

                    Label { text: qsTr("Tag") }
                    TextField {
                        id: inspectorTagField
                        objectName: "inspectorTagField"
                        width: parent.width
                        onTextEdited: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetTag = text
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorTagField.text = canvas.selectedItem
                                    ? canvas.selectedItem.widgetTag : ""
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
                            validator: IntValidator { bottom: 0; top: 9999 }
                            // 妥当な数値の時だけ選択中 Item へ書き戻す（acceptableInput）。
                            onTextEdited: {
                                if (canvas.selectedItem && acceptableInput) {
                                    canvas.selectedItem.x = parseInt(text)
                                }
                            }
                        }

                        Label { text: qsTr("Y") }
                        TextField {
                            id: fieldY
                            objectName: "inspectorYField"
                            width: 150
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 0; top: 9999 }
                            onTextEdited: {
                                if (canvas.selectedItem && acceptableInput) {
                                    canvas.selectedItem.y = parseInt(text)
                                }
                            }
                        }

                        Label { text: qsTr("幅") }
                        TextField {
                            id: fieldW
                            objectName: "inspectorWidthField"
                            width: 150
                            inputMethodHints: Qt.ImhDigitsOnly
                            // 最小幅 30（EditableWidget.minWidth と整合）。
                            validator: IntValidator { bottom: 30; top: 9999 }
                            onTextEdited: {
                                if (canvas.selectedItem && acceptableInput) {
                                    canvas.selectedItem.width = parseInt(text)
                                }
                            }
                        }

                        Label { text: qsTr("高さ") }
                        TextField {
                            id: fieldH
                            objectName: "inspectorHeightField"
                            width: 150
                            inputMethodHints: Qt.ImhDigitsOnly
                            // 最小高さ 24（EditableWidget.minHeight と整合）。
                            validator: IntValidator { bottom: 24; top: 9999 }
                            onTextEdited: {
                                if (canvas.selectedItem && acceptableInput) {
                                    canvas.selectedItem.height = parseInt(text)
                                }
                            }
                        }
                    }

                    // Task 27: x/y/width/height は インスペクタ数値編集・移動ドラッグ・
                    // リサイズハンドルの 3 経路で変わる。表示を value/text へ直接バインド
                    // するとユーザー入力で切れて drag/handle 由来の更新を取りこぼすため、
                    // 選択変更時（selectedItem 変化）と選択中 Item の幾何プロパティ変化
                    //（drag/handle）の両方で明示同期する（syncGeometryFields）。
                    Connections {
                        target: canvas
                        function onSelectedItemChanged() {
                            rootWindow.syncGeometryFields()
                        }
                    }
                    Connections {
                        target: canvas.selectedItem
                        ignoreUnknownSignals: true
                        function onXChanged() { rootWindow.syncGeometryFields() }
                        function onYChanged() { rootWindow.syncGeometryFields() }
                        function onWidthChanged() { rootWindow.syncGeometryFields() }
                        function onHeightChanged() { rootWindow.syncGeometryFields() }
                    }

                    // Task 29: スタイル編集（背景色 / 文字色 / 文字サイズ）。
                    // 色は "#RRGGBB" hex の TextField（ColorDialog は任意のため未採用、
                    // まず hex で確実に動かす）。空文字は HmiButton 側で既定外観に
                    // フォールバックされる（widgetBackgroundColor 等は空 = 未指定）。
                    // 編集は T26/T27 と同じ 2 本立て：onTextEdited で live Item へ書き戻し、
                    // Connections.onSelectedItemChanged で選択切替時に表示値を更新する
                    //（text を直接バインドするとユーザー入力でバインディングが切れて
                    // 選択切替に追従しなくなるため）。
                    Label { text: qsTr("スタイル") }

                    Label { text: qsTr("背景色 (#RRGGBB)") }
                    TextField {
                        id: inspectorBgColorField
                        objectName: "inspectorBgColorField"
                        width: parent.width
                        placeholderText: qsTr("#4cc9f0")
                        // Codex PR #58 P2: 空 または 完全な #RRGGBB の時だけ live Item へ
                        // 反映する。途中入力（"#ff"）や不正値（"redx"）が
                        // widgetBackgroundColor に残ると JSON に無効色が保存され、
                        // Simulator/Runtime の描画で無効色になるため。
                        validator: RegularExpressionValidator {
                            regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                        }
                        onTextEdited: {
                            if (canvas.selectedItem && acceptableInput) {
                                canvas.selectedItem.widgetBackgroundColor = text
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorBgColorField.text = canvas.selectedItem
                                    ? canvas.selectedItem.widgetBackgroundColor : ""
                            }
                        }
                    }

                    Label { text: qsTr("文字色 (#RRGGBB)") }
                    TextField {
                        id: inspectorTextColorField
                        objectName: "inspectorTextColorField"
                        width: parent.width
                        placeholderText: qsTr("white")
                        // Codex PR #58 P2: 背景色と同じく、空 または 完全な #RRGGBB の
                        // 時だけ反映する（途中入力・不正値を live Item に書き戻さない）。
                        validator: RegularExpressionValidator {
                            regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                        }
                        onTextEdited: {
                            if (canvas.selectedItem && acceptableInput) {
                                canvas.selectedItem.widgetTextColor = text
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorTextColorField.text = canvas.selectedItem
                                    ? canvas.selectedItem.widgetTextColor : ""
                            }
                        }
                    }

                    // 文字サイズは SpinBox（範囲 6〜96 px）。editable は付けない：
                    // Task 27 で editable な SpinBox は value をプログラム設定しても
                    // 表示テキストが更新されない不具合を確認したため（非 editable なら
                    // value 設定で表示が正しく更新される）。0/未指定は HmiButton 側で
                    // 既定 14px にフォールバックされるので、ここでは既定 14 を表示する。
                    Label { text: qsTr("文字サイズ") }
                    SpinBox {
                        id: inspectorFontSizeSpin
                        objectName: "inspectorFontSizeSpin"
                        from: 6
                        to: 96
                        value: 14
                        // ユーザー操作（valueModified）でのみ書き戻す。プログラムからの
                        // value 代入では発火しないため書き戻しループは起きない。
                        onValueModified: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetFontSize = value
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                const it = canvas.selectedItem
                                // 0/未指定は既定 14 を表示（HmiButton の resolvedFontSize と整合）。
                                inspectorFontSizeSpin.value = (it && it.widgetFontSize > 0)
                                    ? it.widgetFontSize : 14
                            }
                        }
                    }

                    // Task 33: フォント詳細（太字 / 斜体 / フォント）。bool は CheckBox、
                    // フォントは ComboBox（hex TextField・SpinBox に続く新インスペクタ UI 型）。
                    // 編集は T26 以降と同じ 2 本立て：ユーザー操作（CheckBox.toggled /
                    // ComboBox.activated）でのみ live Item へ書き戻し（プログラム代入では
                    // 発火しないので書き戻しループを起こさない）、Connections.onSelectedItemChanged
                    // で選択切替時に表示値を更新する。
                    CheckBox {
                        id: inspectorFontBoldCheck
                        objectName: "inspectorFontBoldCheck"
                        text: qsTr("太字")
                        // Task 38（Codex PR #77 [Major]）：CheckBox はフォーカス境界
                        // （inspectorFieldFocused）に含まれず onToggled で live Item を直接
                        // 変えるため、ここで明示的に beginEdit→commitEdit して 1 操作を
                        // undo へ積む（離散操作なので開始即確定で 1 件）。
                        onToggled: {
                            if (canvas.selectedItem) {
                                canvas.beginEdit()
                                canvas.selectedItem.widgetFontBold = checked
                                canvas.commitEdit()
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorFontBoldCheck.checked = canvas.selectedItem
                                    ? canvas.selectedItem.widgetFontBold : false
                            }
                        }
                    }

                    CheckBox {
                        id: inspectorFontItalicCheck
                        objectName: "inspectorFontItalicCheck"
                        text: qsTr("斜体")
                        // Task 38（Codex PR #77 [Major]）：太字 CheckBox と同様に明示で
                        // undo へ積む（フォーカス境界に含まれないため）。
                        onToggled: {
                            if (canvas.selectedItem) {
                                canvas.beginEdit()
                                canvas.selectedItem.widgetFontItalic = checked
                                canvas.commitEdit()
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorFontItalicCheck.checked = canvas.selectedItem
                                    ? canvas.selectedItem.widgetFontItalic : false
                            }
                        }
                    }

                    // フォント family は ComboBox。model 先頭に「(既定フォント)」を置き、
                    // index 0 = 未指定（空文字 = システム既定）にマップする。残りは
                    // Qt.fontFamilies()（生成時に一度評価）。読込 JSON の family が
                    // システムに無い（model に無い）場合は表示だけ index 0 に落とし、
                    // live Item の値は上書きしない（ユーザーが選び直すまで保持する）。
                    Label { text: qsTr("フォント") }
                    ComboBox {
                        id: inspectorFontFamilyCombo
                        objectName: "inspectorFontFamilyCombo"
                        width: parent.width
                        model: ["(既定フォント)"].concat(Qt.fontFamilies())
                        // index 0（既定フォント）は空文字 = 未指定として書き戻す。
                        onActivated: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetFontFamily =
                                    (currentIndex === 0 ? "" : currentText)
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                const it = canvas.selectedItem
                                const fam = it ? it.widgetFontFamily : ""
                                const idx = fam
                                    ? inspectorFontFamilyCombo.model.indexOf(fam) : 0
                                inspectorFontFamilyCombo.currentIndex = idx >= 0 ? idx : 0
                            }
                        }
                    }

                    // Task 31: ボーダー＋角丸の編集。背景色 / 文字色 / 文字サイズ（Task 29）と
                    // 同型の 2 本立て（onTextEdited/onValueModified で live Item へ書き戻し、
                    // Connections.onSelectedItemChanged で表示同期）。数値は **0 が正当値**
                    //（borderWidth=0=ボーダーなし、radius=0=角丸なし）なので、SpinBox の
                    // from を 0 にし、未指定（-1）は HmiButton の既定（太さ 1 / 角丸 4）を表示する。
                    Label { text: qsTr("ボーダー色 (#RRGGBB)") }
                    TextField {
                        id: inspectorBorderColorField
                        objectName: "inspectorBorderColorField"
                        width: parent.width
                        placeholderText: qsTr("#1d3557")
                        // 背景色・文字色と同じく、空 または 完全な #RRGGBB の時だけ反映する
                        //（途中入力・不正値を live Item に書き戻さない。Codex PR #58 P2）。
                        validator: RegularExpressionValidator {
                            regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                        }
                        onTextEdited: {
                            if (canvas.selectedItem && acceptableInput) {
                                canvas.selectedItem.widgetBorderColor = text
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorBorderColorField.text = canvas.selectedItem
                                    ? canvas.selectedItem.widgetBorderColor : ""
                            }
                        }
                    }

                    // ボーダー太さ / 角丸は SpinBox（from: 0 で 0 を選べる）。editable は付けない
                    //（Task 27: editable な SpinBox は value プログラム設定で表示が更新されない不具合）。
                    Label { text: qsTr("ボーダー太さ") }
                    SpinBox {
                        id: inspectorBorderWidthSpin
                        objectName: "inspectorBorderWidthSpin"
                        from: 0
                        to: 32
                        value: 1
                        onValueModified: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetBorderWidth = value
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                const it = canvas.selectedItem
                                // -1/未指定は既定 1 を表示（HmiButton の resolvedBorderWidth と整合）。
                                // 0 は正当値（ボーダーなし）なのでそのまま表示する。
                                inspectorBorderWidthSpin.value = (it && it.widgetBorderWidth >= 0)
                                    ? it.widgetBorderWidth : 1
                            }
                        }
                    }

                    Label { text: qsTr("角丸") }
                    SpinBox {
                        id: inspectorRadiusSpin
                        objectName: "inspectorRadiusSpin"
                        from: 0
                        to: 200
                        value: 4
                        onValueModified: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetRadius = value
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                const it = canvas.selectedItem
                                // -1/未指定は既定 4 を表示（HmiButton の resolvedCornerRadius と整合）。
                                // 0 は正当値（角丸なし）なのでそのまま表示する。
                                inspectorRadiusSpin.value = (it && it.widgetRadius >= 0)
                                    ? it.widgetRadius : 4
                            }
                        }
                    }

                    // Task 34: テキスト配置（水平 / 垂直）+ 不透明度。配置は ComboBox（フォント
                    // と同型）で、表示ラベルと enum 文字列を **parallel な values 配列** でマップ
                    // する（index 0 = "(既定:中央)" = 空文字 = 未指定）。2 本立て（onActivated で
                    // 書き戻し、Connections.onSelectedItemChanged で表示同期）は他項目と同じ。
                    Label { text: qsTr("水平配置") }
                    ComboBox {
                        id: inspectorHAlignCombo
                        objectName: "inspectorHAlignCombo"
                        width: parent.width
                        // 表示ラベル（model）と書き戻す enum 文字列（values）を index で対応させる。
                        readonly property var values: ["", "left", "center", "right"]
                        model: [qsTr("(既定:中央)"), qsTr("左"), qsTr("中央"), qsTr("右")]
                        onActivated: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetHAlign = values[currentIndex]
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                const it = canvas.selectedItem
                                const v = it ? it.widgetHAlign : ""
                                const idx = inspectorHAlignCombo.values.indexOf(v)
                                inspectorHAlignCombo.currentIndex = idx >= 0 ? idx : 0
                            }
                        }
                    }

                    Label { text: qsTr("垂直配置") }
                    ComboBox {
                        id: inspectorVAlignCombo
                        objectName: "inspectorVAlignCombo"
                        width: parent.width
                        readonly property var values: ["", "top", "middle", "bottom"]
                        model: [qsTr("(既定:中央)"), qsTr("上"), qsTr("中央"), qsTr("下")]
                        onActivated: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetVAlign = values[currentIndex]
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                const it = canvas.selectedItem
                                const v = it ? it.widgetVAlign : ""
                                const idx = inspectorVAlignCombo.values.indexOf(v)
                                inspectorVAlignCombo.currentIndex = idx >= 0 ? idx : 0
                            }
                        }
                    }

                    // 不透明度は SpinBox（0–100% を 0.0–1.0 にスケール）。editable は付けない
                    //（Task 27: editable な SpinBox は value プログラム設定で表示が更新されない不具合）。
                    // 書き戻しは value/100.0、表示同期は widgetOpatity*100（未指定 -1 は既定 100% を表示）。
                    Label { text: qsTr("不透明度 (%)") }
                    SpinBox {
                        id: inspectorOpacitySpin
                        objectName: "inspectorOpacitySpin"
                        from: 0
                        to: 100
                        value: 100
                        onValueModified: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetOpacity = value / 100.0
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                const it = canvas.selectedItem
                                // -1/未指定は既定 100%（不透明度 1.0）を表示
                                //（HmiButton の resolvedOpacity と整合）。
                                inspectorOpacitySpin.value = (it && it.widgetOpacity >= 0)
                                    ? Math.round(it.widgetOpacity * 100) : 100
                            }
                        }
                    }

                    // Task 40: クリック時アクション（onClick 1 件）。op / target / value を選び
                    // 選択 Item の widgetActions へ書き戻す。target は変数定義 ComboBox 由来。
                    Rectangle { width: parent.width; height: 1; color: "#dddddd" }
                    Label { text: qsTr("クリック時アクション"); font.bold: true; color: "#555555" }

                    Label { text: qsTr("操作") }
                    ComboBox {
                        id: inspectorActionOpCombo
                        objectName: "inspectorActionOpCombo"
                        width: parent.width
                        model: ["(なし)", "setVariable", "toggleVariable"]
                        onActivated: rootWindow.applyActionFromInspector()
                    }
                    Label { text: qsTr("対象変数") }
                    ComboBox {
                        id: inspectorActionTargetCombo
                        objectName: "inspectorActionTargetCombo"
                        width: parent.width
                        model: rootWindow.variableNameModel()
                        onActivated: rootWindow.applyActionFromInspector()
                    }
                    // 値は setVariable のときだけ意味を持つ（toggleVariable では無視）。
                    Label {
                        text: qsTr("値")
                        visible: inspectorActionOpCombo.currentText === "setVariable"
                    }
                    TextField {
                        id: inspectorActionValueField
                        objectName: "inspectorActionValueField"
                        width: parent.width
                        visible: inspectorActionOpCombo.currentText === "setVariable"
                        placeholderText: qsTr("例: true / 10 / hello")
                        onEditingFinished: rootWindow.applyActionFromInspector()
                    }

                    // Task 40: データバインディング（1 件）。property を変数に追従させる。
                    Rectangle { width: parent.width; height: 1; color: "#dddddd" }
                    Label { text: qsTr("バインディング"); font.bold: true; color: "#555555" }

                    Label { text: qsTr("プロパティ") }
                    ComboBox {
                        id: inspectorBindingPropCombo
                        objectName: "inspectorBindingPropCombo"
                        width: parent.width
                        model: ["(なし)", "visible", "backgroundColor", "text", "textColor"]
                        onActivated: rootWindow.applyBindingFromInspector()
                    }
                    Label { text: qsTr("追従変数") }
                    ComboBox {
                        id: inspectorBindingVarCombo
                        objectName: "inspectorBindingVarCombo"
                        width: parent.width
                        model: rootWindow.variableNameModel()
                        onActivated: rootWindow.applyBindingFromInspector()
                    }

                    // Task 40: 選択切替時にアクション / バインディング編集 UI を同期する。
                    Connections {
                        target: canvas
                        function onSelectedItemChanged() {
                            rootWindow.syncActionToInspector()
                            rootWindow.syncBindingToInspector()
                        }
                    }

                    // Task 29: 削除ボタン。構造変更（削除）は Canvas.deleteWidget() に
                    // 集約する（addWidget と対称：live Item をスナップショット → 該当 id
                    // を除いて再代入 → 選択解除）。これで未保存の他 widget 編集が
                    // 巻き戻らない（Phase 4 設計指針）。
                    Button {
                        objectName: "inspectorDeleteButton"
                        text: qsTr("削除")
                        onClicked: {
                            if (canvas.selectedWidgetId) {
                                canvas.deleteWidget(canvas.selectedWidgetId)
                            }
                        }
                    }
                    }
                }
            }
        }

        // キャンバスをインスペクタを除いた左側スペースの中央に配置。
        // Task 7 で Widget 表示は Canvas 内部の Repeater + widgetModel に移譲した。
        // 初期表示の btn001 もモデル初期値で再現している。
        // Task 18: E2E（Spix）からドラッグの drop 先として参照するため objectName を付与。
        Canvas {
            id: canvas
            objectName: "canvas"
            canvasWidth: 800
            canvasHeight: 600
            anchors.verticalCenter: parent.verticalCenter
            x: (parent.width - inspector.width - width) / 2
        }
    }

    // Task 6: JSON 保存ダイアログ
    FileDialog {
        id: saveDialog
        title: qsTr("プロジェクトを保存")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("JSON files (*.json)"), qsTr("All files (*)")]
        defaultSuffix: "json"
        onAccepted: {
            // Canvas 上の live EditableWidget 群を Shared/Schema 互換の Widget
            // リストへ変換（Task 26 で Canvas.snapshotModel() に集約・共用）。
            const widgets = canvas.snapshotModel()
            // Task 39: 読み込んだ変数定義もそのまま保存へ渡す（失わないため）。
            const ok = projectIo.save(saveDialog.selectedFile, "Sample", "Main", widgets,
                                      rootWindow.projectVariables)
            if (!ok) {
                console.warn("プロジェクト保存に失敗:", saveDialog.selectedFile)
            } else {
                console.log("プロジェクト保存:", saveDialog.selectedFile)
            }
        }
    }

    // Task 7: JSON 読込ダイアログ
    FileDialog {
        id: openDialog
        title: qsTr("プロジェクトを開く")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("JSON files (*.json)"), qsTr("All files (*)")]
        onAccepted: {
            const result = projectIo.load(openDialog.selectedFile)
            if (!result || !result.ok) {
                console.warn("プロジェクト読込に失敗:", openDialog.selectedFile)
                return
            }
            // Task 40: 変数定義を widgetModel より先に設定（sync 時に ComboBox 選択肢を揃える）。
            rootWindow.projectVariables = result.variables !== undefined ? result.variables : []
            // Repeater の model を差し替えて Widget 群を再構築する
            canvas.widgetModel = result.widgets
            canvas.clearHistory()  // Task 38: 読込前プロジェクトの undo 履歴は破棄
            console.log("プロジェクト読込:", openDialog.selectedFile,
                        "widgets =", result.widgets.length)
        }
    }
}
