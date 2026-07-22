import QtQuick
import QtQuick.Window
import QtQuick.Controls
import HmiWidgets

// Task W-C / W-D（Phase 11）: サンプルパレット・パネル。インスペクタ領域の先頭に常設し、
// プリセット（`{ id, label, type, defaults }`）を **実 Widget（HmiSimpleButton）で縮小
// レンダリング**して一覧表示する。追加は 2 経路：
//   - **クリック（W-C）**：セルをクリックすると presetActivated(preset) を発火し、
//     Main.qml が canvas.addPresetWidget(preset) を呼んでキャンバス中央へ追加する。
//   - **ドラッグ&ドロップ（W-D）**：セルをキャンバスへドラッグすると、Drag.mimeData に
//     プリセット JSON を載せて運び、Canvas の DropArea がドロップ座標へ追加する。
// パネルは選択有無に依らず常時表示（設計面の「置ける物」一覧）。
//
// 汎用設計：presets 配列にエントリを足せば他 Widget 種別も並べられる（初号＝SimpleButton）。
// サムネイルは画像でなく **生 Widget** なので、HmiSimpleButton の見た目変更に自動追従する。
InspectorSection {
    id: palette
    title: qsTr("サンプルパレット")

    // クリックされたプリセット（`{ id, label, type, defaults }`）を通知する。
    signal presetActivated(var preset)

    // プリセット定義（初号＝SimpleButton の 2 サンプル）。defaults は addPresetWidget が
    // そのまま初期値に使う（width/height/text + 種別固有フィールド）。将来ここへ追記して増やす。
    property var presets: [
        { id: "simple-circle-light", label: qsTr("円・ライト"), type: "SimpleButton",
          defaults: { width: 160, height: 160, text: "TEST", shape: "circle", theme: "light" } },
        { id: "simple-square-dark", label: qsTr("四角・ダーク"), type: "SimpleButton",
          defaults: { width: 160, height: 160, text: "TEST", shape: "square", theme: "dark" } }
    ]

    Flow {
        width: parent.width
        spacing: 6

        Repeater {
            model: palette.presets

            // 1 プリセット = 1 セル（縮小プレビュー + ラベル + クリック追加）。
            Rectangle {
                id: cell
                required property var modelData
                objectName: "paletteCell_" + modelData.id
                width: 112
                height: 122
                radius: 4
                color: cellMouse.containsMouse ? "#eef4ff" : "#f7f7f7"
                border.color: cellMouse.containsMouse ? "#9db8e0" : "#cccccc"
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    // サムネイルは **プリセットの type に応じて実 Widget を選んで縮小描画**する
                    //（Codex PR #165 [P2]）。全セル一律 HmiSimpleButton だと、将来 presets に
                    // Button/Label 等を足したときパレット表示と追加される実型が食い違うため。
                    // Canvas.qml の delegate と同じ Loader + inline Component の型分岐パターン。
                    // 新しいプリセット型を足すときはここに Component 分岐を 1 つ追加する。
                    Loader {
                        anchors.horizontalCenter: parent.horizontalCenter
                        objectName: "paletteThumb_" + cell.modelData.id
                        width: 82
                        height: 82
                        sourceComponent: cell.modelData.type === "SimpleButton"
                            ? simpleButtonThumb : genericThumb
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cell.modelData.label
                        color: "#555555"
                        font.pixelSize: 11
                    }
                }

                // SimpleButton プリセットのサムネイル（実 HmiSimpleButton・live:false＝静的プレビュー）。
                // HmiSimpleButton は自身の width/height に比例して描くので、scale 変換でなく
                // 小さいサイズを与えるだけで「見た目そのまま」の縮小版になる。inline Component は
                // 定義位置の外側 id（cell）を捕捉できるので cell.modelData.defaults を参照できる。
                Component {
                    id: simpleButtonThumb
                    HmiSimpleButton {
                        anchors.fill: parent
                        live: false
                        text: cell.modelData.defaults.text !== undefined ? cell.modelData.defaults.text : "TEST"
                        shape: cell.modelData.defaults.shape !== undefined ? cell.modelData.defaults.shape : ""
                        theme: cell.modelData.defaults.theme !== undefined ? cell.modelData.defaults.theme : ""
                        accentColor: cell.modelData.defaults.accentColor !== undefined ? cell.modelData.defaults.accentColor : ""
                    }
                }

                // 未対応型のフォールバック（サムネイル未実装の型に SimpleButton を誤表示しないための
                // 中立プレースホルダ。実際にその型のプリセットを足すときに専用 Component 分岐へ差し替える）。
                Component {
                    id: genericThumb
                    Rectangle {
                        anchors.fill: parent
                        color: "#ffffff"
                        border.color: "#cccccc"
                        radius: 4
                        Text {
                            anchors.centerIn: parent
                            text: cell.modelData.type
                            color: "#999999"
                            font.pixelSize: 10
                        }
                    }
                }

                // Task W-D: ドラッグ用の軽量プロキシ。cell 自身をドラッグ対象にすると Flow
                // レイアウトが乱れるため、**cell の子**として不可視のプロキシを持ち、これを
                // drag.target にする（Flow は cell の位置を管理し続け、プロキシの x/y 変化には
                // 影響されない）。プロキシに Drag.mimeData でプリセット JSON を載せ、
                // Canvas の DropArea が（内部ドラッグの）座標付きで受け取る。プロキシ自体は
                // 不可視で、見た目のゴーストは下の dragGhost（クリップされない Overlay）が担う。
                Item {
                    id: dragProxy
                    width: cell.width
                    height: cell.height
                    // 初期は cell 全面に重なる（x/y=0）。ドラッグ中は cellMouse が x/y を動かす。
                    Drag.active: cellMouse.drag.active
                    Drag.mimeData: ({ "application/x-hmi-preset": JSON.stringify(cell.modelData) })
                    Drag.keys: ["application/x-hmi-preset"]
                    // hotSpot は押下位置に合わせて cellMouse.onPressed で毎回設定する
                    //（セル中央以外を掴んでもドロップ座標＝カーソルになる。Codex PR #166 [P2]）。
                }

                // Task W-D（Codex PR #166 [Minor]）: ドラッグ中のゴースト。
                // インスペクタの ScrollView は clip: true なので、ゴーストを cell の子に置くと
                // インスペクタ境界で切れてキャンバス側まで追従して見えない。**ウィンドウの
                // contentItem（クリップされないルート Item）を親**にして z を上げ、カーソルへ
                // 追従させる。位置は cellMouse がドラッグ中に mapToItem で親座標へ変換して更新する。
                // 注意：ここに Overlay.overlay を使ってはいけない（RF-A 中に発覚した W-D の
                // 不具合）。QQuickOverlay は子を持つと Editor ウィンドウ全体のマウスイベントを
                // 奪い、ツールバー・キャンバスのクリックが全て死ぬ（Qt 6.10 offscreen で実証、
                // E2E 4 件が失敗）。contentItem 親 + 高 z なら同じ「クリップされない最前面」を
                // 副作用なしで実現できる。
                Rectangle {
                    id: dragGhost
                    parent: cell.Window.window ? cell.Window.window.contentItem : null
                    z: 1000
                    width: cell.width
                    height: cell.height
                    visible: cellMouse.drag.active
                    color: "#e8f0ff"
                    border.color: "#9db8e0"
                    border.width: 1
                    radius: 4
                    opacity: 0.9
                    Text {
                        anchors.centerIn: parent
                        text: cell.modelData.label
                        color: "#333333"
                        font.pixelSize: 11
                    }
                }

                // セル全面のクリック / ドラッグ検出（HmiSimpleButton 内蔵 MouseArea より後に
                // 宣言＝上に乗り、プレビューの clicked を消費してセル操作を確実に拾う）。
                // クリック＝W-C の中央追加、ドラッグ＝W-D の D&D 追加。
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    drag.target: dragProxy
                    // Task W-D（Codex PR #166 [Major]）: セルは clip:true の ScrollView（内部 Flickable）
                    // 内にあるため、押下中に Flickable がグラブを奪うと縦スクロールになり D&D が
                    // キャンセルされる。preventStealing でセルを押している間はグラブを保持する。
                    preventStealing: true
                    // ゴーストをカーソルへ追従させる（overlay 座標系へ変換して配置）。
                    function moveGhost(mx, my) {
                        if (!dragGhost.parent) {
                            return
                        }
                        const p = cellMouse.mapToItem(dragGhost.parent, mx, my)
                        dragGhost.x = p.x - dragGhost.width / 2
                        dragGhost.y = p.y - dragGhost.height / 2
                    }
                    // ドラッグで動いたプロキシを cell 全面へ戻す（次のドラッグの起点をそろえる）。
                    // 確定（onReleased）だけでなくキャンセル（onCanceled：ウィンドウ非アクティブ化・
                    // ポインタキャンセル）でも呼ばないと、ずれたプロキシが次のドラッグへ持ち越される
                    //（Codex PR #166 [P2]）。
                    function resetProxy() {
                        dragProxy.x = 0
                        dragProxy.y = 0
                    }
                    onPressed: function(mouse) {
                        // ホットスポットを実際の押下位置に合わせ、ドロップ座標＝カーソル位置にする
                        //（セル中央以外を掴んでもズレない。Codex PR #166 [P2]）。
                        dragProxy.Drag.hotSpot.x = mouse.x
                        dragProxy.Drag.hotSpot.y = mouse.y
                        moveGhost(mouse.x, mouse.y)
                    }
                    onPositionChanged: function(mouse) { moveGhost(mouse.x, mouse.y) }
                    onClicked: palette.presetActivated(cell.modelData)
                    onReleased: {
                        if (dragProxy.Drag.active) {
                            dragProxy.Drag.drop()
                        }
                        resetProxy()
                    }
                    onCanceled: resetProxy()
                }
            }
        }
    }
}
