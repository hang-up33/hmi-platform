import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import HmiEditor
import HmiWidgets

Window {
    width: 1024
    height: 768
    visible: true
    title: qsTr("HMI Editor")
    // Task 18: Spix からのパス解決のため Window 自身に objectName を付与する。
    // Spix のテストランナーは `hmiEditorWindow/<objectName>` の形で操作対象
    // QML Item を指定する。
    objectName: "hmiEditorWindow"

    // 薄いグレーの余白背景
    Rectangle {
        anchors.fill: parent
        color: "#e0e0e0"

        // 上部ツールバー（Task 6: 保存 / Task 7: 開く / Task 18: 追加）
        Row {
            id: toolbar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            spacing: 8

            // Task 18: Widget 追加。E2E からは objectName で参照する。
            Button {
                objectName: "addWidgetButton"
                text: qsTr("追加")
                onClicked: canvas.addWidget()
            }

            Button {
                text: qsTr("開く")
                onClicked: openDialog.open()
            }

            Button {
                text: qsTr("保存")
                onClicked: saveDialog.open()
            }
        }

        // キャンバスを中央配置。
        // Task 7 で Widget 表示は Canvas 内部の Repeater + widgetModel に移譲した。
        // 初期表示の btn001 もモデル初期値で再現している。
        // Task 18: E2E（Spix）からドラッグの drop 先として参照するため
        // objectName を付与する。
        Canvas {
            id: canvas
            objectName: "canvas"
            anchors.centerIn: parent
            canvasWidth: 800
            canvasHeight: 600
        }
    }

    // Task 6: JSON 保存ダイアログ
    FileDialog {
        id: saveDialog
        title: qsTr("プロジェクトを保存")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("JSON files (*.json)"), qsTr("All files (*)")]
        defaultSuffix: "json"
        onAccepted: {
            // Canvas 上の EditableWidget を走査し、Shared/Schema 互換の Widget リストへ変換
            const items = canvas.widgetItems
            const widgets = []
            for (let i = 0; i < items.length; ++i) {
                const item = items[i]
                if (item.widgetId === undefined) {
                    continue // EditableWidget 以外（Repeater 自身など）はスキップ
                }
                widgets.push({
                    id: item.widgetId,
                    type: item.widgetType,
                    x: Math.round(item.x),
                    y: Math.round(item.y),
                    width: Math.round(item.width),
                    height: Math.round(item.height),
                    text: item.widgetText,
                    tag: item.widgetTag
                })
            }
            const ok = projectIo.save(saveDialog.selectedFile, "Sample", "Main", widgets)
            if (!ok) {
                console.warn("プロジェクト保存に失敗:", saveDialog.selectedFile)
            } else {
                console.log("プロジェクト保存:", saveDialog.selectedFile)
            }
        }
    }

    // Task 7: JSON 読込ダイアログ
    FileDialog {
        id: openDialog
        title: qsTr("プロジェクトを開く")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("JSON files (*.json)"), qsTr("All files (*)")]
        onAccepted: {
            const result = projectIo.load(openDialog.selectedFile)
            if (!result || !result.ok) {
                console.warn("プロジェクト読込に失敗:", openDialog.selectedFile)
                return
            }
            // Repeater の model を差し替えて Widget 群を再構築する
            canvas.widgetModel = result.widgets
            console.log("プロジェクト読込:", openDialog.selectedFile,
                        "widgets =", result.widgets.length)
        }
    }
}
