import QtQuick
import QtQuick.Window
import HmiEditor

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
        }
    }
}
