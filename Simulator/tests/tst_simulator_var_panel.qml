import QtQuick
import QtTest
import HmiWidgets

// 変数（タグ）デバッグパネルの検証。本体 Main.qml（Window）を生成し、
//   - 変数定義（variableModel）が一覧に出る
//   - 現在値（VariableStore.values）が setVariable / toggleVariable 等で変わると
//     パネルの値表示がライブ追従する（同じ依存追跡で再評価される）
// ことを固定する。Main.qml は `import HmiSimulator`（SimulatorCanvas）するため、
// 実行体に hmi_simulator_qmlplugin をリンクして解決する（CMakeLists 参照）。
//
// Main.qml の Component.onCompleted は `typeof initialJsonUrl !== "undefined"` を
// ガードにしており、テストでは initialJsonUrl / projectLoader を渡さないので
// 起動時自動ロードは走らない（パネルだけを直接駆動できる）。
Item {
    id: root
    width: 1024
    height: 768

    property var win: null

    // Window の可視ツリーは contentItem 配下にあるため、children だけでなく
    // contentItem も再帰的に辿って objectName 一致ノードを探す。
    function findByObjectName(node, name) {
        if (!node)
            return null
        if (node.objectName === name)
            return node
        const kids = node.children
        if (kids) {
            for (let i = 0; i < kids.length; ++i) {
                const r = findByObjectName(kids[i], name)
                if (r)
                    return r
            }
        }
        if (node.contentItem) {
            const r = findByObjectName(node.contentItem, name)
            if (r)
                return r
        }
        return null
    }

    TestCase {
        name: "SimulatorVarPanel"
        when: windowShown

        function init() {
            // singleton はテスト間で状態を共有するため毎回リセットする。
            VariableStore.clear()
        }

        function cleanup() {
            if (root.win) {
                root.win.destroy()
                root.win = null
            }
        }

        function createWindow() {
            const comp = Qt.createComponent(Qt.resolvedUrl("../qml/Main.qml"))
            compare(comp.status, Component.Ready, comp.errorString())
            const w = comp.createObject(root)
            verify(w, "Main.qml create failed")
            root.win = w
            return w
        }

        // 変数定義が一覧に並び、現在値が変数更新でライブ追従する。
        function test_panel_lists_variables_and_follows_live_value() {
            const w = createWindow()
            w.showVarPanel = true

            // 実行ストアを初期値で用意し、同じ定義をパネルの model（canvas.variableModel）へ流す。
            const defs = [
                { name: "flag", type: "bool", initial: "false" },
                { name: "level", type: "int", initial: "3" }
            ]
            VariableStore.initFrom(defs)
            setCanvasVariableModel(w, defs)
            wait(50)

            const flagValue = findVarValue(w, "flag")
            const levelValue = findVarValue(w, "level")
            verify(flagValue, "flag 行が見つからない")
            verify(levelValue, "level 行が見つからない")
            compare(flagValue.text, "false")
            compare(levelValue.text, "3")

            // 変数を更新するとパネルの値表示がライブ追従する。
            VariableStore.setValue("flag", true)
            VariableStore.setValue("level", 42)
            wait(50)
            compare(flagValue.text, "true")
            compare(levelValue.text, "42")
        }

        // 変数が無い JSON では案内文が出る（行は 0 件）。
        function test_panel_shows_placeholder_when_no_variables() {
            const w = createWindow()
            w.showVarPanel = true
            setCanvasVariableModel(w, [])
            wait(50)
            verify(!findVarValue(w, "flag"), "変数 0 件なのに行がある")
        }

        // ── ヘルパ ─────────────────────────────────────────────
        // Main.qml 内の SimulatorCanvas（id: canvas）へ variableModel を流す。
        // canvas は objectName 無しだが varPanel と兄弟なので、varPanel の parent
        // （背景 Rectangle）の children から SimulatorCanvas を型で拾う。
        function setCanvasVariableModel(w, model) {
            const panel = findByObjectName(w, "varPanel")
            verify(panel, "varPanel が見つからない")
            const bg = panel.parent
            for (let i = 0; i < bg.children.length; ++i) {
                const ch = bg.children[i]
                // SimulatorCanvas は variableModel / widgetModel / loaded を持つ。
                if (ch !== panel && ch.variableModel !== undefined) {
                    ch.variableModel = model
                    return
                }
            }
            verify(false, "SimulatorCanvas が見つからない")
        }

        // パネル内の変数 <name> 行の値ラベル（objectName: "varValue"）を返す。
        function findVarValue(w, name) {
            const rowObj = "varRow_" + name
            const row = findByObjectName(w, rowObj)
            if (!row)
                return null
            return findByObjectName(row, "varValue")
        }
    }
}
