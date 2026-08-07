import QtQuick
import QtQuick.Window
import QtQuick.Controls
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
        inspector.syncActionToInspector()
        inspector.syncBindingToInspector()
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
    // Phase 9 / OP-1: proto 切替（modbusTcp ↔ opcua）。proto あたり単一接続の制約
    //（Phase 7 と同じ）を維持しつつ、Modbus と OPC-UA を混在させたとき connections[] の
    // id 衝突（両 proto が同じ "plc1" に集約され save が最初の接続だけ採用→後続を捨て、
    // 再読込で壊れる）を防ぐため、proto 由来の既定 connection id を入れる（modbusTcp→"plc1"
    // / opcua→"opc1"）。さらに非アクティブ proto のフィールドをクリアして、opcua 切替後も残る
    // reg のせいで isValidJson が「nodeId 空でも reg 経由で有効」と誤判定するのを防ぐ
    //（opcua へ→reg/address クリア、modbusTcp へ→endpoint/nodeId クリア）。Codex/CodeRabbit PR #140。
    function updateVariableSourceProto(index, proto) {
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
        ns.proto = proto
        if (proto === "opcua") {
            ns.connection = "opc1"
            ns.reg = ""
            ns.address = 0
            ns.poll = 0  // OPC-UA 既定は購読のみ（0 = フォールバックなし）
        } else {
            ns.connection = "plc1"
            // opcua で reg/address をクリアしているため、modbusTcp へ戻す時は既定値へ復元する
            //（さもないと reg 空のまま save → isValidJson 不正で割当が丸ごと落ちる。Codex PR #140）。
            ns.reg = "holding"
            ns.address = 0
            ns.endpoint = ""
            ns.nodeId = ""
            ns.poll = 1000  // Modbus 既定ポーリング
        }
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

    // Task 8B-D: 系列の線色を選ぶ専用 ColorDialog 起動。背景色等の openColorDialog は
    // 「選択中 Item の単一プロパティ名」へ書き戻す方式だが、系列色は配列内 index への
    // 書き戻しが要るため別ダイアログ（seriesColorDialog）を使う。
    function openSeriesColorDialog(index, currentHex) {
        // Task RF-A: 実体は EditorDialogs へ移動（呼び出し名は据え置き）。
        dialogs.openSeriesColor(index, currentHex)
    }

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
        // Task RF-A: 実体は EditorDialogs へ移動（インスペクタ各所の呼び出し名は据え置き）。
        dialogs.openInspectorColor(field, targetProperty, fallback)
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

    // Task 29: Delete キーで選択中 Widget を削除する。Shortcut なら個別 Item の
    // フォーカス・Keys ハンドリングを増やさず Window 全体に効かせられる。
    Shortcut {
        sequence: StandardKey.Delete
        enabled: canvas.selectedWidgetIds.length > 0 && !inspector.inspectorFieldFocused
        onActivated: canvas.deleteWidgets(canvas.selectedWidgetIds)
    }

    // Task 37: コピー / ペースト / 複製のショートカット。コピペは StandardKey で OS 差
    // （macOS = Cmd / Win・Linux = Ctrl）を吸収する。複製は **Ctrl+D を避け Ctrl+Shift+D**
    // にする（Ctrl+D は KDE/GNOME で StandardKey.Delete に含まれ T29 削除と衝突するため）。
    // いずれもインスペクタ編集中は無効（テキストの copy/paste を妨げない）。
    Shortcut {
        sequence: StandardKey.Copy
        enabled: canvas.selectedWidgetIds.length > 0 && !inspector.inspectorFieldFocused
        onActivated: canvas.copySelected()
    }
    Shortcut {
        sequence: StandardKey.Paste
        enabled: canvas.clipboard.length > 0 && !inspector.inspectorFieldFocused
        onActivated: canvas.pasteClipboard()
    }
    Shortcut {
        sequence: "Ctrl+Shift+D"
        enabled: canvas.selectedWidgetIds.length > 0 && !inspector.inspectorFieldFocused
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
        enabled: canvas.canUndo && !inspector.inspectorFieldFocused
        onActivated: canvas.undo()
    }
    Shortcut {
        sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]
        enabled: canvas.canRedo && !inspector.inspectorFieldFocused
        onActivated: canvas.redo()
    }

    // 薄いグレーの余白背景
    Rectangle {
        anchors.fill: parent
        color: "#e0e0e0"

        // 上部ツールバー（Task 6: 保存 / Task 7: 開く / Task 18: 追加）。
        // Task RF-A: ボタン群の実体は EditorToolbar.qml に切り出した（objectName・挙動は不変）。
        // FileDialog は EditorDialogs（id: dialogs）の所有なのでシグナル経由で開く。
        EditorToolbar {
            id: toolbar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            editorCanvas: canvas
            onOpenRequested: dialogs.openOpenDialog()
            onSaveRequested: dialogs.openSaveDialog()
        }

        // Task 26 / 44: 右側インスペクタ。選択中 Widget のプロパティ編集フォーム。
        // Task RF-B: 本体は InspectorPanel.qml に切り出した（objectName "inspectorPanel"・
        // 編集ロジック・Schema は不変）。Window が持つ変数定義とダイアログ起動は
        // editorRoot 経由で呼ばれる。
        InspectorPanel {
            id: inspector
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            editorCanvas: canvas
            editorRoot: rootWindow
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

    // Task RF-A: ダイアログ群（色選択 ×2 / ファイル保存・読込）は EditorDialogs.qml に
    // 切り出した（各ダイアログのロジックは不変。Task 46 / 8B-D / 6 / 7 の経緯はそちらを参照）。
    EditorDialogs {
        id: dialogs
        editorCanvas: canvas
        editorRoot: rootWindow
        // Task RF-B: 系列色ダイアログの書き戻し先（updateSeries）は InspectorPanel の所有。
        editorInspector: inspector
    }
}
