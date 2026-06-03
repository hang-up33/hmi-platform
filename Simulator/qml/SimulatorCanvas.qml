import QtQuick
import HmiWidgets

// HMI Simulator 用の読み取り専用キャンバス（Task 8）。
//
// Editor の Canvas.qml と似た構造だが、編集機能は持たない：
//   - EditableWidget でラップしない（ドラッグ不可）
//   - HmiButton を Repeater で直接配置する
//   - 子要素を外から追加する経路は持たない（widgetModel のみが描画ソース）
//
// QtQuick 標準の Canvas 型と衝突しないよう "SimulatorCanvas" のプレフィックス
// 命名を採用（CLAUDE.md「QtQuick 標準型と同名の QML ファイルを作らない」）。
Item {
    id: root

    property int canvasWidth: 800
    property int canvasHeight: 600

    // Widget 配置情報。Main.qml から projectLoader.load() の結果を流し込む。
    property var widgetModel: []

    // JSON 読込が一度でも成功したか。widgetModel.length では「空 widgets の
    // 有効 JSON」と「未読込」を区別できないため独立フラグで持つ
    // （ScreenData::isValidJson は空 widgets 配列を許容する仕様のため）。
    property bool loaded: false

    implicitWidth: canvasWidth
    implicitHeight: canvasHeight
    width: canvasWidth
    height: canvasHeight

    Rectangle {
        id: background
        anchors.fill: parent
        color: "white"
        border.color: "#888888"
        border.width: 1

        Repeater {
            model: root.widgetModel
            delegate: Item {
                id: wrapper
                required property var modelData
                // Task 20: Spix から `widget_<id>` で参照できるようにする
                // （Editor 側 EditableWidget と同じ命名規則）。
                objectName: "widget_" + (modelData.id !== undefined ? modelData.id : "")
                x: modelData.x !== undefined ? modelData.x : 0
                y: modelData.y !== undefined ? modelData.y : 0
                width: modelData.width !== undefined ? modelData.width : 120
                height: modelData.height !== undefined ? modelData.height : 40

                // MVP は Button のみ。将来 Widget 種別が増えたら type で分岐する。
                HmiButton {
                    anchors.fill: parent
                    text: wrapper.modelData.text !== undefined ? wrapper.modelData.text : ""
                    tag: wrapper.modelData.tag !== undefined ? wrapper.modelData.tag : ""
                    // Task 28: スタイル属性も HmiButton へ渡す（Editor delegate と対）。
                    // 未指定（空 / 0）は HmiButton 側で既定外観にフォールバックされる。
                    // Runtime は本ソースを共有するため、これだけで実機にも反映される。
                    backgroundColor: wrapper.modelData.backgroundColor !== undefined ? wrapper.modelData.backgroundColor : ""
                    textColor: wrapper.modelData.textColor !== undefined ? wrapper.modelData.textColor : ""
                    fontSize: wrapper.modelData.fontSize !== undefined ? wrapper.modelData.fontSize : 0
                }
            }
        }
    }
}
