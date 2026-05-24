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

    // 薄いグレーの余白背景
    Rectangle {
        anchors.fill: parent
        color: "#e0e0e0"

        // 上部ツールバー（Task 6: Save ボタンを設置）
        Row {
            id: toolbar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            spacing: 8

            Button {
                text: qsTr("保存")
                onClicked: saveDialog.open()
            }
        }

        // キャンバスを中央配置
        Canvas {
            id: canvas
            anchors.centerIn: parent
            canvasWidth: 800
            canvasHeight: 600

            // Task 4: 共有 Button Widget をハードコード配置。
            // Task 5: EditableWidget でラップしてドラッグ可能に。
            // Task 6: EditableWidget にメタ情報（id/type/text/tag）を持たせ JSON 保存対象とする。
            // Task 7（JSON 読込）で動的化する。
            EditableWidget {
                id: btn001
                widgetId: "btn001"
                widgetType: "Button"
                widgetText: "Start"
                widgetTag: "PLC.START"
                x: 100
                y: 50
                width: 120
                height: 40

                HmiButton {
                    anchors.fill: parent
                    // parent は EditableWidget 内部の container Item を指すため、
                    // メタ情報は id 経由で取りに行く。
                    text: btn001.widgetText
                    tag: btn001.widgetTag
                }
            }
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
                    continue // EditableWidget 以外（将来の補助要素など）はスキップ
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
}
