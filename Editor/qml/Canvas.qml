import QtQuick

// HMI 編集用のキャンバス。
// 白背景 + 枠線を持つ固定サイズの編集領域を表す。
// 後続 Task で Widget を配置するため、widgetLayer を default property alias として
// 公開しており、本要素の子として宣言された QML 要素はキャンバス内部に配置される。
Item {
    id: root

    // キャンバスの論理サイズ（外部からプロパティで指定可能）
    property int canvasWidth: 800
    property int canvasHeight: 600

    // 子要素は widgetLayer に直接配置する
    default property alias content: widgetLayer.data

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
        }
    }
}
