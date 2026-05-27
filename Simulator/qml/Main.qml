import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import HmiSimulator

Window {
    width: 1024
    height: 768
    visible: true
    title: qsTr("HMI Simulator")
    // Task 20: Spix からの参照パス解決のため Window に objectName を付与する。
    // Editor 側（hmiEditorWindow）と同じ命名規則。
    objectName: "hmiSimulatorWindow"

    // 薄いグレーの余白背景
    Rectangle {
        anchors.fill: parent
        color: "#e0e0e0"

        // 上部ツールバー（Task 8: 「開く」ボタン）。
        // Simulator は読み取り専用なので保存ボタンは無し。
        Row {
            id: toolbar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            spacing: 8

            Button {
                text: qsTr("開く")
                onClicked: openDialog.open()
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                // `loaded` フラグで「未読込」と「読込成功（空含む）」を区別する。
                // widgets が 0 件でも読込成功なら "widgets: 0" を表示する。
                text: canvas.loaded
                      ? qsTr("widgets: %1").arg(canvas.widgetModel.length)
                      : qsTr("JSON 未読込")
                color: "#444444"
            }
        }

        // キャンバスを中央配置。読み取り専用。
        SimulatorCanvas {
            id: canvas
            anchors.centerIn: parent
            canvasWidth: 800
            canvasHeight: 600
        }
    }

    // 起動時に CLI 引数 `--open <path>` 相当を main.cpp 側で
    // initialJsonUrl コンテキストプロパティに詰めている。空でなければ自動ロード。
    Component.onCompleted: {
        if (typeof initialJsonUrl !== "undefined"
            && initialJsonUrl !== null
            && String(initialJsonUrl) !== "") {
            const result = projectLoader.load(initialJsonUrl)
            if (result && result.ok) {
                canvas.widgetModel = result.widgets
                canvas.loaded = true
                console.log("起動時 JSON 読込:", initialJsonUrl,
                            "widgets =", result.widgets.length)
            } else {
                console.warn("起動時 JSON 読込に失敗:", initialJsonUrl)
            }
        }
    }

    FileDialog {
        id: openDialog
        title: qsTr("プロジェクトを開く")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("JSON files (*.json)"), qsTr("All files (*)")]
        onAccepted: {
            const result = projectLoader.load(openDialog.selectedFile)
            if (!result || !result.ok) {
                console.warn("プロジェクト読込に失敗:", openDialog.selectedFile)
                return
            }
            canvas.widgetModel = result.widgets
            canvas.loaded = true
            console.log("プロジェクト読込:", openDialog.selectedFile,
                        "widgets =", result.widgets.length)
        }
    }
}
