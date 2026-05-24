import QtQuick
import QtQuick.Window
import HmiEditor
import HmiWidgets

Window {
    width: 1024
    height: 768
    visible: true
    title: qsTr("HMI Editor")

    // 薄いグレーの余白背景
    Rectangle {
        anchors.fill: parent
        color: "#e0e0e0"

        // キャンバスを中央配置
        Canvas {
            id: canvas
            anchors.centerIn: parent
            canvasWidth: 800
            canvasHeight: 600

            // Task 4: 共有 Button Widget をハードコード配置。
            // Task 5（ドラッグ）/ Task 6-7（JSON I/O）で動的化する。
            HmiButton {
                x: 100
                y: 50
                width: 120
                height: 40
                text: "Start"
                tag: "PLC.START"
            }
        }
    }
}
