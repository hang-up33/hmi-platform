import QtQuick
import QtQuick.Controls
import HmiWidgets

// Task W-C（Phase 11）: サンプルパレット・パネル。インスペクタ領域の先頭に常設し、
// プリセット（`{ id, label, type, defaults }`）を **実 Widget（HmiSimpleButton）で縮小
// レンダリング**して一覧表示する。セルをクリックすると presetActivated(preset) を発火し、
// Main.qml が canvas.addPresetWidget(preset) を呼んでキャンバス中央へ追加する（手触り確認）。
// ドラッグ&ドロップ追加は W-D。パネルは選択有無に依らず常時表示（設計面の「置ける物」一覧）。
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

                // セル全面のクリック検出（HmiSimpleButton 内蔵 MouseArea より後に宣言＝上に乗り、
                // プレビューの clicked を消費してセルのクリック追加を確実に拾う）。
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: palette.presetActivated(cell.modelData)
                }
            }
        }
    }
}
