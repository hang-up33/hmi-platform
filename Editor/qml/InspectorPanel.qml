import QtQuick
import QtQuick.Controls

// Task 26 / 44: 右側インスペクタ本体。選択中 Widget の各プロパティを編集する。
// 編集対象は editorCanvas.selectedWidgetId が指す live な EditableWidget
//（editorCanvas.selectedItem で解決）。Simulator / Runtime は読み取り専用のため、
// この編集 UI は Editor のみが持つ（Phase 4 ルール）。項目は InspectorSection で
// グループ化してある（基本 / 文字 / 背景・枠 / 状態 / 動作 / 詳細）。
//
// Task RF-B: Main.qml の肥大化解消のため、インスペクタのフォーム本体と
// インスペクタ専用のヘルパー（フォーカス集約プロパティ / 型判定 / アクション・
// バインディング・系列・幾何の編集関数 / ColorSwatch）をまとめて切り出した
//（リファクタリング計画 RF-B。objectName・編集ロジック・Schema は不変）。
// Canvas / Window への参照は受け口プロパティで受ける（同名バインドの自己参照罠を
// 避けるため別名＝MB-4 罠①）。Project レベルの変数定義（projectVariables）と
// その編集ヘルパー、ダイアログ起動は Window 側の所有のまま editorRoot 経由で呼ぶ。
Rectangle {
    id: root
    objectName: "inspectorPanel"
    width: 260
    color: "#f5f5f5"
    border.color: "#cccccc"
    border.width: 1

    // Main.qml の Canvas（id: canvas）と Window（id: rootWindow）。
    property var editorCanvas: null
    property var editorRoot: null

    // Task 40: 変数パネルの動的 TextField（Repeater 由来で id 固定できない）の編集中フラグ。
    // Delete ショートカットの抑止に使う（各行が onActiveFocusChanged で増減する）。
    property int variableFieldFocusCount: 0

    // Task 8B-D: Trend 系列パネルの動的 TextField（色 / 凡例ラベル、Repeater 由来で
    // id 固定できない）の編集中フラグ。変数定義（widget undo に載せない）と違い、系列は
    // widget 内データなので widget undo 境界（widgetEditFieldFocused）にも含める。
    // Delete ショートカット抑止（inspectorFieldFocused）にも入れる。
    property int seriesFieldFocusCount: 0

    // Task 40: アクション編集（onClick 1 件）。op ComboBox / target ComboBox / value から
    // 選択 Item の widgetActions を組み立てる。op "(なし)" は空配列（アクション無し）。
    function applyActionFromInspector() {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        // 操作 "(なし)" または対象変数 "(未選択)" のときはアクション無し（空配列）。
        // **空 target のアクションを保存しない**：ActionData.isValidJson が空 target を
        // 無効としプロジェクト全体が再読込不能になるため（Codex PR #80 [P1]）。
        if (inspectorActionOpCombo.currentIndex === 0
                || inspectorActionTargetCombo.currentIndex === 0) {
            root.editorCanvas.selectedItem.widgetActions = []
            return
        }
        const op = inspectorActionOpCombo.currentText
        const target = inspectorActionTargetCombo.currentText
        const value = (op === "setVariable") ? inspectorActionValueField.text : ""
        root.editorCanvas.selectedItem.widgetActions = [{
            trigger: "onClick", op: op, target: target, value: value
        }]
    }
    // 選択切替時にアクション編集 UI を選択 Item の値へ同期する。
    function syncActionToInspector() {
        const it = root.editorCanvas.selectedItem
        const a = (it && it.widgetActions && it.widgetActions.length > 0)
            ? it.widgetActions[0] : null
        inspectorActionOpCombo.currentIndex = a
            ? Math.max(0, inspectorActionOpCombo.model.indexOf(a.op)) : 0
        const names = root.editorRoot.variableNameModel()
        inspectorActionTargetCombo.currentIndex = (a && a.target)
            ? Math.max(0, names.indexOf(a.target)) : 0
        inspectorActionValueField.text = (a && a.value !== undefined) ? a.value : ""
    }

    // Task 40: バインディング編集（1 件）。property ComboBox / variable ComboBox から
    // 選択 Item の widgetBindings を組み立てる。property "(なし)" or variable "(未選択)" は空。
    function applyBindingFromInspector() {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        if (inspectorBindingPropCombo.currentIndex === 0
                || inspectorBindingVarCombo.currentIndex === 0) {
            root.editorCanvas.selectedItem.widgetBindings = []
            return
        }
        root.editorCanvas.selectedItem.widgetBindings = [{
            property: inspectorBindingPropCombo.currentText,
            variable: inspectorBindingVarCombo.currentText
        }]
    }
    function syncBindingToInspector() {
        const it = root.editorCanvas.selectedItem
        const b = (it && it.widgetBindings && it.widgetBindings.length > 0)
            ? it.widgetBindings[0] : null
        inspectorBindingPropCombo.currentIndex = b
            ? Math.max(0, inspectorBindingPropCombo.model.indexOf(b.property)) : 0
        const names = root.editorRoot.variableNameModel()
        inspectorBindingVarCombo.currentIndex = (b && b.variable)
            ? Math.max(0, names.indexOf(b.variable)) : 0
    }

    // Task 8B-D: Trend 系列エディタ。系列は選択中 live Item の widgetSeries
    //（[{variable, color, label}] 配列）を真実とし、**配列を丸ごと置換**して編集する
    // （アクション / バインディングと同じ流儀＝in-place 変更しないので参照共有でも安全）。
    // 系列の追加 / 削除は構造変更なので pushUndo() で 1 件積む（CheckBox と同じ離散操作。
    // 連続編集〔色 hex 手入力 / ラベル入力〕は各 TextField のフォーカス境界が
    // beginEdit/commitEdit を拾うため明示しない）。
    function currentSeries() {
        const it = root.editorCanvas.selectedItem
        if (!it || it.widgetSeries === undefined || it.widgetSeries === null) {
            return []
        }
        return it.widgetSeries
    }
    function addSeries() {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        root.editorCanvas.pushUndo()
        const next = currentSeries().slice()
        next.push({ variable: "", color: "", label: "" })
        root.editorCanvas.selectedItem.widgetSeries = next
    }
    function removeSeries(index) {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        const next = currentSeries().slice()
        if (index < 0 || index >= next.length) {
            return
        }
        root.editorCanvas.pushUndo()
        next.splice(index, 1)
        root.editorCanvas.selectedItem.widgetSeries = next
    }
    function updateSeries(index, key, value) {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        const next = currentSeries().slice()
        if (index < 0 || index >= next.length) {
            return
        }
        // 行オブジェクトを複製してから書き換える（live/undo の参照共有を切る）。
        const row = {
            variable: next[index].variable !== undefined ? next[index].variable : "",
            color: next[index].color !== undefined ? next[index].color : "",
            label: next[index].label !== undefined ? next[index].label : ""
        }
        row[key] = value
        next[index] = row
        root.editorCanvas.selectedItem.widgetSeries = next
    }

    // Task 26: 選択中の live な EditableWidget はインスペクタの編集対象。
    // 解決ロジックと所有は Canvas に集約した（editorCanvas.selectedItem）。Repeater
    // 再生成後も同一 id の新しい live Item に解決し直される（Codex PR #52 P2 指摘
    // への回答。詳細は Canvas.qml の selectedItem コメント）。インスペクタは
    // この live Item を直接 two-way 編集する（widgetModel の var 配列は据え置き
    // ＝Phase 4 設計指針、delegate 再生成を起こさない）。

    // Task 27: 座標・サイズ SpinBox の表示値を選択中 Item の現在値へ同期する。
    // 選択変更・移動ドラッグ・リサイズハンドルのいずれの経路でも呼ばれ、表示を
    // live 値に追従させる。プログラムからの value 代入は valueModified を発火
    // しないため書き戻しループは起きない。未選択時は既定値（from）に戻す。
    function syncGeometryFields() {
        const it = root.editorCanvas.selectedItem
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

    // 座標・サイズの数値欄を ↑/↓ キーで増減する（Shift で ±10）。SpinBox 化された
    // 文字サイズ・ボーダー・角丸・不透明度は標準の矢印キー増減が効くのに対し、
    // X/Y/幅/高さ は TextField + IntValidator（Task 27 の SpinBox 不具合回避）で
    // キー増減が無く「キーボードで微調整できない」差があったため補う。現在値を
    // validator の範囲（bottom/top）へ clamp し、表示と選択中 live Item の両方を
    // 更新する（onTextEdited と同じ書き戻し経路）。フォーカス中の編集なので undo は
    // focus 由来の beginEdit/commitEdit が 1 操作として拾う。
    function nudgeGeometry(field, prop, step) {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        const v = field.validator
        let cur = parseInt(field.text)
        if (isNaN(cur)) {
            cur = v.bottom
        }
        const next = Math.max(v.bottom, Math.min(v.top, cur + step))
        field.text = String(next)
        root.editorCanvas.selectedItem[prop] = next
    }

    // Task 46: 色スウォッチの一辺と、色 TextField がスウォッチ用に空ける幅
    //（スウォッチ + Row spacing 6）。3 つの色フィールドで共有する
    //（CodeRabbit PR #99 nitpick: マジックナンバー 34 の重複を定数化）。
    readonly property int colorSwatchSize: 28
    readonly property int colorSwatchReserve: colorSwatchSize + 6

    // Task 38: 選択中 Widget を編集するインスペクタ欄が編集フォーカス中か。これらの
    // 変更は Canvas の widgetModel に入る（snapshotModel が拾う）ため、Canvas undo の
    // 1 操作境界（beginEdit/commitEdit）のトリガにする。
    // Task 40: 変数定義欄（variableFieldFocusCount）は **ここに含めない**。変数編集は
    // editorRoot.projectVariables を変えるだけで Canvas の widgetModel には入らず、
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
        || inspectorMinValueField.activeFocus
        || inspectorMaxValueField.activeFocus
        // Task T-C: Trend 詳細欄（点数 / Y 軸 min・max / 線色 / 周期）も undo の操作境界に含める。
        || inspectorPointCountSpin.activeFocus
        || inspectorYMinField.activeFocus
        || inspectorYMaxField.activeFocus
        || inspectorLineColorField.activeFocus
        || inspectorSampleMsSpin.activeFocus
        // Task 8B-D: 軸/凡例（Y 目盛り本数）と系列パネルの動的入力欄も undo 境界に含める。
        // 系列の色 / 凡例ラベル TextField はフォーカス取得 → editingFinished（配列置換）→
        // フォーカス喪失（commitEdit）の順なので 1 編集 = 1 undo になる。
        || inspectorYTickCountSpin.activeFocus
        || root.seriesFieldFocusCount > 0
        // Task M-C: Meter 詳細欄（範囲 min/max / 弧色 / 針色 / 目盛り数 / 単位）も undo の操作境界に含める。
        || inspectorMeterMinField.activeFocus
        || inspectorMeterMaxField.activeFocus
        || inspectorArcColorField.activeFocus
        || inspectorNeedleColorField.activeFocus
        || inspectorTickCountSpin.activeFocus
        || inspectorUnitField.activeFocus
        // Task W-E: シンプルボタン詳細欄（形状 / テーマ / 差し色 / 長押し時間）も undo の操作境界に含める。
        || inspectorShapeCombo.activeFocus
        || inspectorThemeCombo.activeFocus
        || inspectorAccentColorField.activeFocus
        || inspectorHoldMsSpin.activeFocus
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
        || root.variableFieldFocusCount > 0

    // Task 48: 選択中 Widget が Label 型か。型に応じてインスペクタの無関係セクション /
    // 項目を隠す（Label は状態・クリックアクション・ボーダー/角丸を非表示。背景色・
    // 不透明度・バインディング・基本・文字・詳細は表示）。editorCanvas.selectedItem は単一選択時
    // のみ非 null なので、複数 / 未選択では false（単一編集フォーム自体が出ない）。
    // **objectName・編集ロジック・Schema は不変で、表示（visible）切替のみ**（plan Task 48）。
    readonly property bool selectedIsLabel:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "Label"

    // Task 51: 選択中 Widget が NumericField 型か。NumericField は入力 Widget で、状態
    // （有効/トグル/初期オン）とクリックアクションを持たない（書きは入力確定＝binding で行う）。
    // 背景・枠・文字・配置・不透明度・バインディングは持つ（背景・枠は Label と違い全部表示）。
    readonly property bool selectedIsNumericField:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "NumericField"

    // Task T-C: 選択中 Widget が Trend 型か。Trend は表示専用（ライブ折れ線）で、状態
    //（トグル/初期オン）・クリックアクション・文字（フォント）を持たない。背景・枠（グラフ枠）・
    // 不透明度・有効・バインディング（サンプル対象変数 = value 読み）は持つ。Trend 詳細
    //（点数 / Y 軸 / 線色 / 周期）は selectedIsTrend で出し分ける。
    readonly property bool selectedIsTrend:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "Trend"

    // Task M-C: 選択中 Widget が Meter 型か。Meter は表示専用（車のスピードメーター風＝
    // 円弧 + 針）で、状態（トグル/初期オン）・クリックアクション・文字（フォント）を持たない。
    // 背景・枠（メーター枠）・不透明度・有効・バインディング（表示対象変数 = value 読み）は持つ。
    // Meter 詳細（範囲 min/max / 弧色 / 針色 / 目盛り数 / 単位）は selectedIsMeter で出し分ける。
    readonly property bool selectedIsMeter:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "Meter"

    // Task W-E: 選択中 Widget が SimpleButton 型か。SimpleButton はテーマが外観を決めるため
    // 文字（フォント）・背景・枠セクションを隠し、固有の「シンプルボタン詳細」（形状 / テーマ /
    // 差し色 / 長押し時間）を出す。状態（有効 + ON/OFF＝checked）とバインディング（checked の
    // 値源）は表示する。クリックアクションは持たない（状態遷移は checked binding 経路へ一本化。
    // toggleVariable アクションと併用すると二重トグルになるため。Codex PR #164 [P2]）。
    readonly property bool selectedIsSimpleButton:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "SimpleButton"

    // Task 51 / T-C / M-C: クリックアクション（onClick）を扱える Widget か（= Button のみ）。Label /
    // NumericField / Trend / Meter はクリックアクションを持たないため、`!selectedIsLabel && …`
    // を毎回連結せず派生プロパティへまとめる（今後の入力 / 表示 Widget 追加で破綻しにくい。
    // 新たに「クリックアクション非対応」種別が増えたらここだけ直せばよい）。Trend / Meter は
    // Label の既存抑制（selectedIsLabel）と独立に AND するだけで競合しない（派生 1 本に集約）。
    // Task W-E: SimpleButton もクリックアクション非対応（長押しトグル＝checked binding 経路のみ）。
    readonly property bool selectedSupportsClickAction:
        !selectedIsLabel && !selectedIsNumericField && !selectedIsTrend && !selectedIsMeter
        && !selectedIsSimpleButton

    // Task 38: インスペクタの Widget 編集を undo の 1 操作境界にする。どれかの入力欄が
    // フォーカスを得た時に前状態を保留（beginEdit）し、全フィールドからフォーカスが
    // 外れた時に確定（commitEdit、状態が変わっていれば 1 件積む）。これで「フィールドを
    // 触った 1 セッション = 1 undo」になり、キーストロークごとに積まれない。
    onWidgetEditFieldFocusedChanged: {
        if (widgetEditFieldFocused) {
            root.editorCanvas.beginEdit()
        } else {
            root.editorCanvas.commitEdit()
        }
    }

    // Task 46: hex TextField の隣に置く色スウォッチ（現在色のプレビュー兼
    // ColorDialog の起動ボタン）。3 つの色フィールド（背景 / 文字 / ボーダー）で
    // 使い回すインラインコンポーネント。field の hex が妥当ならその色、
    // 空・編集途中は fallback（HmiButton の resolved* 既定色 = 実際の描画色）を見せる。
    component ColorSwatch: Rectangle {
        id: swatch
        // 連動する hex TextField（現在色の参照元・ColorDialog の書き戻し先）。
        property var field: null
        // 選択中 live Item へ書き戻すプロパティ名（"widgetBackgroundColor" 等）。
        property string targetProperty: ""
        // 未指定（空文字）のとき見せる既定色。HmiButton の resolved* と揃える。
        property color fallback: "white"

        width: root.colorSwatchSize
        height: root.colorSwatchSize
        radius: 4
        border.color: "#999999"
        border.width: 1
        color: (field && field.text !== "" && field.acceptableInput)
            ? field.text : fallback

        ToolTip.text: qsTr("クリックで色を選択")
        ToolTip.visible: swatchArea.containsMouse
        ToolTip.delay: 600

        MouseArea {
            id: swatchArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.editorRoot.openColorDialog(
                swatch.field, swatch.targetProperty, swatch.fallback)
        }
    }

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

        // インスペクタを端まで送ったときに「ぐいーっ」と伸びて跳ね返る
        // overshoot（既定の DragAndOvershootBounds）を止め、端でピタッと
        // 止める。ScrollView の実体 Flickable（contentItem）へ設定する。
        Component.onCompleted: contentItem.boundsBehavior = Flickable.StopAtBounds

        Column {
            width: inspectorScroll.availableWidth
            spacing: 8

            Label {
                text: qsTr("インスペクタ")
                font.pixelSize: 16
                font.bold: true
            }

            // Task W-C（Phase 11）: サンプルパレット（選択に依らず常時表示）。プリセットを
            // 実 Widget の見た目で並べ、セルのクリックでキャンバス中央へ追加する。
            SamplePalette {
                objectName: "samplePalette"
                onPresetActivated: function(preset) {
                    root.editorCanvas.addPresetWidget(preset)
                }
            }

            // Task 40 / 44: Project レベルの変数定義パネル（選択に依らず常時表示）。
            // 変数の追加 / 削除 / 名前・型・初期値の編集を行い、editorRoot.projectVariables を
            // 駆動する。アクション target / バインディング variable の ComboBox 選択肢になる。
            // Task 44: 折りたたみ可能なセクションに収める。
            InspectorSection {
                objectName: "variablePanel"
                title: qsTr("変数定義")

                Repeater {
                    model: root.editorRoot.projectVariables
                    delegate: Column {
                        id: varRow
                        required property var modelData
                        required property int index
                        // Phase 7 / MB-1: source を持つ変数は PLC レジスタ写像つき
                        //（接続先 + レジスタ）の編集欄を展開する。
                        readonly property var rowSource:
                            varRow.modelData.source !== undefined ? varRow.modelData.source : null
                        // Phase 9 / OP-1: 接続 proto（"modbusTcp" / "opcua"）。欠落時は modbusTcp。
                        readonly property string rowProto:
                            (varRow.rowSource && varRow.rowSource.proto !== undefined
                             && varRow.rowSource.proto !== "") ? varRow.rowSource.proto : "modbusTcp"
                        width: parent.width
                        spacing: 4

                        Row {
                            width: parent.width
                            spacing: 4

                            TextField {
                                id: varNameField
                                objectName: "variableName_" + varRow.index
                                width: 80
                                text: varRow.modelData.name !== undefined ? varRow.modelData.name : ""
                                placeholderText: qsTr("名前")
                                // **空名・重複名を保存しない**：空名は VariableData.isValidJson が
                                // 無効としプロジェクト全体が再読込不能になり（Codex PR #80 [P1]）、
                                // 重複名は VariableStore（名前キー map）で後勝ちになり参照先を
                                // 区別できなくなる（Codex PR #80 [P2]）。どちらも元の名前へ戻す
                                // （削除は × ボタンで行う）。
                                onEditingFinished: {
                                    if (text.length > 0
                                            && !root.editorRoot.isVariableNameTaken(varRow.index, text)) {
                                        root.editorRoot.updateVariable(varRow.index, "name", text)
                                    } else {
                                        text = Qt.binding(function() {
                                            return varRow.modelData.name !== undefined
                                                ? varRow.modelData.name : ""
                                        })
                                    }
                                }
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }
                            ComboBox {
                                objectName: "variableType_" + varRow.index
                                width: 80
                                model: ["bool", "int", "real", "string"]
                                currentIndex: Math.max(0, model.indexOf(varRow.modelData.type))
                                onActivated: root.editorRoot.updateVariable(varRow.index, "type", currentText)
                            }
                            TextField {
                                objectName: "variableInitial_" + varRow.index
                                width: 60
                                text: varRow.modelData.initial !== undefined ? varRow.modelData.initial : ""
                                placeholderText: qsTr("初期値")
                                onEditingFinished: root.editorRoot.updateVariable(varRow.index, "initial", text)
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }
                            Button {
                                objectName: "variableDelete_" + varRow.index
                                text: qsTr("×")
                                onClicked: root.editorRoot.removeVariable(varRow.index)
                            }
                        }

                        // Phase 7 / MB-1: PLC 接続写像（source）の有効化トグル。
                        // チェックで variable.source を付ける（内部変数 ↔ PLC 変数）。
                        CheckBox {
                            objectName: "variableSourceEnabled_" + varRow.index
                            text: qsTr("PLC レジスタに割当")
                            checked: varRow.rowSource !== null
                            onToggled: root.editorRoot.setVariableSourceEnabled(varRow.index, checked)
                        }

                        // 接続先 + レジスタ写像の編集欄（source ありのときのみ）。実通信はせず
                        // 入力値を JSON（保存時 connections[] と variable.source）へ書くだけ。
                        Grid {
                            objectName: "variableSourceGrid_" + varRow.index
                            visible: varRow.rowSource !== null
                            columns: 2
                            rowSpacing: 4
                            columnSpacing: 6
                            leftPadding: 12

                            // Phase 9 / OP-1: プロトコル選択。modbusTcp（host/port/unitId/reg/
                            // address）と opcua（endpoint/nodeId）で下の入力欄を出し分ける。
                            Label { text: qsTr("プロトコル") }
                            ComboBox {
                                objectName: "variableSourceProto_" + varRow.index
                                width: 120
                                model: ["modbusTcp", "opcua"]
                                currentIndex: Math.max(0, model.indexOf(varRow.rowProto))
                                onActivated: root.editorRoot.updateVariableSourceProto(varRow.index, currentText)
                            }

                            // --- Modbus 用フィールド（proto === "modbusTcp" のとき表示） ---
                            Label {
                                text: qsTr("ホスト")
                                visible: varRow.rowProto === "modbusTcp"
                            }
                            TextField {
                                objectName: "variableSourceHost_" + varRow.index
                                visible: varRow.rowProto === "modbusTcp"
                                width: 120
                                text: varRow.rowSource ? (varRow.rowSource.host !== undefined ? varRow.rowSource.host : "") : ""
                                placeholderText: qsTr("192.168.0.10")
                                onEditingFinished: root.editorRoot.updateVariableSource(varRow.index, "host", text)
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }

                            Label {
                                text: qsTr("ポート")
                                visible: varRow.rowProto === "modbusTcp"
                            }
                            TextField {
                                objectName: "variableSourcePort_" + varRow.index
                                visible: varRow.rowProto === "modbusTcp"
                                width: 80
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 1; top: 65535 }
                                text: varRow.rowSource ? String(varRow.rowSource.port !== undefined ? varRow.rowSource.port : 502) : ""
                                placeholderText: qsTr("502")
                                onEditingFinished: if (acceptableInput) root.editorRoot.updateVariableSource(varRow.index, "port", parseInt(text, 10))
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }

                            Label {
                                text: qsTr("Unit ID")
                                visible: varRow.rowProto === "modbusTcp"
                            }
                            TextField {
                                objectName: "variableSourceUnitId_" + varRow.index
                                visible: varRow.rowProto === "modbusTcp"
                                width: 80
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 0; top: 255 }
                                text: varRow.rowSource ? String(varRow.rowSource.unitId !== undefined ? varRow.rowSource.unitId : 1) : ""
                                placeholderText: qsTr("1")
                                onEditingFinished: if (acceptableInput) root.editorRoot.updateVariableSource(varRow.index, "unitId", parseInt(text, 10))
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }

                            Label {
                                text: qsTr("レジスタ")
                                visible: varRow.rowProto === "modbusTcp"
                            }
                            ComboBox {
                                objectName: "variableSourceReg_" + varRow.index
                                visible: varRow.rowProto === "modbusTcp"
                                width: 120
                                model: ["coil", "discrete", "input", "holding"]
                                currentIndex: Math.max(0, model.indexOf(varRow.rowSource ? varRow.rowSource.reg : "holding"))
                                onActivated: root.editorRoot.updateVariableSource(varRow.index, "reg", currentText)
                            }

                            // address は 0 始まりのプロトコル番地（JSON / 内部の正準は 0 ベース）。
                            Label {
                                text: qsTr("アドレス")
                                visible: varRow.rowProto === "modbusTcp"
                            }
                            TextField {
                                objectName: "variableSourceAddress_" + varRow.index
                                visible: varRow.rowProto === "modbusTcp"
                                width: 80
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 0; top: 65535 }
                                text: varRow.rowSource ? String(varRow.rowSource.address !== undefined ? varRow.rowSource.address : 0) : ""
                                placeholderText: qsTr("0")
                                onEditingFinished: if (acceptableInput) root.editorRoot.updateVariableSource(varRow.index, "address", parseInt(text, 10))
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }

                            // --- OPC-UA 用フィールド（proto === "opcua" のとき表示） ---
                            Label {
                                text: qsTr("エンドポイント")
                                visible: varRow.rowProto === "opcua"
                            }
                            TextField {
                                objectName: "variableSourceEndpoint_" + varRow.index
                                visible: varRow.rowProto === "opcua"
                                width: 180
                                text: varRow.rowSource ? (varRow.rowSource.endpoint !== undefined ? varRow.rowSource.endpoint : "") : ""
                                placeholderText: qsTr("opc.tcp://192.168.0.20:4840")
                                onEditingFinished: root.editorRoot.updateVariableSource(varRow.index, "endpoint", text)
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }

                            Label {
                                text: qsTr("ノード ID")
                                visible: varRow.rowProto === "opcua"
                            }
                            TextField {
                                objectName: "variableSourceNodeId_" + varRow.index
                                visible: varRow.rowProto === "opcua"
                                width: 180
                                text: varRow.rowSource ? (varRow.rowSource.nodeId !== undefined ? varRow.rowSource.nodeId : "") : ""
                                placeholderText: qsTr("ns=2;s=Spindle.Temp")
                                onEditingFinished: root.editorRoot.updateVariableSource(varRow.index, "nodeId", text)
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }

                            // ポーリング周期は両プロトコル共通。OPC-UA は購読が主なので poll=0
                            //（購読のみ）を許す＝下限を proto で切替える（opcua→0 / modbusTcp→1）。
                            // Codex/CodeRabbit PR #140。
                            Label { text: qsTr("ポーリング(ms)") }
                            TextField {
                                objectName: "variableSourcePoll_" + varRow.index
                                width: 80
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator {
                                    bottom: varRow.rowProto === "opcua" ? 0 : 1
                                    top: 600000
                                }
                                text: varRow.rowSource
                                    ? String(varRow.rowSource.poll !== undefined
                                             ? varRow.rowSource.poll
                                             : (varRow.rowProto === "opcua" ? 0 : 1000))
                                    : ""
                                placeholderText: varRow.rowProto === "opcua" ? qsTr("0") : qsTr("1000")
                                onEditingFinished: if (acceptableInput) root.editorRoot.updateVariableSource(varRow.index, "poll", parseInt(text, 10))
                                onActiveFocusChanged: root.variableFieldFocusCount += activeFocus ? 1 : -1
                            }
                        }

                        Rectangle {
                            visible: varRow.index < root.editorRoot.projectVariables.length - 1
                            width: parent.width
                            height: 1
                            color: "#eeeeee"
                        }
                    }
                }

                Button {
                    objectName: "addVariableButton"
                    text: qsTr("変数を追加")
                    onClicked: root.editorRoot.addVariable()
                }
            }

            Rectangle { width: parent.width; height: 1; color: "#dddddd" }

            // 未選択時の案内（Task 36: 0 個選択のときのみ）
            Label {
                objectName: "inspectorEmptyLabel"
                visible: root.editorCanvas.selectedWidgetIds.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#888888"
                text: qsTr("Widget を選択してください")
            }

            // Task 36: 複数選択時のパネル。単一プロパティ編集は単一選択時のみとし、
            // 複数選択時は「N 個選択中」+ 一括整列 / 分布 / 削除のアクションを提供する。
            Column {
                objectName: "inspectorMultiPanel"
                visible: root.editorCanvas.selectedWidgetIds.length > 1
                width: parent.width
                spacing: 8

                Label {
                    objectName: "inspectorMultiLabel"
                    width: parent.width
                    font.bold: true
                    text: root.editorCanvas.selectedWidgetIds.length + qsTr(" 個選択中")
                }

                Label { text: qsTr("整列"); color: "#555555" }
                // 水平方向の整列（左 / 中央 / 右）
                Row {
                    spacing: 4
                    Button { objectName: "alignLeftButton";    text: qsTr("左");   onClicked: root.editorCanvas.alignSelected("left") }
                    Button { objectName: "alignHCenterButton"; text: qsTr("中央"); onClicked: root.editorCanvas.alignSelected("hcenter") }
                    Button { objectName: "alignRightButton";   text: qsTr("右");   onClicked: root.editorCanvas.alignSelected("right") }
                }
                // 垂直方向の整列（上 / 中央 / 下）
                Row {
                    spacing: 4
                    Button { objectName: "alignTopButton";     text: qsTr("上");   onClicked: root.editorCanvas.alignSelected("top") }
                    Button { objectName: "alignVCenterButton"; text: qsTr("中央"); onClicked: root.editorCanvas.alignSelected("vcenter") }
                    Button { objectName: "alignBottomButton";  text: qsTr("下");   onClicked: root.editorCanvas.alignSelected("bottom") }
                }

                Label { text: qsTr("等間隔分布（3 個以上）"); color: "#555555" }
                Row {
                    spacing: 4
                    Button { objectName: "distributeHButton"; text: qsTr("水平"); onClicked: root.editorCanvas.distributeSelected("h") }
                    Button { objectName: "distributeVButton"; text: qsTr("垂直"); onClicked: root.editorCanvas.distributeSelected("v") }
                }

                Button {
                    objectName: "inspectorMultiDeleteButton"
                    text: qsTr("選択をすべて削除")
                    onClicked: root.editorCanvas.deleteWidgets(root.editorCanvas.selectedWidgetIds)
                }
            }

            // 選択中の編集フォーム（Task 44: InspectorSection でグループ化）。
            Column {
                objectName: "inspectorForm"
                visible: root.editorCanvas.selectedItem !== null
                width: parent.width
                spacing: 8

                // ── 基本 : Text / 座標・サイズ ──
                InspectorSection {
                    title: qsTr("基本")

                    // Task T-C / M-C: Trend / Meter は文字を持たないため Text 入力（ラベル + 欄）を隠す。
                    Label { text: qsTr("Text"); visible: !root.selectedIsTrend && !root.selectedIsMeter }
                    TextField {
                        id: inspectorTextField
                        objectName: "inspectorTextField"
                        visible: !root.selectedIsTrend && !root.selectedIsMeter
                        width: parent.width
                        // ユーザー入力のみ選択中 Item へ書き戻す
                        // （textEdited はプログラム変更では発火しない）。
                        // Item.widgetText 更新で HmiButton の text バインドが即追従する。
                        onTextEdited: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetText = text
                            }
                        }
                        // 選択が変わったら表示値を選択 Item の値へ更新する。
                        // text を直接バインドするとユーザー入力でバインディングが
                        // 切れ、選択切替時に追従しなくなるため明示更新する。
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorTextField.text = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetText : ""
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
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.x = parseInt(text)
                                }
                            }
                            Keys.onUpPressed: (event) => {
                                root.nudgeGeometry(fieldX, "x", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                                event.accepted = true
                            }
                            Keys.onDownPressed: (event) => {
                                root.nudgeGeometry(fieldX, "x", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
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
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.y = parseInt(text)
                                }
                            }
                            Keys.onUpPressed: (event) => {
                                root.nudgeGeometry(fieldY, "y", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                                event.accepted = true
                            }
                            Keys.onDownPressed: (event) => {
                                root.nudgeGeometry(fieldY, "y", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
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
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.width = parseInt(text)
                                }
                            }
                            Keys.onUpPressed: (event) => {
                                root.nudgeGeometry(fieldW, "width", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                                event.accepted = true
                            }
                            Keys.onDownPressed: (event) => {
                                root.nudgeGeometry(fieldW, "width", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
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
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.height = parseInt(text)
                                }
                            }
                            Keys.onUpPressed: (event) => {
                                root.nudgeGeometry(fieldH, "height", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                                event.accepted = true
                            }
                            Keys.onDownPressed: (event) => {
                                root.nudgeGeometry(fieldH, "height", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
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
                        target: root.editorCanvas
                        function onSelectedItemChanged() {
                            root.syncGeometryFields()
                        }
                    }
                    Connections {
                        target: root.editorCanvas.selectedItem
                        ignoreUnknownSignals: true
                        function onXChanged() { root.syncGeometryFields() }
                        function onYChanged() { root.syncGeometryFields() }
                        function onWidthChanged() { root.syncGeometryFields() }
                        function onHeightChanged() { root.syncGeometryFields() }
                    }
                }

                // ── 文字 : フォント / 文字サイズ / 太字 / 斜体 / 文字色 / 配置 ──
                // Task T-C / M-C: Trend / Meter は文字を持たない（表示専用の折れ線グラフ /
                // メーター）ため文字セクションを丸ごと隠す（型出し分けは visible のみ）。
                InspectorSection {
                    title: qsTr("文字")
                    // Task W-E: SimpleButton はテーマが文字色・サイズを決める（ラベル文字列
                    // 自体は「基本」の Text 欄で編集）ため、フォント詳細を隠す。
                    visible: !root.selectedIsTrend && !root.selectedIsMeter
                             && !root.selectedIsSimpleButton

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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetFontFamily =
                                    (currentIndex === 0 ? "" : currentText)
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                const fam = it ? it.widgetFontFamily : ""
                                const idx = fam
                                    ? inspectorFontFamilyCombo.model.indexOf(fam) : 0
                                inspectorFontFamilyCombo.currentIndex = idx >= 0 ? idx : 0
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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetFontSize = value
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                // 0/未指定は既定 14 を表示（HmiButton の resolvedFontSize と整合）。
                                inspectorFontSizeSpin.value = (it && it.widgetFontSize > 0)
                                    ? it.widgetFontSize : 14
                            }
                        }
                    }

                    // Task 33: フォント詳細（太字 / 斜体）。bool は CheckBox。編集は T26 以降と
                    // 同じ 2 本立て + 明示 beginEdit/commitEdit（CheckBox はフォーカス境界に
                    // 含まれないため離散操作として 1 件 undo へ積む）。
                    CheckBox {
                        id: inspectorFontBoldCheck
                        objectName: "inspectorFontBoldCheck"
                        text: qsTr("太字")
                        // Task 38（Codex PR #77 [Major]）：CheckBox はフォーカス境界
                        // （inspectorFieldFocused）に含まれず onToggled で live Item を直接
                        // 変えるため、ここで明示的に beginEdit→commitEdit して 1 操作を
                        // undo へ積む（離散操作なので開始即確定で 1 件）。
                        onToggled: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.beginEdit()
                                root.editorCanvas.selectedItem.widgetFontBold = checked
                                root.editorCanvas.commitEdit()
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorFontBoldCheck.checked = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetFontBold : false
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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.beginEdit()
                                root.editorCanvas.selectedItem.widgetFontItalic = checked
                                root.editorCanvas.commitEdit()
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorFontItalicCheck.checked = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetFontItalic : false
                            }
                        }
                    }

                    // Task 29: 文字色（"#RRGGBB" hex の TextField）。空文字は HmiButton 側で
                    // 既定外観にフォールバックされる。編集は 2 本立て（onTextEdited で live
                    // Item へ書き戻し、Connections.onSelectedItemChanged で表示同期）。
                    Label { text: qsTr("文字色 (#RRGGBB)") }
                    // Task 46: hex TextField + 色スウォッチ（プレビュー / クリックで
                    // ColorDialog）。手入力欄はそのまま残す（E2E / 既存導線を維持）。
                    // 幅は leftPadding（InspectorSection の content インデント）ぶん
                    // 詰める：parent.width のままだと右端のスウォッチがインデント分
                    // はみ出して ScrollView の clip に切られる。
                    Row {
                        width: parent.width - parent.leftPadding
                        spacing: 6

                        TextField {
                            id: inspectorTextColorField
                            objectName: "inspectorTextColorField"
                            width: parent.width - root.colorSwatchReserve
                            placeholderText: qsTr("white")
                            // Codex PR #58 P2: 空 または 完全な #RRGGBB の時だけ反映する
                            //（途中入力・不正値を live Item に書き戻さない）。
                            validator: RegularExpressionValidator {
                                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                            }
                            onTextEdited: {
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.widgetTextColor = text
                                }
                            }
                            Connections {
                                target: root.editorCanvas
                                function onSelectedItemChanged() {
                                    inspectorTextColorField.text = root.editorCanvas.selectedItem
                                        ? root.editorCanvas.selectedItem.widgetTextColor : ""
                                }
                            }
                        }
                        ColorSwatch {
                            objectName: "inspectorTextColorSwatch"
                            anchors.verticalCenter: parent.verticalCenter
                            field: inspectorTextColorField
                            targetProperty: "widgetTextColor"
                            // 未指定時の既定色は Widget 種別の resolved* と揃える
                            //（HmiButton=white / HmiLabel=#1d3557 / HmiNumericField=#1d3557）。
                            // Task 51: NumericField も Label と同じ濃文字（#1d3557）が既定。
                            fallback: (root.editorCanvas.selectedItem
                                       && (root.editorCanvas.selectedItem.widgetType === "Label"
                                           || root.editorCanvas.selectedItem.widgetType === "NumericField"))
                                ? "#1d3557" : "white"
                        }
                    }

                    // Task 34: テキスト配置（水平 / 垂直）。配置は ComboBox で、表示ラベルと
                    // enum 文字列を parallel な values 配列でマップする（index 0 = "(既定:中央)"
                    // = 空文字 = 未指定）。2 本立て（onActivated で書き戻し、
                    // Connections.onSelectedItemChanged で表示同期）。
                    Label { text: qsTr("水平配置") }
                    ComboBox {
                        id: inspectorHAlignCombo
                        objectName: "inspectorHAlignCombo"
                        width: parent.width
                        // 表示ラベル（model）と書き戻す enum 文字列（values）を index で対応させる。
                        readonly property var values: ["", "left", "center", "right"]
                        model: [qsTr("(既定:中央)"), qsTr("左"), qsTr("中央"), qsTr("右")]
                        onActivated: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetHAlign = values[currentIndex]
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetVAlign = values[currentIndex]
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                const v = it ? it.widgetVAlign : ""
                                const idx = inspectorVAlignCombo.values.indexOf(v)
                                inspectorVAlignCombo.currentIndex = idx >= 0 ? idx : 0
                            }
                        }
                    }
                }

                // ── 背景・枠 : 背景色 / ボーダー / 角丸 / 不透明度 ──
                InspectorSection {
                    title: qsTr("背景・枠")
                    // Task W-E: SimpleButton は面色・縁取り・影をテーマ（light/dark）が
                    // 決めるため、背景・枠セクションごと隠す（backgroundColor/border* は
                    // SimpleButton では未使用＝plan §Schema「流さない」）。
                    visible: !root.selectedIsSimpleButton

                    // Task 29: 背景色（"#RRGGBB" hex の TextField）。空文字は HmiButton 側で
                    // 既定外観にフォールバックされる（widgetBackgroundColor は空 = 未指定）。
                    Label { text: qsTr("背景色 (#RRGGBB)") }
                    // Task 46: hex TextField + 色スウォッチ（プレビュー / クリックで
                    // ColorDialog）。手入力欄はそのまま残す（E2E / 既存導線を維持）。
                    // 幅補正は文字色の Row と同じ（leftPadding ぶん詰める）。
                    Row {
                        width: parent.width - parent.leftPadding
                        spacing: 6

                        TextField {
                            id: inspectorBgColorField
                            objectName: "inspectorBgColorField"
                            width: parent.width - root.colorSwatchReserve
                            placeholderText: qsTr("#4cc9f0")
                            // Codex PR #58 P2: 空 または 完全な #RRGGBB の時だけ live Item へ
                            // 反映する。途中入力（"#ff"）や不正値（"redx"）が
                            // widgetBackgroundColor に残ると JSON に無効色が保存され、
                            // Simulator/Runtime の描画で無効色になるため。
                            validator: RegularExpressionValidator {
                                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                            }
                            onTextEdited: {
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.widgetBackgroundColor = text
                                }
                            }
                            Connections {
                                target: root.editorCanvas
                                function onSelectedItemChanged() {
                                    inspectorBgColorField.text = root.editorCanvas.selectedItem
                                        ? root.editorCanvas.selectedItem.widgetBackgroundColor : ""
                                }
                            }
                        }
                        ColorSwatch {
                            objectName: "inspectorBgColorSwatch"
                            anchors.verticalCenter: parent.verticalCenter
                            field: inspectorBgColorField
                            targetProperty: "widgetBackgroundColor"
                            // 未指定時の既定色は Widget 種別の resolved* と揃える
                            //（HmiButton=#4cc9f0 / HmiLabel=transparent / HmiNumericField=#ffffff /
                            // HmiMeter=#0b1d2a）。Task 51: NumericField は入力欄らしい白背景。
                            // Task M-C: Meter はスピードメーターらしい濃紺背景（#0b1d2a）が既定。
                            fallback: (root.editorCanvas.selectedItem
                                       && root.editorCanvas.selectedItem.widgetType === "Label")
                                ? "transparent"
                                : (root.editorCanvas.selectedItem
                                   && root.editorCanvas.selectedItem.widgetType === "NumericField")
                                    ? "#ffffff"
                                : (root.editorCanvas.selectedItem
                                   && root.editorCanvas.selectedItem.widgetType === "Meter")
                                    ? "#0b1d2a" : "#4cc9f0"
                        }
                    }

                    // Task 31: ボーダー＋角丸の編集。背景色 / 文字色 / 文字サイズ（Task 29）と
                    // 同型の 2 本立て（onTextEdited/onValueModified で live Item へ書き戻し、
                    // Connections.onSelectedItemChanged で表示同期）。数値は **0 が正当値**
                    //（borderWidth=0=ボーダーなし、radius=0=角丸なし）なので、SpinBox の
                    // from を 0 にし、未指定（-1）は HmiButton の既定（太さ 1 / 角丸 4）を表示する。
                    Label {
                        text: qsTr("ボーダー色 (#RRGGBB)")
                        visible: !root.selectedIsLabel
                    }
                    // Task 46: hex TextField + 色スウォッチ（プレビュー / クリックで
                    // ColorDialog）。手入力欄はそのまま残す（E2E / 既存導線を維持）。
                    // 幅補正は文字色の Row と同じ（leftPadding ぶん詰める）。
                    // Task 48: Label はフラット（ボーダー/角丸を持たない）ため、これら 3 項目
                    // （ボーダー色 / 太さ / 角丸）を Label 選択時は隠す（背景色・不透明度は残す）。
                    Row {
                        width: parent.width - parent.leftPadding
                        spacing: 6
                        visible: !root.selectedIsLabel

                        TextField {
                            id: inspectorBorderColorField
                            objectName: "inspectorBorderColorField"
                            width: parent.width - root.colorSwatchReserve
                            placeholderText: qsTr("#1d3557")
                            // 背景色・文字色と同じく、空 または 完全な #RRGGBB の時だけ反映する
                            //（途中入力・不正値を live Item に書き戻さない。Codex PR #58 P2）。
                            validator: RegularExpressionValidator {
                                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                            }
                            onTextEdited: {
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.widgetBorderColor = text
                                }
                            }
                            Connections {
                                target: root.editorCanvas
                                function onSelectedItemChanged() {
                                    inspectorBorderColorField.text = root.editorCanvas.selectedItem
                                        ? root.editorCanvas.selectedItem.widgetBorderColor : ""
                                }
                            }
                        }
                        ColorSwatch {
                            objectName: "inspectorBorderColorSwatch"
                            anchors.verticalCenter: parent.verticalCenter
                            field: inspectorBorderColorField
                            targetProperty: "widgetBorderColor"
                            // 既定色は Widget 種別の resolvedBorderColor と揃える
                            //（HmiButton=#1d3557 / HmiMeter=#9aa5b1）。
                            fallback: (root.editorCanvas.selectedItem
                                       && root.editorCanvas.selectedItem.widgetType === "Meter")
                                ? "#9aa5b1" : "#1d3557"
                        }
                    }

                    // ボーダー太さ / 角丸は SpinBox（from: 0 で 0 を選べる）。editable は付けない
                    //（Task 27: editable な SpinBox は value プログラム設定で表示が更新されない不具合）。
                    Label {
                        text: qsTr("ボーダー太さ")
                        visible: !root.selectedIsLabel
                    }
                    SpinBox {
                        id: inspectorBorderWidthSpin
                        objectName: "inspectorBorderWidthSpin"
                        visible: !root.selectedIsLabel
                        from: 0
                        to: 32
                        value: 1
                        onValueModified: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetBorderWidth = value
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                // -1/未指定は既定 1 を表示（HmiButton の resolvedBorderWidth と整合）。
                                // 0 は正当値（ボーダーなし）なのでそのまま表示する。
                                inspectorBorderWidthSpin.value = (it && it.widgetBorderWidth >= 0)
                                    ? it.widgetBorderWidth : 1
                            }
                        }
                    }

                    Label {
                        text: qsTr("角丸")
                        visible: !root.selectedIsLabel
                    }
                    SpinBox {
                        id: inspectorRadiusSpin
                        objectName: "inspectorRadiusSpin"
                        visible: !root.selectedIsLabel
                        from: 0
                        to: 200
                        value: 4
                        onValueModified: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetRadius = value
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                // -1/未指定は既定 4 を表示（HmiButton の resolvedCornerRadius と整合）。
                                // 0 は正当値（角丸なし）なのでそのまま表示する。
                                inspectorRadiusSpin.value = (it && it.widgetRadius >= 0)
                                    ? it.widgetRadius : 4
                            }
                        }
                    }

                    // Task 34: 不透明度は SpinBox（0–100% を 0.0–1.0 にスケール）。editable は
                    // 付けない（Task 27 の SpinBox 不具合回避）。書き戻しは value/100.0、表示同期は
                    // widgetOpacity*100（未指定 -1 は既定 100% を表示）。
                    Label { text: qsTr("不透明度 (%)") }
                    SpinBox {
                        id: inspectorOpacitySpin
                        objectName: "inspectorOpacitySpin"
                        from: 0
                        to: 100
                        value: 100
                        onValueModified: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetOpacity = value / 100.0
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                // -1/未指定は既定 100%（不透明度 1.0）を表示
                                //（HmiButton の resolvedOpacity と整合）。
                                inspectorOpacitySpin.value = (it && it.widgetOpacity >= 0)
                                    ? Math.round(it.widgetOpacity * 100) : 100
                            }
                        }
                    }
                }

                // ── Trend 詳細（Trend 選択時のみ）: 点数 N / Y 軸 min・max / 線色 / 周期 ──
                // Task T-C: Trend 固有の編集 UI。型出し分けは visible のみ（objectName・
                // 編集ロジック・Schema 不変）。点数 / 周期は int（SpinBox）、Y 軸 min/max は
                // double で **負値も正当なので presence チェック方式**（NumericField の min/max
                // を手本）。線色は色スウォッチ + ColorDialog（Task 46 の色入力を手本）。
                // すべて 2 本立て（onValueModified/onTextEdited で live Item へ書き戻し、
                // Connections.onSelectedItemChanged で表示同期）。
                InspectorSection {
                    objectName: "inspectorTrendSection"
                    title: qsTr("Trend 詳細")
                    visible: root.selectedIsTrend

                    // 点数 N（直近何点を表示するか）。0/未指定は HmiTrend 側で既定 60 へ解決。
                    // SpinBox（editable なし）で from を 2 にし（折れ線は 2 点以上で意味を持つ）、
                    // 未指定（widgetPointCount<=0）は既定 60 を表示する。
                    Label { text: qsTr("点数 (N)") }
                    SpinBox {
                        id: inspectorPointCountSpin
                        objectName: "inspectorPointCountSpin"
                        from: 2
                        to: 2000
                        value: 60
                        ToolTip.text: qsTr("直近に表示するサンプル点数。満杯になると最古を捨てて横スクロールします")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onValueModified: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetPointCount = value
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                // 0/未指定は既定 60 を表示（HmiTrend の resolvedPointCount と整合）。
                                inspectorPointCountSpin.value = (it && it.widgetPointCount > 0)
                                    ? it.widgetPointCount : 60
                            }
                        }
                    }

                    // Y 軸 最小値（presence 方式）。空欄 = 未指定（hasYMin=false → 自動スケール）、
                    // 値を入れると hasYMin=true。負値・小数も許す（NumericField min と同型の
                    // RegularExpressionValidator＝空 または 数値）。
                    Label { text: qsTr("Y 軸 最小値") }
                    TextField {
                        id: inspectorYMinField
                        objectName: "inspectorYMinField"
                        width: parent.width
                        placeholderText: qsTr("(自動)")
                        onActiveFocusChanged: if (activeFocus) selectAll()
                        validator: RegularExpressionValidator {
                            regularExpression: /^(-?\d*\.?\d*)$/
                        }
                        ToolTip.text: qsTr("グラフ下端の値。空欄でデータから自動スケールします")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onTextEdited: {
                            if (root.editorCanvas.selectedItem && acceptableInput) {
                                var t = text.trim()
                                var nv = Number(t)
                                if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                                    root.editorCanvas.selectedItem.widgetHasYMin = false
                                } else {
                                    root.editorCanvas.selectedItem.widgetYMin = nv
                                    root.editorCanvas.selectedItem.widgetHasYMin = true
                                }
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorYMinField.text =
                                    (root.editorCanvas.selectedItem && root.editorCanvas.selectedItem.widgetHasYMin)
                                        ? String(root.editorCanvas.selectedItem.widgetYMin) : ""
                            }
                        }
                    }

                    Label { text: qsTr("Y 軸 最大値") }
                    TextField {
                        id: inspectorYMaxField
                        objectName: "inspectorYMaxField"
                        width: parent.width
                        placeholderText: qsTr("(自動)")
                        onActiveFocusChanged: if (activeFocus) selectAll()
                        validator: RegularExpressionValidator {
                            regularExpression: /^(-?\d*\.?\d*)$/
                        }
                        ToolTip.text: qsTr("グラフ上端の値。空欄でデータから自動スケールします")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onTextEdited: {
                            if (root.editorCanvas.selectedItem && acceptableInput) {
                                var t = text.trim()
                                var nv = Number(t)
                                if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                                    root.editorCanvas.selectedItem.widgetHasYMax = false
                                } else {
                                    root.editorCanvas.selectedItem.widgetYMax = nv
                                    root.editorCanvas.selectedItem.widgetHasYMax = true
                                }
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorYMaxField.text =
                                    (root.editorCanvas.selectedItem && root.editorCanvas.selectedItem.widgetHasYMax)
                                        ? String(root.editorCanvas.selectedItem.widgetYMax) : ""
                            }
                        }
                    }

                    // 線色（"#RRGGBB" hex の TextField + 色スウォッチ）。背景色等と同じ
                    // 2 本立て + ColorDialog 起動（Task 46）。空 = 未指定＝既定線色 #4cc9f0。
                    Label { text: qsTr("線色 (#RRGGBB)") }
                    Row {
                        width: parent.width - parent.leftPadding
                        spacing: 6

                        TextField {
                            id: inspectorLineColorField
                            objectName: "inspectorLineColorField"
                            width: parent.width - root.colorSwatchReserve
                            placeholderText: qsTr("#4cc9f0")
                            validator: RegularExpressionValidator {
                                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                            }
                            onTextEdited: {
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.widgetLineColor = text
                                }
                            }
                            Connections {
                                target: root.editorCanvas
                                function onSelectedItemChanged() {
                                    inspectorLineColorField.text = root.editorCanvas.selectedItem
                                        ? root.editorCanvas.selectedItem.widgetLineColor : ""
                                }
                            }
                        }
                        ColorSwatch {
                            objectName: "inspectorLineColorSwatch"
                            anchors.verticalCenter: parent.verticalCenter
                            field: inspectorLineColorField
                            targetProperty: "widgetLineColor"
                            // HmiTrend.resolvedLineColor の既定と揃える。
                            fallback: "#4cc9f0"
                        }
                    }

                    // サンプル周期[ms]。0/未指定は HmiTrend 側で「変更時サンプルのみ」(方式 A)。
                    // >0 で周期 Timer 駆動(方式 B)。SpinBox（editable なし）で from を 0 にし
                    // 0=変更時のみを選べるようにする。
                    Label { text: qsTr("サンプル周期 (ms)") }
                    SpinBox {
                        id: inspectorSampleMsSpin
                        objectName: "inspectorSampleMsSpin"
                        from: 0
                        to: 600000
                        value: 0
                        stepSize: 100
                        ToolTip.text: qsTr("0 = 変数の変化時のみ取り込み。1 以上で指定ミリ秒ごとに周期サンプリングします")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onValueModified: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetSampleMs = value
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                // 0/未指定はそのまま 0（変更時サンプルのみ）を表示する。
                                inspectorSampleMsSpin.value = (it && it.widgetSampleMs > 0)
                                    ? it.widgetSampleMs : 0
                            }
                        }
                    }

                    // ── 軸 / 凡例（Task 8B-D） ──
                    // グリッド線 / 凡例の表示トグルと Y 目盛り本数。いずれも既定 OFF /
                    // 既定本数（HmiTrend が 0/負値 → 4 に解決）。CheckBox は離散操作なので
                    // 明示 beginEdit/commitEdit、SpinBox は onValueModified の 2 本立て。
                    Rectangle { width: parent.width; height: 1; color: "#dddddd" }
                    Label { text: qsTr("軸 / 凡例"); font.bold: true; color: "#555555" }

                    CheckBox {
                        id: inspectorShowGridCheck
                        objectName: "inspectorShowGridCheck"
                        text: qsTr("グリッド線を表示")
                        ToolTip.text: qsTr("水平グリッド線と Y 軸目盛りラベルを描画します")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onToggled: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.beginEdit()
                                root.editorCanvas.selectedItem.widgetShowGrid = checked
                                root.editorCanvas.commitEdit()
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorShowGridCheck.checked = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetShowGrid : false
                            }
                        }
                    }

                    CheckBox {
                        id: inspectorShowLegendCheck
                        objectName: "inspectorShowLegendCheck"
                        text: qsTr("凡例を表示")
                        ToolTip.text: qsTr("系列の色スウォッチとラベルを凡例として描画します")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onToggled: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.beginEdit()
                                root.editorCanvas.selectedItem.widgetShowLegend = checked
                                root.editorCanvas.commitEdit()
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorShowLegendCheck.checked = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetShowLegend : false
                            }
                        }
                    }

                    // Y 目盛り本数。0/未指定は HmiTrend 側で既定 4 へ解決。
                    // SpinBox（editable なし）で from を 0（=既定）にする。
                    Label { text: qsTr("Y 目盛り本数") }
                    SpinBox {
                        id: inspectorYTickCountSpin
                        objectName: "inspectorYTickCountSpin"
                        from: 0
                        to: 20
                        value: 0
                        ToolTip.text: qsTr("Y 軸の目盛り本数。0 で既定（4 本）。グリッド線表示時に効きます")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onValueModified: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetYTickCount = value
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                inspectorYTickCountSpin.value = (it && it.widgetYTickCount > 0)
                                    ? it.widgetYTickCount : 0
                            }
                        }
                    }

                    // ── 系列（Task 8B-D） ──
                    // 複数系列の編集。各行 = 変数 ComboBox + 線色（hex TextField + スウォッチ）
                    // + 凡例ラベル TextField + 削除ボタン。系列は selectedItem.widgetSeries を
                    // 配列丸ごと置換で編集する（updateSeries/addSeries/removeSeries）。系列 0 件
                    // でも単系列パス（線色 / value バインド）が後方互換で描く。
                    Rectangle { width: parent.width; height: 1; color: "#dddddd" }
                    Label { text: qsTr("系列"); font.bold: true; color: "#555555" }

                    // 系列行の Repeater。model は live Item の widgetSeries。選択切替・
                    // 配列置換のたびに widgetSeries が変わり Repeater が再構築される。
                    Repeater {
                        id: inspectorSeriesRepeater
                        objectName: "inspectorSeriesRepeater"
                        model: root.selectedIsTrend && root.editorCanvas.selectedItem
                            ? root.editorCanvas.selectedItem.widgetSeries : []
                        delegate: Column {
                            id: seriesRow
                            required property var modelData
                            required property int index
                            width: parent ? parent.width : 0
                            spacing: 4

                            Row {
                                width: parent.width
                                spacing: 4

                                // 変数 ComboBox（凡例ラベル空のときの既定表示にも使われる）。
                                ComboBox {
                                    objectName: "seriesVariable_" + seriesRow.index
                                    width: 100
                                    model: root.editorRoot.variableNameModel()
                                    currentIndex: {
                                        const v = seriesRow.modelData
                                            && seriesRow.modelData.variable !== undefined
                                            ? seriesRow.modelData.variable : ""
                                        return Math.max(0, model.indexOf(v))
                                    }
                                    // "(未選択)" は空文字へ畳む（variableNameModel の先頭）。
                                    onActivated: root.updateSeries(
                                        seriesRow.index, "variable",
                                        currentIndex === 0 ? "" : currentText)
                                }
                                Button {
                                    objectName: "seriesDelete_" + seriesRow.index
                                    text: qsTr("×")
                                    onClicked: root.removeSeries(seriesRow.index)
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 6

                                TextField {
                                    id: seriesColorField
                                    objectName: "seriesColor_" + seriesRow.index
                                    width: 100
                                    text: seriesRow.modelData
                                        && seriesRow.modelData.color !== undefined
                                        ? seriesRow.modelData.color : ""
                                    placeholderText: qsTr("(既定色)")
                                    validator: RegularExpressionValidator {
                                        regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                                    }
                                    onEditingFinished: if (acceptableInput)
                                        root.updateSeries(seriesRow.index, "color", text)
                                    onActiveFocusChanged:
                                        root.seriesFieldFocusCount += activeFocus ? 1 : -1
                                }
                                // 色スウォッチ（クリックで系列専用 ColorDialog）。
                                Rectangle {
                                    objectName: "seriesColorSwatch_" + seriesRow.index
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.colorSwatchSize
                                    height: root.colorSwatchSize
                                    radius: 4
                                    border.color: "#999999"
                                    border.width: 1
                                    color: (seriesColorField.text !== ""
                                            && seriesColorField.acceptableInput)
                                        ? seriesColorField.text : "#4cc9f0"
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.editorRoot.openSeriesColorDialog(
                                            seriesRow.index, seriesColorField.text)
                                    }
                                }
                            }

                            // 凡例ラベル（空 = 変数名へフォールバック）。
                            TextField {
                                objectName: "seriesLabel_" + seriesRow.index
                                width: parent.width
                                text: seriesRow.modelData
                                    && seriesRow.modelData.label !== undefined
                                    ? seriesRow.modelData.label : ""
                                placeholderText: qsTr("凡例ラベル（空=変数名）")
                                onEditingFinished:
                                    root.updateSeries(seriesRow.index, "label", text)
                                onActiveFocusChanged:
                                    root.seriesFieldFocusCount += activeFocus ? 1 : -1
                            }

                            Rectangle { width: parent.width; height: 1; color: "#eeeeee" }
                        }
                    }

                    Button {
                        objectName: "addSeriesButton"
                        text: qsTr("系列を追加")
                        onClicked: root.addSeries()
                    }
                }

                // ── Meter 詳細（Meter 選択時のみ）: 範囲 min/max / 弧色 / 針色 / 目盛り数 / 単位 ──
                // Task M-C: Meter 固有の編集 UI。型出し分けは visible のみ（objectName・
                // 編集ロジック・Schema 不変）。範囲 min/max は double で **負値も正当なので
                // presence チェック方式**（Trend の Y 軸 min/max・NumericField の min/max を手本）。
                // 弧色 / 針色は色スウォッチ + ColorDialog（Task 46 の色入力を手本）。目盛り数は
                // int（SpinBox）、単位は素の TextField。すべて 2 本立て（onValueModified/
                // onTextEdited で live Item へ書き戻し、Connections.onSelectedItemChanged で表示同期）。
                InspectorSection {
                    objectName: "inspectorMeterSection"
                    title: qsTr("Meter 詳細")
                    visible: root.selectedIsMeter

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
                            if (root.editorCanvas.selectedItem && acceptableInput) {
                                var t = text.trim()
                                var nv = Number(t)
                                if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                                    root.editorCanvas.selectedItem.widgetHasMeterMin = false
                                } else {
                                    root.editorCanvas.selectedItem.widgetMeterMin = nv
                                    root.editorCanvas.selectedItem.widgetHasMeterMin = true
                                }
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorMeterMinField.text =
                                    (root.editorCanvas.selectedItem && root.editorCanvas.selectedItem.widgetHasMeterMin)
                                        ? String(root.editorCanvas.selectedItem.widgetMeterMin) : ""
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
                            if (root.editorCanvas.selectedItem && acceptableInput) {
                                var t = text.trim()
                                var nv = Number(t)
                                if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                                    root.editorCanvas.selectedItem.widgetHasMeterMax = false
                                } else {
                                    root.editorCanvas.selectedItem.widgetMeterMax = nv
                                    root.editorCanvas.selectedItem.widgetHasMeterMax = true
                                }
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorMeterMaxField.text =
                                    (root.editorCanvas.selectedItem && root.editorCanvas.selectedItem.widgetHasMeterMax)
                                        ? String(root.editorCanvas.selectedItem.widgetMeterMax) : ""
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
                            width: parent.width - root.colorSwatchReserve
                            placeholderText: qsTr("#4cc9f0")
                            validator: RegularExpressionValidator {
                                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                            }
                            onTextEdited: {
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.widgetArcColor = text
                                }
                            }
                            Connections {
                                target: root.editorCanvas
                                function onSelectedItemChanged() {
                                    inspectorArcColorField.text = root.editorCanvas.selectedItem
                                        ? root.editorCanvas.selectedItem.widgetArcColor : ""
                                }
                            }
                        }
                        ColorSwatch {
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
                            width: parent.width - root.colorSwatchReserve
                            placeholderText: qsTr("#ff595e")
                            validator: RegularExpressionValidator {
                                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                            }
                            onTextEdited: {
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.widgetNeedleColor = text
                                }
                            }
                            Connections {
                                target: root.editorCanvas
                                function onSelectedItemChanged() {
                                    inspectorNeedleColorField.text = root.editorCanvas.selectedItem
                                        ? root.editorCanvas.selectedItem.widgetNeedleColor : ""
                                }
                            }
                        }
                        ColorSwatch {
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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetTickCount = value
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetUnit = text
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorUnitField.text = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetUnit : ""
                            }
                        }
                    }
                }

                // ── シンプルボタン詳細（SimpleButton 選択時のみ）: 形状 / テーマ / 差し色 / 長押し時間 ──
                // Task W-E: SimpleButton 固有の編集 UI。型出し分けは visible のみ（objectName・
                // 編集ロジック・Schema 不変）。形状 / テーマは hAlign と同じ「表示ラベル model +
                // parallel な values 配列」の ComboBox（index 0 = 未指定 = 空文字 = HmiSimpleButton
                // の resolved* が既定へ解決）。差し色は色スウォッチ + ColorDialog（弧色と同型）、
                // 長押し時間は SpinBox（0 = 既定 800ms。tickCount と同じ 0 センチネル）。
                InspectorSection {
                    objectName: "inspectorSimpleButtonSection"
                    title: qsTr("シンプルボタン詳細")
                    visible: root.selectedIsSimpleButton

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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetShape = values[currentIndex]
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetTheme = values[currentIndex]
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
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
                            width: parent.width - root.colorSwatchReserve
                            placeholderText: qsTr("(既定: テーマの緑)")
                            validator: RegularExpressionValidator {
                                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                            }
                            ToolTip.text: qsTr("ランプ・進捗・ON 表示に使うアクセント色。空欄でテーマ既定の緑")
                            ToolTip.visible: hovered
                            ToolTip.delay: 600
                            onTextEdited: {
                                if (root.editorCanvas.selectedItem && acceptableInput) {
                                    root.editorCanvas.selectedItem.widgetAccentColor = text
                                }
                            }
                            Connections {
                                target: root.editorCanvas
                                function onSelectedItemChanged() {
                                    inspectorAccentColorField.text = root.editorCanvas.selectedItem
                                        ? root.editorCanvas.selectedItem.widgetAccentColor : ""
                                }
                            }
                        }
                        ColorSwatch {
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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetHoldMs = value
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                const it = root.editorCanvas.selectedItem
                                // 0/未指定はそのまま 0（＝既定 800ms）を表示する。
                                inspectorHoldMsSpin.value = (it && it.widgetHoldMs > 0)
                                    ? it.widgetHoldMs : 0
                            }
                        }
                    }
                }

                // ── 状態 : 有効 / チェック可能 / チェック状態 ──
                // Task 48 / 51: Label（表示専用）はセクションごと隠す。**NumericField は
                // 「有効」だけ出す**（トグル / 初期オンは Button 専用）。NumericField も
                // `widgetEnabled` を内部 TextField.enabled に流すため、`enabled:false` を含む
                // JSON を開いたとき Editor で有効に戻せるよう「有効」チェックを残す
                // （Codex PR #105 P2）。トグル / 初期オンは `selectedSupportsClickAction`
                // ＝ Button のみで出し分ける（objectName・中身は不変、visible のみ）。
                InspectorSection {
                    title: qsTr("状態")
                    visible: !root.selectedIsLabel

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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.beginEdit()
                                root.editorCanvas.selectedItem.widgetEnabled = checked
                                root.editorCanvas.commitEdit()
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                // enabled は既定 true。未選択時も true 表示にする。
                                inspectorEnabledCheck.checked = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetEnabled : true
                            }
                        }
                    }

                    CheckBox {
                        id: inspectorCheckableCheck
                        objectName: "inspectorCheckableCheck"
                        text: qsTr("トグルボタンにする")
                        // Task 51: トグル / 初期オンは Button 専用（NumericField は「有効」のみ）。
                        visible: root.selectedSupportsClickAction
                        ToolTip.text: qsTr("ON にすると、クリックのたびに押下状態（オン / オフ）が切り替わるトグルボタンになります")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onToggled: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.beginEdit()
                                root.editorCanvas.selectedItem.widgetCheckable = checked
                                root.editorCanvas.commitEdit()
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorCheckableCheck.checked = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetCheckable : false
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
                        visible: root.selectedSupportsClickAction
                                 || root.selectedIsSimpleButton
                        // PR #110: checked の ON 外観は checkable 非依存になった（PR #109 修正）。
                        // よって checked 編集も checkable でゲートしない（checkable:false の
                        // 状態表示〔ランプ/インジケータ〕用 JSON でも直接 ON/OFF を編集できる）。
                        ToolTip.text: qsTr("ボタンを押下状態（オン）の外観にします。変数にバインドすればランプ／インジケータの状態表示にも使えます")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onToggled: {
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.beginEdit()
                                root.editorCanvas.selectedItem.widgetChecked = checked
                                root.editorCanvas.commitEdit()
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorCheckedCheck.checked = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetChecked : false
                            }
                        }
                    }
                }

                // ── 動作 : クリック時アクション / バインディング ──
                InspectorSection {
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
                        visible: root.selectedSupportsClickAction
                    }

                    Label { text: qsTr("操作"); visible: root.selectedSupportsClickAction }
                    ComboBox {
                        id: inspectorActionOpCombo
                        objectName: "inspectorActionOpCombo"
                        width: parent.width
                        visible: root.selectedSupportsClickAction
                        model: ["(なし)", "setVariable", "toggleVariable"]
                        // Task 45: クリック時の動作が分かりにくいため補足を付ける。
                        ToolTip.text: qsTr("クリック時の動作。setVariable=値を代入 / toggleVariable=オン↔オフを反転")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onActivated: root.applyActionFromInspector()
                    }
                    Label { text: qsTr("対象変数"); visible: root.selectedSupportsClickAction }
                    ComboBox {
                        id: inspectorActionTargetCombo
                        objectName: "inspectorActionTargetCombo"
                        width: parent.width
                        visible: root.selectedSupportsClickAction
                        model: root.editorRoot.variableNameModel()
                        onActivated: root.applyActionFromInspector()
                    }
                    // 値は setVariable のときだけ意味を持つ（toggleVariable では無視）。
                    // Task 48 / 51: Label / NumericField 選択時はアクション部ごと隠す
                    // （selectedSupportsClickAction と AND）。
                    Label {
                        text: qsTr("値")
                        visible: root.selectedSupportsClickAction
                               && inspectorActionOpCombo.currentText === "setVariable"
                    }
                    TextField {
                        id: inspectorActionValueField
                        objectName: "inspectorActionValueField"
                        width: parent.width
                        visible: root.selectedSupportsClickAction
                               && inspectorActionOpCombo.currentText === "setVariable"
                        placeholderText: qsTr("例: true / 10 / hello")
                        onEditingFinished: root.applyActionFromInspector()
                    }

                    // Task 40: データバインディング（1 件）。property を変数に追従させる。
                    // Task 48 / 51: 区切り線はアクション部とバインディング部の境界なので、
                    // アクション部が隠れる Label / NumericField 選択時は一緒に隠す。
                    Rectangle {
                        width: parent.width; height: 1; color: "#dddddd"
                        visible: root.selectedSupportsClickAction
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
                        onActivated: root.applyBindingFromInspector()
                    }
                    Label { text: qsTr("追従変数") }
                    ComboBox {
                        id: inspectorBindingVarCombo
                        objectName: "inspectorBindingVarCombo"
                        width: parent.width
                        model: root.editorRoot.variableNameModel()
                        onActivated: root.applyBindingFromInspector()
                    }

                    // Task 40: 選択切替時にアクション / バインディング編集 UI を同期する。
                    Connections {
                        target: root.editorCanvas
                        function onSelectedItemChanged() {
                            root.syncActionToInspector()
                            root.syncBindingToInspector()
                        }
                    }
                }

                // ── 詳細（既定で閉）: ID / 外部タグ ──
                // Task 45: 技術的・通常編集しない項目（読み取り専用の ID、機能未配線の
                // 外部タグ）をここへまとめ、既定で折りたたんで通常の編集を邪魔しない。
                InspectorSection {
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
                        visible: root.selectedIsNumericField
                    }
                    TextField {
                        id: inspectorMinValueField
                        objectName: "inspectorMinValueField"
                        width: parent.width
                        visible: root.selectedIsNumericField
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
                            if (root.editorCanvas.selectedItem && acceptableInput) {
                                // 空 / 符号のみ / 小数点のみは「未指定」（has=false）扱い。
                                var t = text.trim()
                                var n = Number(t)
                                if (t === "" || t === "-" || t === "." || isNaN(n)) {
                                    root.editorCanvas.selectedItem.widgetHasMin = false
                                } else {
                                    root.editorCanvas.selectedItem.widgetMinValue = n
                                    root.editorCanvas.selectedItem.widgetHasMin = true
                                }
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorMinValueField.text =
                                    (root.editorCanvas.selectedItem && root.editorCanvas.selectedItem.widgetHasMin)
                                        ? String(root.editorCanvas.selectedItem.widgetMinValue) : ""
                            }
                        }
                    }

                    Label {
                        text: qsTr("範囲 最大値")
                        visible: root.selectedIsNumericField
                    }
                    TextField {
                        id: inspectorMaxValueField
                        objectName: "inspectorMaxValueField"
                        width: parent.width
                        visible: root.selectedIsNumericField
                        placeholderText: qsTr("(未指定)")
                        onActiveFocusChanged: if (activeFocus) selectAll()
                        validator: RegularExpressionValidator {
                            regularExpression: /^(-?\d*\.?\d*)$/
                        }
                        ToolTip.text: qsTr("入力可能な最大値。空欄で未指定（上限なし）。確定時に範囲外は境界へ丸めます")
                        ToolTip.visible: hovered
                        ToolTip.delay: 600
                        onTextEdited: {
                            if (root.editorCanvas.selectedItem && acceptableInput) {
                                var t = text.trim()
                                var n = Number(t)
                                if (t === "" || t === "-" || t === "." || isNaN(n)) {
                                    root.editorCanvas.selectedItem.widgetHasMax = false
                                } else {
                                    root.editorCanvas.selectedItem.widgetMaxValue = n
                                    root.editorCanvas.selectedItem.widgetHasMax = true
                                }
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorMaxValueField.text =
                                    (root.editorCanvas.selectedItem && root.editorCanvas.selectedItem.widgetHasMax)
                                        ? String(root.editorCanvas.selectedItem.widgetMaxValue) : ""
                            }
                        }
                    }

                    Label {
                        objectName: "inspectorIdLabel"
                        color: "#555555"
                        text: qsTr("ID: ") + (root.editorCanvas.selectedItem
                            ? root.editorCanvas.selectedItem.widgetId : "")
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
                            if (root.editorCanvas.selectedItem) {
                                root.editorCanvas.selectedItem.widgetTag = text
                            }
                        }
                        Connections {
                            target: root.editorCanvas
                            function onSelectedItemChanged() {
                                inspectorTagField.text = root.editorCanvas.selectedItem
                                    ? root.editorCanvas.selectedItem.widgetTag : ""
                            }
                        }
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
                        if (root.editorCanvas.selectedWidgetId) {
                            root.editorCanvas.deleteWidget(root.editorCanvas.selectedWidgetId)
                        }
                    }
                }
            }
        }
    }
}
