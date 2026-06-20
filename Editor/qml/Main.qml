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

    // Task 8B-D: Trend 系列パネルの動的 TextField（色 / 凡例ラベル、Repeater 由来で
    // id 固定できない）の編集中フラグ。変数定義（widget undo に載せない）と違い、系列は
    // widget 内データなので widget undo 境界（widgetEditFieldFocused）にも含める。
    // Delete ショートカット抑止（inspectorFieldFocused）にも入れる。
    property int seriesFieldFocusCount: 0

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
        // Task 40（Codex PR #80 [P2]）：削除で variableNameModel() が縮むと、
        // アクション/バインディング ComboBox の currentIndex が古い数値のままズレる
        // （selectedItem は変わらないので onSelectedItemChanged の再同期が走らない）。
        // 選択中 Widget の現在値から名前で index を取り直す（未選択時は index 0 に戻る）。
        syncActionToInspector()
        syncBindingToInspector()
    }
    // Task 40（Codex PR #80 [P2]）：変数名の重複を保存前に防ぐ。VariableStore は名前を
    // キーにした map で、アクション/バインディングも名前で解決するため、同名が複数あると
    // 後勝ちで参照先を区別できない。index 行を除く他行に同名があれば true。
    function isVariableNameTaken(index, name) {
        for (let i = 0; i < projectVariables.length; ++i) {
            if (i !== index && projectVariables[i].name === name) {
                return true
            }
        }
        return false
    }
    // Phase 7 / MB-1 + Phase 9 / OP-1: 変数ソース（接続写像）の編集ヘルパー。実通信はしない＝
    // 入力値を variable.source（{connection, proto, host/port/unitId, endpoint, reg/address/poll,
    // nodeId}）に保存するだけ。接続詳細はインラインで持ち、保存（ProjectIo.save）時に
    // connections[] へ集約される。proto で Modbus（host/port/unitId/reg/address）と
    // OPC-UA（endpoint/nodeId）を出し分ける。MB-1 は最小：接続 id は "plc1" 固定（複数 PLC は別タスク）。
    function setVariableSourceEnabled(index, enabled) {
        if (index < 0 || index >= projectVariables.length) {
            return
        }
        const next = projectVariables.slice()
        const v = Object.assign({}, next[index])
        if (enabled) {
            // 既定の source（modbusTcp / holding / 0 番地 / 1000ms / plc1 / 502 / unitId 1）。
            // OPC-UA 用 endpoint / nodeId は proto を opcua に切り替えたとき使う。
            v.source = {
                connection: "plc1", proto: "modbusTcp",
                host: "", port: 502, unitId: 1,
                reg: "holding", address: 0, poll: 1000,
                endpoint: "", nodeId: ""
            }
        } else {
            delete v.source
        }
        next[index] = v
        projectVariables = next
    }
    function updateVariableSource(index, key, value) {
        if (index < 0 || index >= projectVariables.length) {
            return
        }
        const v = projectVariables[index]
        if (!v.source) {
            return
        }
        const next = projectVariables.slice()
        const nv = Object.assign({}, next[index])
        const ns = Object.assign({}, nv.source)
        ns[key] = value
        nv.source = ns
        next[index] = nv
        projectVariables = next
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

    // Task 8B-D: Trend 系列エディタ。系列は選択中 live Item の widgetSeries
    //（[{variable, color, label}] 配列）を真実とし、**配列を丸ごと置換**して編集する
    // （アクション / バインディングと同じ流儀＝in-place 変更しないので参照共有でも安全）。
    // 系列の追加 / 削除は構造変更なので pushUndo() で 1 件積む（CheckBox と同じ離散操作。
    // 連続編集〔色 hex 手入力 / ラベル入力〕は各 TextField のフォーカス境界が
    // beginEdit/commitEdit を拾うため明示しない）。
    function currentSeries() {
        const it = canvas.selectedItem
        if (!it || it.widgetSeries === undefined || it.widgetSeries === null) {
            return []
        }
        return it.widgetSeries
    }
    function addSeries() {
        if (!canvas.selectedItem) {
            return
        }
        canvas.pushUndo()
        const next = currentSeries().slice()
        next.push({ variable: "", color: "", label: "" })
        canvas.selectedItem.widgetSeries = next
    }
    function removeSeries(index) {
        if (!canvas.selectedItem) {
            return
        }
        const next = currentSeries().slice()
        if (index < 0 || index >= next.length) {
            return
        }
        canvas.pushUndo()
        next.splice(index, 1)
        canvas.selectedItem.widgetSeries = next
    }
    function updateSeries(index, key, value) {
        if (!canvas.selectedItem) {
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
        canvas.selectedItem.widgetSeries = next
    }

    // Task 8B-D: 系列の線色を選ぶ専用 ColorDialog 起動。背景色等の openColorDialog は
    // 「選択中 Item の単一プロパティ名」へ書き戻す方式だが、系列色は配列内 index への
    // 書き戻しが要るため別ダイアログ（seriesColorDialog）を使う。
    function openSeriesColorDialog(index, currentHex) {
        if (!canvas.selectedItem) {
            return
        }
        seriesColorDialog.targetIndex = index
        seriesColorDialog.selectedColor =
            (currentHex && /^#[0-9A-Fa-f]{6}$/.test(currentHex)) ? currentHex : "#4cc9f0"
        seriesColorDialog.open()
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

    // 座標・サイズの数値欄を ↑/↓ キーで増減する（Shift で ±10）。SpinBox 化された
    // 文字サイズ・ボーダー・角丸・不透明度は標準の矢印キー増減が効くのに対し、
    // X/Y/幅/高さ は TextField + IntValidator（Task 27 の SpinBox 不具合回避）で
    // キー増減が無く「キーボードで微調整できない」差があったため補う。現在値を
    // validator の範囲（bottom/top）へ clamp し、表示と選択中 live Item の両方を
    // 更新する（onTextEdited と同じ書き戻し経路）。フォーカス中の編集なので undo は
    // focus 由来の beginEdit/commitEdit が 1 操作として拾う。
    function nudgeGeometry(field, prop, step) {
        if (!canvas.selectedItem) {
            return
        }
        const v = field.validator
        let cur = parseInt(field.text)
        if (isNaN(cur)) {
            cur = v.bottom
        }
        const next = Math.max(v.bottom, Math.min(v.top, cur + step))
        field.text = String(next)
        canvas.selectedItem[prop] = next
    }

    // Task 46: 色スウォッチの一辺と、色 TextField がスウォッチ用に空ける幅
    //（スウォッチ + Row spacing 6）。3 つの色フィールドで共有する
    //（CodeRabbit PR #99 nitpick: マジックナンバー 34 の重複を定数化）。
    readonly property int colorSwatchSize: 28
    readonly property int colorSwatchReserve: colorSwatchSize + 6

    // Task 46: QML の color 値を Schema の "#RRGGBB" 形式へ変換する。
    // ColorDialog の selectedColor（color 型）を hex TextField / live Item に
    // 書き戻すときに使う（alpha は使わない。ColorDialog の alpha オプションも無効のまま）。
    function colorToHex(c) {
        function h(v) { return ("0" + Math.round(v * 255).toString(16)).slice(-2) }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }

    // Task 46: 色スウォッチクリックで共有 ColorDialog を開く。field = 書き戻し先の
    // hex TextField、targetProperty = 選択中 live Item のプロパティ名
    //（"widgetBackgroundColor" 等）、fallback = 未指定時の既定色（HmiButton の
    // resolved* と同じ値。ダイアログの初期色として使う）。
    function openColorDialog(field, targetProperty, fallback) {
        if (!canvas.selectedItem) {
            return
        }
        inspectorColorDialog.targetField = field
        inspectorColorDialog.targetProperty = targetProperty
        inspectorColorDialog.selectedColor =
            (field.text !== "" && field.acceptableInput) ? field.text : fallback
        inspectorColorDialog.open()
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
        || rootWindow.seriesFieldFocusCount > 0
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

    // Task 48: 選択中 Widget が Label 型か。型に応じてインスペクタの無関係セクション /
    // 項目を隠す（Label は状態・クリックアクション・ボーダー/角丸を非表示。背景色・
    // 不透明度・バインディング・基本・文字・詳細は表示）。canvas.selectedItem は単一選択時
    // のみ非 null なので、複数 / 未選択では false（単一編集フォーム自体が出ない）。
    // **objectName・編集ロジック・Schema は不変で、表示（visible）切替のみ**（plan Task 48）。
    readonly property bool selectedIsLabel:
        canvas.selectedItem !== null && canvas.selectedItem.widgetType === "Label"

    // Task 51: 選択中 Widget が NumericField 型か。NumericField は入力 Widget で、状態
    // （有効/トグル/初期オン）とクリックアクションを持たない（書きは入力確定＝binding で行う）。
    // 背景・枠・文字・配置・不透明度・バインディングは持つ（背景・枠は Label と違い全部表示）。
    readonly property bool selectedIsNumericField:
        canvas.selectedItem !== null && canvas.selectedItem.widgetType === "NumericField"

    // Task T-C: 選択中 Widget が Trend 型か。Trend は表示専用（ライブ折れ線）で、状態
    //（トグル/初期オン）・クリックアクション・文字（フォント）を持たない。背景・枠（グラフ枠）・
    // 不透明度・有効・バインディング（サンプル対象変数 = value 読み）は持つ。Trend 詳細
    //（点数 / Y 軸 / 線色 / 周期）は selectedIsTrend で出し分ける。
    readonly property bool selectedIsTrend:
        canvas.selectedItem !== null && canvas.selectedItem.widgetType === "Trend"

    // Task 51 / T-C: クリックアクション（onClick）を扱える Widget か（= Button のみ）。Label /
    // NumericField / Trend はクリックアクションを持たないため、`!selectedIsLabel && …`
    // を毎回連結せず派生プロパティへまとめる（今後の入力 / 表示 Widget 追加で破綻しにくい。
    // 新たに「クリックアクション非対応」種別が増えたらここだけ直せばよい）。Trend は
    // Label の既存抑制（selectedIsLabel）と独立に AND するだけで競合しない（派生 1 本に集約）。
    readonly property bool selectedSupportsClickAction:
        !selectedIsLabel && !selectedIsNumericField && !selectedIsTrend

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

        width: rootWindow.colorSwatchSize
        height: rootWindow.colorSwatchSize
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
            onClicked: rootWindow.openColorDialog(
                swatch.field, swatch.targetProperty, swatch.fallback)
        }
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

            // Task 18 / 48: Widget 追加。E2E からは objectName で参照する。
            // Task 48: 横展開で種別が増えたため「ボタン追加」と明示し、隣に「ラベル追加」を足す。
            // objectName（addWidgetButton）と挙動（Button を追加）は据え置き＝既存 E2E 互換。
            Button {
                objectName: "addWidgetButton"
                text: qsTr("ボタン追加")
                onClicked: canvas.addWidget("Button")
            }

            // Task 48: ラベル（表示専用 Widget）追加。同じ addWidget を type 違いで呼ぶ。
            Button {
                objectName: "addLabelButton"
                text: qsTr("ラベル追加")
                onClicked: canvas.addWidget("Label")
            }

            // Task 51: 数値入力（NumericField）追加。Phase 6 の最初の入力 Widget。
            // 同じ addWidget を type 違いで呼ぶ（ホワイトリストに "NumericField" を追加済み）。
            Button {
                objectName: "addNumericButton"
                text: qsTr("数値入力追加")
                onClicked: canvas.addWidget("NumericField")
            }

            // Task T-C: トレンドグラフ（Trend）追加。Phase 8 の最初の表示 Widget（ライブ
            // 折れ線）。同じ addWidget を type 違いで呼ぶ（ホワイトリストに "Trend" を追加済み）。
            Button {
                objectName: "addTrendButton"
                text: qsTr("トレンド追加")
                onClicked: canvas.addWidget("Trend")
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

        // Task 26: 右側インスペクタ。選択中 Widget の各プロパティを編集する。
        // 編集対象は canvas.selectedWidgetId が指す live な EditableWidget
        // （canvas.selectedItem で解決）。Simulator / Runtime は読み取り専用の
        // ため、この編集 UI は Editor のみが持つ（Phase 4 ルール）。
        // Task 44: Phase 4 で平坦に積み上がった項目を InspectorSection で
        // グループ化し、関連プロパティを論理順に集約した（基本 / 文字 / 背景・枠 /
        // 状態 / 動作 / 詳細）。objectName・編集ロジック・Schema は不変で表示のみ整理。
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

                    // Task 40 / 44: Project レベルの変数定義パネル（選択に依らず常時表示）。
                    // 変数の追加 / 削除 / 名前・型・初期値の編集を行い、rootWindow.projectVariables を
                    // 駆動する。アクション target / バインディング variable の ComboBox 選択肢になる。
                    // Task 44: 折りたたみ可能なセクションに収める。
                    InspectorSection {
                        objectName: "variablePanel"
                        title: qsTr("変数定義")

                        Repeater {
                            model: rootWindow.projectVariables
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
                                                    && !rootWindow.isVariableNameTaken(varRow.index, text)) {
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
                                        model: ["bool", "int", "real", "string"]
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

                                // Phase 7 / MB-1: PLC 接続写像（source）の有効化トグル。
                                // チェックで variable.source を付ける（内部変数 ↔ PLC 変数）。
                                CheckBox {
                                    objectName: "variableSourceEnabled_" + varRow.index
                                    text: qsTr("PLC レジスタに割当")
                                    checked: varRow.rowSource !== null
                                    onToggled: rootWindow.setVariableSourceEnabled(varRow.index, checked)
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
                                        onActivated: rootWindow.updateVariableSource(varRow.index, "proto", currentText)
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
                                        onEditingFinished: rootWindow.updateVariableSource(varRow.index, "host", text)
                                        onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
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
                                        onEditingFinished: if (acceptableInput) rootWindow.updateVariableSource(varRow.index, "port", parseInt(text, 10))
                                        onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
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
                                        onEditingFinished: if (acceptableInput) rootWindow.updateVariableSource(varRow.index, "unitId", parseInt(text, 10))
                                        onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
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
                                        onActivated: rootWindow.updateVariableSource(varRow.index, "reg", currentText)
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
                                        onEditingFinished: if (acceptableInput) rootWindow.updateVariableSource(varRow.index, "address", parseInt(text, 10))
                                        onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
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
                                        onEditingFinished: rootWindow.updateVariableSource(varRow.index, "endpoint", text)
                                        onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
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
                                        onEditingFinished: rootWindow.updateVariableSource(varRow.index, "nodeId", text)
                                        onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
                                    }

                                    // ポーリング周期は両プロトコル共通（OPC-UA は購読不可時のフォールバック）。
                                    Label { text: qsTr("ポーリング(ms)") }
                                    TextField {
                                        objectName: "variableSourcePoll_" + varRow.index
                                        width: 80
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1; top: 600000 }
                                        text: varRow.rowSource ? String(varRow.rowSource.poll !== undefined ? varRow.rowSource.poll : 1000) : ""
                                        placeholderText: qsTr("1000")
                                        onEditingFinished: if (acceptableInput) rootWindow.updateVariableSource(varRow.index, "poll", parseInt(text, 10))
                                        onActiveFocusChanged: rootWindow.variableFieldFocusCount += activeFocus ? 1 : -1
                                    }
                                }

                                Rectangle {
                                    visible: varRow.index < rootWindow.projectVariables.length - 1
                                    width: parent.width
                                    height: 1
                                    color: "#eeeeee"
                                }
                            }
                        }

                        Button {
                            objectName: "addVariableButton"
                            text: qsTr("変数を追加")
                            onClicked: rootWindow.addVariable()
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: "#dddddd" }

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

                    // 選択中の編集フォーム（Task 44: InspectorSection でグループ化）。
                    Column {
                        objectName: "inspectorForm"
                        visible: canvas.selectedItem !== null
                        width: parent.width
                        spacing: 8

                        // ── 基本 : Text / 座標・サイズ ──
                        InspectorSection {
                            title: qsTr("基本")

                            // Task T-C: Trend は文字を持たないため Text 入力（ラベル + 欄）を隠す。
                            Label { text: qsTr("Text"); visible: !rootWindow.selectedIsTrend }
                            TextField {
                                id: inspectorTextField
                                objectName: "inspectorTextField"
                                visible: !rootWindow.selectedIsTrend
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
                                        if (canvas.selectedItem && acceptableInput) {
                                            canvas.selectedItem.x = parseInt(text)
                                        }
                                    }
                                    Keys.onUpPressed: (event) => {
                                        rootWindow.nudgeGeometry(fieldX, "x", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                                        event.accepted = true
                                    }
                                    Keys.onDownPressed: (event) => {
                                        rootWindow.nudgeGeometry(fieldX, "x", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
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
                                        if (canvas.selectedItem && acceptableInput) {
                                            canvas.selectedItem.y = parseInt(text)
                                        }
                                    }
                                    Keys.onUpPressed: (event) => {
                                        rootWindow.nudgeGeometry(fieldY, "y", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                                        event.accepted = true
                                    }
                                    Keys.onDownPressed: (event) => {
                                        rootWindow.nudgeGeometry(fieldY, "y", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
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
                                        if (canvas.selectedItem && acceptableInput) {
                                            canvas.selectedItem.width = parseInt(text)
                                        }
                                    }
                                    Keys.onUpPressed: (event) => {
                                        rootWindow.nudgeGeometry(fieldW, "width", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                                        event.accepted = true
                                    }
                                    Keys.onDownPressed: (event) => {
                                        rootWindow.nudgeGeometry(fieldW, "width", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
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
                                        if (canvas.selectedItem && acceptableInput) {
                                            canvas.selectedItem.height = parseInt(text)
                                        }
                                    }
                                    Keys.onUpPressed: (event) => {
                                        rootWindow.nudgeGeometry(fieldH, "height", (event.modifiers & Qt.ShiftModifier) ? 10 : 1)
                                        event.accepted = true
                                    }
                                    Keys.onDownPressed: (event) => {
                                        rootWindow.nudgeGeometry(fieldH, "height", (event.modifiers & Qt.ShiftModifier) ? -10 : -1)
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
                        }

                        // ── 文字 : フォント / 文字サイズ / 太字 / 斜体 / 文字色 / 配置 ──
                        // Task T-C: Trend は文字を持たない（表示専用の折れ線グラフ）ため
                        // 文字セクションを丸ごと隠す（型出し分けは visible のみ）。
                        InspectorSection {
                            title: qsTr("文字")
                            visible: !rootWindow.selectedIsTrend

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
                                    width: parent.width - rootWindow.colorSwatchReserve
                                    placeholderText: qsTr("white")
                                    // Codex PR #58 P2: 空 または 完全な #RRGGBB の時だけ反映する
                                    //（途中入力・不正値を live Item に書き戻さない）。
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
                                ColorSwatch {
                                    objectName: "inspectorTextColorSwatch"
                                    anchors.verticalCenter: parent.verticalCenter
                                    field: inspectorTextColorField
                                    targetProperty: "widgetTextColor"
                                    // 未指定時の既定色は Widget 種別の resolved* と揃える
                                    //（HmiButton=white / HmiLabel=#1d3557 / HmiNumericField=#1d3557）。
                                    // Task 51: NumericField も Label と同じ濃文字（#1d3557）が既定。
                                    fallback: (canvas.selectedItem
                                               && (canvas.selectedItem.widgetType === "Label"
                                                   || canvas.selectedItem.widgetType === "NumericField"))
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
                        }

                        // ── 背景・枠 : 背景色 / ボーダー / 角丸 / 不透明度 ──
                        InspectorSection {
                            title: qsTr("背景・枠")

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
                                    width: parent.width - rootWindow.colorSwatchReserve
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
                                ColorSwatch {
                                    objectName: "inspectorBgColorSwatch"
                                    anchors.verticalCenter: parent.verticalCenter
                                    field: inspectorBgColorField
                                    targetProperty: "widgetBackgroundColor"
                                    // 未指定時の既定色は Widget 種別の resolved* と揃える
                                    //（HmiButton=#4cc9f0 / HmiLabel=transparent / HmiNumericField=#ffffff）。
                                    // Task 51: NumericField は入力欄らしい白背景（#ffffff）が既定。
                                    fallback: (canvas.selectedItem
                                               && canvas.selectedItem.widgetType === "Label")
                                        ? "transparent"
                                        : (canvas.selectedItem
                                           && canvas.selectedItem.widgetType === "NumericField")
                                            ? "#ffffff" : "#4cc9f0"
                                }
                            }

                            // Task 31: ボーダー＋角丸の編集。背景色 / 文字色 / 文字サイズ（Task 29）と
                            // 同型の 2 本立て（onTextEdited/onValueModified で live Item へ書き戻し、
                            // Connections.onSelectedItemChanged で表示同期）。数値は **0 が正当値**
                            //（borderWidth=0=ボーダーなし、radius=0=角丸なし）なので、SpinBox の
                            // from を 0 にし、未指定（-1）は HmiButton の既定（太さ 1 / 角丸 4）を表示する。
                            Label {
                                text: qsTr("ボーダー色 (#RRGGBB)")
                                visible: !rootWindow.selectedIsLabel
                            }
                            // Task 46: hex TextField + 色スウォッチ（プレビュー / クリックで
                            // ColorDialog）。手入力欄はそのまま残す（E2E / 既存導線を維持）。
                            // 幅補正は文字色の Row と同じ（leftPadding ぶん詰める）。
                            // Task 48: Label はフラット（ボーダー/角丸を持たない）ため、これら 3 項目
                            // （ボーダー色 / 太さ / 角丸）を Label 選択時は隠す（背景色・不透明度は残す）。
                            Row {
                                width: parent.width - parent.leftPadding
                                spacing: 6
                                visible: !rootWindow.selectedIsLabel

                                TextField {
                                    id: inspectorBorderColorField
                                    objectName: "inspectorBorderColorField"
                                    width: parent.width - rootWindow.colorSwatchReserve
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
                                ColorSwatch {
                                    objectName: "inspectorBorderColorSwatch"
                                    anchors.verticalCenter: parent.verticalCenter
                                    field: inspectorBorderColorField
                                    targetProperty: "widgetBorderColor"
                                    // HmiButton.resolvedBorderColor の既定と揃える。
                                    fallback: "#1d3557"
                                }
                            }

                            // ボーダー太さ / 角丸は SpinBox（from: 0 で 0 を選べる）。editable は付けない
                            //（Task 27: editable な SpinBox は value プログラム設定で表示が更新されない不具合）。
                            Label {
                                text: qsTr("ボーダー太さ")
                                visible: !rootWindow.selectedIsLabel
                            }
                            SpinBox {
                                id: inspectorBorderWidthSpin
                                objectName: "inspectorBorderWidthSpin"
                                visible: !rootWindow.selectedIsLabel
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

                            Label {
                                text: qsTr("角丸")
                                visible: !rootWindow.selectedIsLabel
                            }
                            SpinBox {
                                id: inspectorRadiusSpin
                                objectName: "inspectorRadiusSpin"
                                visible: !rootWindow.selectedIsLabel
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
                            visible: rootWindow.selectedIsTrend

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
                                    if (canvas.selectedItem) {
                                        canvas.selectedItem.widgetPointCount = value
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        const it = canvas.selectedItem
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
                                    if (canvas.selectedItem && acceptableInput) {
                                        var t = text.trim()
                                        var nv = Number(t)
                                        if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                                            canvas.selectedItem.widgetHasYMin = false
                                        } else {
                                            canvas.selectedItem.widgetYMin = nv
                                            canvas.selectedItem.widgetHasYMin = true
                                        }
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        inspectorYMinField.text =
                                            (canvas.selectedItem && canvas.selectedItem.widgetHasYMin)
                                                ? String(canvas.selectedItem.widgetYMin) : ""
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
                                    if (canvas.selectedItem && acceptableInput) {
                                        var t = text.trim()
                                        var nv = Number(t)
                                        if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                                            canvas.selectedItem.widgetHasYMax = false
                                        } else {
                                            canvas.selectedItem.widgetYMax = nv
                                            canvas.selectedItem.widgetHasYMax = true
                                        }
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        inspectorYMaxField.text =
                                            (canvas.selectedItem && canvas.selectedItem.widgetHasYMax)
                                                ? String(canvas.selectedItem.widgetYMax) : ""
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
                                    width: parent.width - rootWindow.colorSwatchReserve
                                    placeholderText: qsTr("#4cc9f0")
                                    validator: RegularExpressionValidator {
                                        regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                                    }
                                    onTextEdited: {
                                        if (canvas.selectedItem && acceptableInput) {
                                            canvas.selectedItem.widgetLineColor = text
                                        }
                                    }
                                    Connections {
                                        target: canvas
                                        function onSelectedItemChanged() {
                                            inspectorLineColorField.text = canvas.selectedItem
                                                ? canvas.selectedItem.widgetLineColor : ""
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
                                    if (canvas.selectedItem) {
                                        canvas.selectedItem.widgetSampleMs = value
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        const it = canvas.selectedItem
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
                                    if (canvas.selectedItem) {
                                        canvas.beginEdit()
                                        canvas.selectedItem.widgetShowGrid = checked
                                        canvas.commitEdit()
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        inspectorShowGridCheck.checked = canvas.selectedItem
                                            ? canvas.selectedItem.widgetShowGrid : false
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
                                    if (canvas.selectedItem) {
                                        canvas.beginEdit()
                                        canvas.selectedItem.widgetShowLegend = checked
                                        canvas.commitEdit()
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        inspectorShowLegendCheck.checked = canvas.selectedItem
                                            ? canvas.selectedItem.widgetShowLegend : false
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
                                    if (canvas.selectedItem) {
                                        canvas.selectedItem.widgetYTickCount = value
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        const it = canvas.selectedItem
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
                                model: rootWindow.selectedIsTrend && canvas.selectedItem
                                    ? canvas.selectedItem.widgetSeries : []
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
                                            model: rootWindow.variableNameModel()
                                            currentIndex: {
                                                const v = seriesRow.modelData
                                                    && seriesRow.modelData.variable !== undefined
                                                    ? seriesRow.modelData.variable : ""
                                                return Math.max(0, model.indexOf(v))
                                            }
                                            // "(未選択)" は空文字へ畳む（variableNameModel の先頭）。
                                            onActivated: rootWindow.updateSeries(
                                                seriesRow.index, "variable",
                                                currentIndex === 0 ? "" : currentText)
                                        }
                                        Button {
                                            objectName: "seriesDelete_" + seriesRow.index
                                            text: qsTr("×")
                                            onClicked: rootWindow.removeSeries(seriesRow.index)
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
                                                rootWindow.updateSeries(seriesRow.index, "color", text)
                                            onActiveFocusChanged:
                                                rootWindow.seriesFieldFocusCount += activeFocus ? 1 : -1
                                        }
                                        // 色スウォッチ（クリックで系列専用 ColorDialog）。
                                        Rectangle {
                                            objectName: "seriesColorSwatch_" + seriesRow.index
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: rootWindow.colorSwatchSize
                                            height: rootWindow.colorSwatchSize
                                            radius: 4
                                            border.color: "#999999"
                                            border.width: 1
                                            color: (seriesColorField.text !== ""
                                                    && seriesColorField.acceptableInput)
                                                ? seriesColorField.text : "#4cc9f0"
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: rootWindow.openSeriesColorDialog(
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
                                            rootWindow.updateSeries(seriesRow.index, "label", text)
                                        onActiveFocusChanged:
                                            rootWindow.seriesFieldFocusCount += activeFocus ? 1 : -1
                                    }

                                    Rectangle { width: parent.width; height: 1; color: "#eeeeee" }
                                }
                            }

                            Button {
                                objectName: "addSeriesButton"
                                text: qsTr("系列を追加")
                                onClicked: rootWindow.addSeries()
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
                            visible: !rootWindow.selectedIsLabel

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
                                    if (canvas.selectedItem) {
                                        canvas.beginEdit()
                                        canvas.selectedItem.widgetEnabled = checked
                                        canvas.commitEdit()
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        // enabled は既定 true。未選択時も true 表示にする。
                                        inspectorEnabledCheck.checked = canvas.selectedItem
                                            ? canvas.selectedItem.widgetEnabled : true
                                    }
                                }
                            }

                            CheckBox {
                                id: inspectorCheckableCheck
                                objectName: "inspectorCheckableCheck"
                                text: qsTr("トグルボタンにする")
                                // Task 51: トグル / 初期オンは Button 専用（NumericField は「有効」のみ）。
                                visible: rootWindow.selectedSupportsClickAction
                                ToolTip.text: qsTr("ON にすると、クリックのたびに押下状態（オン / オフ）が切り替わるトグルボタンになります")
                                ToolTip.visible: hovered
                                ToolTip.delay: 600
                                onToggled: {
                                    if (canvas.selectedItem) {
                                        canvas.beginEdit()
                                        canvas.selectedItem.widgetCheckable = checked
                                        canvas.commitEdit()
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        inspectorCheckableCheck.checked = canvas.selectedItem
                                            ? canvas.selectedItem.widgetCheckable : false
                                    }
                                }
                            }

                            CheckBox {
                                id: inspectorCheckedCheck
                                objectName: "inspectorCheckedCheck"
                                text: qsTr("状態をオン")
                                // Task 51: トグル / 状態オンは Button 専用（NumericField は「有効」のみ）。
                                visible: rootWindow.selectedSupportsClickAction
                                // PR #110: checked の ON 外観は checkable 非依存になった（PR #109 修正）。
                                // よって checked 編集も checkable でゲートしない（checkable:false の
                                // 状態表示〔ランプ/インジケータ〕用 JSON でも直接 ON/OFF を編集できる）。
                                ToolTip.text: qsTr("ボタンを押下状態（オン）の外観にします。変数にバインドすればランプ／インジケータの状態表示にも使えます")
                                ToolTip.visible: hovered
                                ToolTip.delay: 600
                                onToggled: {
                                    if (canvas.selectedItem) {
                                        canvas.beginEdit()
                                        canvas.selectedItem.widgetChecked = checked
                                        canvas.commitEdit()
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        inspectorCheckedCheck.checked = canvas.selectedItem
                                            ? canvas.selectedItem.widgetChecked : false
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
                                visible: rootWindow.selectedSupportsClickAction
                            }

                            Label { text: qsTr("操作"); visible: rootWindow.selectedSupportsClickAction }
                            ComboBox {
                                id: inspectorActionOpCombo
                                objectName: "inspectorActionOpCombo"
                                width: parent.width
                                visible: rootWindow.selectedSupportsClickAction
                                model: ["(なし)", "setVariable", "toggleVariable"]
                                // Task 45: クリック時の動作が分かりにくいため補足を付ける。
                                ToolTip.text: qsTr("クリック時の動作。setVariable=値を代入 / toggleVariable=オン↔オフを反転")
                                ToolTip.visible: hovered
                                ToolTip.delay: 600
                                onActivated: rootWindow.applyActionFromInspector()
                            }
                            Label { text: qsTr("対象変数"); visible: rootWindow.selectedSupportsClickAction }
                            ComboBox {
                                id: inspectorActionTargetCombo
                                objectName: "inspectorActionTargetCombo"
                                width: parent.width
                                visible: rootWindow.selectedSupportsClickAction
                                model: rootWindow.variableNameModel()
                                onActivated: rootWindow.applyActionFromInspector()
                            }
                            // 値は setVariable のときだけ意味を持つ（toggleVariable では無視）。
                            // Task 48 / 51: Label / NumericField 選択時はアクション部ごと隠す
                            // （selectedSupportsClickAction と AND）。
                            Label {
                                text: qsTr("値")
                                visible: rootWindow.selectedSupportsClickAction
                                       && inspectorActionOpCombo.currentText === "setVariable"
                            }
                            TextField {
                                id: inspectorActionValueField
                                objectName: "inspectorActionValueField"
                                width: parent.width
                                visible: rootWindow.selectedSupportsClickAction
                                       && inspectorActionOpCombo.currentText === "setVariable"
                                placeholderText: qsTr("例: true / 10 / hello")
                                onEditingFinished: rootWindow.applyActionFromInspector()
                            }

                            // Task 40: データバインディング（1 件）。property を変数に追従させる。
                            // Task 48 / 51: 区切り線はアクション部とバインディング部の境界なので、
                            // アクション部が隠れる Label / NumericField 選択時は一緒に隠す。
                            Rectangle {
                                width: parent.width; height: 1; color: "#dddddd"
                                visible: rootWindow.selectedSupportsClickAction
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
                                visible: rootWindow.selectedIsNumericField
                            }
                            TextField {
                                id: inspectorMinValueField
                                objectName: "inspectorMinValueField"
                                width: parent.width
                                visible: rootWindow.selectedIsNumericField
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
                                    if (canvas.selectedItem && acceptableInput) {
                                        // 空 / 符号のみ / 小数点のみは「未指定」（has=false）扱い。
                                        var t = text.trim()
                                        var n = Number(t)
                                        if (t === "" || t === "-" || t === "." || isNaN(n)) {
                                            canvas.selectedItem.widgetHasMin = false
                                        } else {
                                            canvas.selectedItem.widgetMinValue = n
                                            canvas.selectedItem.widgetHasMin = true
                                        }
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        inspectorMinValueField.text =
                                            (canvas.selectedItem && canvas.selectedItem.widgetHasMin)
                                                ? String(canvas.selectedItem.widgetMinValue) : ""
                                    }
                                }
                            }

                            Label {
                                text: qsTr("範囲 最大値")
                                visible: rootWindow.selectedIsNumericField
                            }
                            TextField {
                                id: inspectorMaxValueField
                                objectName: "inspectorMaxValueField"
                                width: parent.width
                                visible: rootWindow.selectedIsNumericField
                                placeholderText: qsTr("(未指定)")
                                onActiveFocusChanged: if (activeFocus) selectAll()
                                validator: RegularExpressionValidator {
                                    regularExpression: /^(-?\d*\.?\d*)$/
                                }
                                ToolTip.text: qsTr("入力可能な最大値。空欄で未指定（上限なし）。確定時に範囲外は境界へ丸めます")
                                ToolTip.visible: hovered
                                ToolTip.delay: 600
                                onTextEdited: {
                                    if (canvas.selectedItem && acceptableInput) {
                                        var t = text.trim()
                                        var n = Number(t)
                                        if (t === "" || t === "-" || t === "." || isNaN(n)) {
                                            canvas.selectedItem.widgetHasMax = false
                                        } else {
                                            canvas.selectedItem.widgetMaxValue = n
                                            canvas.selectedItem.widgetHasMax = true
                                        }
                                    }
                                }
                                Connections {
                                    target: canvas
                                    function onSelectedItemChanged() {
                                        inspectorMaxValueField.text =
                                            (canvas.selectedItem && canvas.selectedItem.widgetHasMax)
                                                ? String(canvas.selectedItem.widgetMaxValue) : ""
                                    }
                                }
                            }

                            Label {
                                objectName: "inspectorIdLabel"
                                color: "#555555"
                                text: qsTr("ID: ") + (canvas.selectedItem
                                    ? canvas.selectedItem.widgetId : "")
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

    // Task 46: 色スウォッチクリックで開く共有 ColorDialog。targetField /
    // targetProperty を差し替えて 3 つの色（背景 / 文字 / ボーダー）で使い回す。
    // 確定は CheckBox と同じ離散操作なので、明示 beginEdit/commitEdit で
    // 1 操作 = 1 件を undo へ積む（フォーカス境界を通らないため。Task 38 と同型）。
    ColorDialog {
        id: inspectorColorDialog
        title: qsTr("色を選択")
        property var targetField: null
        property string targetProperty: ""
        onAccepted: {
            if (!canvas.selectedItem || !targetField) {
                return
            }
            // Schema は "#RRGGBB" 文字列を期待するため hex 化して書き戻す。
            // TextField の表示も更新する（プログラム代入は textEdited を発火
            // しないため二重書き戻しは起きない）。
            const hex = rootWindow.colorToHex(selectedColor)
            canvas.beginEdit()
            canvas.selectedItem[targetProperty] = hex
            canvas.commitEdit()
            targetField.text = hex
        }
    }

    // Task 8B-D: Trend 系列の線色を選ぶ共有 ColorDialog（series 配列の index へ書き戻す）。
    // 色変更は離散操作なので明示 beginEdit/commitEdit で 1 件 undo へ積む（CheckBox と同型）。
    ColorDialog {
        id: seriesColorDialog
        title: qsTr("系列の線色を選択")
        property int targetIndex: -1
        onAccepted: {
            if (!canvas.selectedItem || targetIndex < 0) {
                return
            }
            const hex = rootWindow.colorToHex(selectedColor)
            canvas.beginEdit()
            rootWindow.updateSeries(targetIndex, "color", hex)
            canvas.commitEdit()
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
