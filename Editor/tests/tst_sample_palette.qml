import QtQuick
import QtTest

// Task W-D（Phase 11）: サンプルパレットのドラッグ&ドロップ配線を検証する。
//
// 観点：
//   - パレットのドラッグ用プロキシ（dragProxy）が Drag.mimeData に preset JSON を載せ、
//     Canvas.qml の DropArea と同じ Drag.keys を使うこと。
//   - パレットのセルからキャンバスへ実際にマウスでドラッグ&ドロップすると、
//     DropArea.onDropped を通って Widget が 1 個追加されること（実ドラッグ経路）。
//     **パレットは実アプリ同様に Flickable（インスペクタの ScrollView 相当）内に
//     置き、キャンバスへ向けて縦方向にも動かす**ことで、親 Flickable の grab 横取り
//     （preventStealing 未設定だとドロップできない）まで再現する（Codex PR #170 [P1]）。
//
// 配置：Main.qml と同じくパレットを Flickable 内に置き、Canvas.qml / SamplePalette.qml を
//   Qt.resolvedUrl で直接ロードする（本体構造を変えないテスト方式。tst_canvas.qml と同じ）。
TestCase {
    id: testCase
    name: "SamplePalette"
    when: windowShown
    visible: true
    width: 1040
    height: 700

    property var canvas: null
    property var palette: null

    Item {
        id: stage
        anchors.fill: parent
    }

    // 実アプリのインスペクタ ScrollView（＝Flickable）を模した、実際にスクロール可能な
    // コンテナ（contentHeight > height）。この中にパレットを置くことで、縦ドラッグ時に
    // 親 Flickable が grab を奪おうとする本番固有の経路を再現する。
    Flickable {
        id: paletteFlick
        x: 840
        y: 0
        width: 180
        height: 320
        contentWidth: 180
        contentHeight: 900
        clip: true
    }

    Component.onCompleted: {
        const canvasComp = Qt.createComponent(Qt.resolvedUrl("../qml/Canvas.qml"));
        if (canvasComp.status !== Component.Ready) {
            console.error("Canvas の読込に失敗:", canvasComp.errorString());
            return;
        }
        canvas = canvasComp.createObject(stage, { x: 0, y: 0 });

        const paletteComp = Qt.createComponent(Qt.resolvedUrl("../qml/SamplePalette.qml"));
        if (paletteComp.status !== Component.Ready) {
            console.error("SamplePalette の読込に失敗:", paletteComp.errorString());
            return;
        }
        // 実アプリ同様に Flickable の contentItem 内へ置く。
        palette = paletteComp.createObject(paletteFlick.contentItem, { width: 180 });
    }

    function init() {
        verify(canvas !== null, "Canvas が未ロード");
        verify(palette !== null, "SamplePalette が未ロード");
        canvas.clearHistory();
        canvas.widgetModel = [];
        canvas.selectedWidgetIds = [];
        paletteFlick.contentY = 0;
        tryVerify(function() { return editableChildren().length === 0; }, 1000,
                  "init: キャンバスが空にならない");
    }

    // objectName で子孫を再帰探索する（tst_canvas.qml と同じ）。
    function findByObjectName(node, name) {
        if (!node) {
            return null;
        }
        if (node.objectName === name) {
            return node;
        }
        const kids = node.children;
        if (kids) {
            for (let i = 0; i < kids.length; ++i) {
                const found = findByObjectName(kids[i], name);
                if (found) {
                    return found;
                }
            }
        }
        return null;
    }

    // キャンバス配下から EditableWidget（widgetId を持つ子）だけを抽出する。
    function editableChildren() {
        const items = canvas.widgetItems;
        const result = [];
        for (let i = 0; i < items.length; ++i) {
            if (items[i].widgetId !== undefined) {
                result.push(items[i]);
            }
        }
        return result;
    }

    function driveScene(src, pressLocalX, pressLocalY, endSceneX, endSceneY) {
        const startScene = src.mapToItem(testCase, pressLocalX, pressLocalY);
        mousePress(src, pressLocalX, pressLocalY);
        const steps = 30;
        for (let i = 1; i <= steps; ++i) {
            const t = i / steps;
            const mx = startScene.x + (endSceneX - startScene.x) * t;
            const my = startScene.y + (endSceneY - startScene.y) * t;
            mouseMove(testCase, mx, my);
        }
        const endLocal = src.mapFromItem(testCase, endSceneX, endSceneY);
        mouseRelease(src, endLocal.x, endLocal.y);
    }

    // Task W-D: dragProxy が Canvas の DropArea と一致する MIME key で preset JSON を運ぶ。
    function test_drag_proxy_carries_preset_mime_data() {
        const proxy = findByObjectName(testCase, "paletteDragProxy_simple-circle-light");
        verify(proxy !== null, "dragProxy が見つからない");
        compare(proxy.Drag.keys.length, 1);
        compare(proxy.Drag.keys[0], "application/x-hmi-preset");
        const preset = JSON.parse(proxy.Drag.mimeData["application/x-hmi-preset"]);
        compare(preset.type, "SimpleButton");
        compare(preset.defaults.shape, "circle");
    }

    // Task W-D（Codex PR #170 [P1]）：ドラッグ用 MouseArea に preventStealing が立っている。
    // 実アプリではパレットは ScrollView（Flickable）内にあり、これが無いと縦ドラッグで親
    // Flickable が grab を奪ってドロップできない。offscreen の合成マウスイベントでは
    // Flickable の横取り自体を再現できない（既知の offscreen ドラッグ制約）ため、設定の
    // 有無を決定的に固定して回帰を防ぐ。
    function test_cell_mousearea_prevents_stealing() {
        const ma = findByObjectName(testCase, "paletteCellMouse_simple-circle-light");
        verify(ma !== null, "パレットセルの MouseArea が見つからない");
        compare(ma.preventStealing, true, "preventStealing が立っていない（Flickable に grab を奪われる）");
    }

    // Task W-D: MouseArea は dragProxy を動かし、dragProxy が MIME 付き Drag を発火する。
    // 実マウス D&D は offscreen で不安定なので、ここでは配線を決定的に固定する。
    function test_real_drag_drop_from_flickable_adds_widget() {
        const proxy = findByObjectName(testCase, "paletteDragProxy_simple-circle-light");
        const ma = findByObjectName(testCase, "paletteCellMouse_simple-circle-light");
        verify(proxy !== null, "dragProxy が見つからない");
        verify(ma !== null, "パレットセルの MouseArea が見つからない");
        compare(ma.drag.target, proxy);
        compare(proxy.Drag.keys[0], "application/x-hmi-preset");

        const targetScene = canvas.mapToItem(testCase, 400, 300);
        driveScene(ma, ma.width / 2, ma.height / 2, targetScene.x, targetScene.y);

        tryVerify(function() { return editableChildren().length === 1; }, 2000,
                  "パレットからキャンバスへ D&D しても Widget が追加されない");
        const snap = canvas.snapshotModel();
        compare(snap.length, 1);
        compare(snap[0].type, "SimpleButton");
        compare(snap[0].shape, "circle");
        compare(snap[0].theme, "light");
    }
}
