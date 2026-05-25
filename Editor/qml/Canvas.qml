import QtQuick
import HmiWidgets

// HMI 編集用のキャンバス。
// 白背景 + 枠線を持つ固定サイズの編集領域を表す。
//
// Task 7 で動的化：内部に Repeater + EditableWidget を持ち、widgetModel に
// 流し込まれた配列（{id,type,x,y,width,height,text,tag}）から Widget を生成する。
// 初期値は Task 4/5/6 で利用していた btn001 1 件のみで、起動時の見た目は従来通り。
// JSON 読込時は Main.qml から widgetModel を差し替えればキャンバスが再構築される。
Item {
    id: root

    // キャンバスの論理サイズ（外部からプロパティで指定可能）
    property int canvasWidth: 800
    property int canvasHeight: 600

    // Widget 配置情報。Main.qml の Open 結果や Save 後の再代入で差し替える。
    property var widgetModel: [
        { id: "btn001", type: "Button", x: 100, y: 50, width: 120, height: 40,
          text: "Start", tag: "PLC.START" }
    ]

    // 配置されている Widget 群（Task 6 の JSON 保存で走査するため公開）
    property alias widgetItems: widgetLayer.children

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

        Item {
            id: widgetLayer
            anchors.fill: parent

            Repeater {
                model: root.widgetModel
                delegate: EditableWidget {
                    id: wrapper
                    required property var modelData
                    widgetId: modelData.id !== undefined ? modelData.id : ""
                    widgetType: modelData.type !== undefined ? modelData.type : "Button"
                    widgetText: modelData.text !== undefined ? modelData.text : ""
                    widgetTag: modelData.tag !== undefined ? modelData.tag : ""
                    x: modelData.x !== undefined ? modelData.x : 0
                    y: modelData.y !== undefined ? modelData.y : 0
                    width: modelData.width !== undefined ? modelData.width : 120
                    height: modelData.height !== undefined ? modelData.height : 40

                    // 現状 MVP は Button のみ。型分岐は将来 Widget 種別が増えた時に拡張。
                    HmiButton {
                        anchors.fill: parent
                        // EditableWidget の content alias は内部 container を指すため、
                        // parent 経由ではなく wrapper の id 経由でメタを参照する
                        // （CLAUDE.md の "default property alias の parent 罠" 参照）。
                        text: wrapper.widgetText
                        tag: wrapper.widgetTag
                    }
                }
            }
        }
    }
}
