import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import HmiEditor
import HmiWidgets

Window {
    id: rootWindow
    width: 1024
    height: 768
    visible: true
    title: qsTr("HMI Editor")
    // Task 18: Spix からのパス解決のため Window 自身に objectName を付与する。
    // Spix のテストランナーは `hmiEditorWindow/<objectName>` の形で操作対象
    // QML Item を指定する。
    objectName: "hmiEditorWindow"

    // Task 19: E2E（Spix の invokeMethod）から呼ぶ JSON 保存ラッパー。
    // FileDialog は AppleScript / Spix から自動操作できないため、Canvas 上の
    // EditableWidget 群を Shared/Schema 互換のリストへ変換 → ProjectIo.save に
    // 直接渡す処理を関数化する。saveDialog.onAccepted と同じロジック。
    // 戻り値は ProjectIo.save の bool をそのまま返し、Spix 側で
    // <boolean>0/1</boolean> として受け取れる。
    function saveTo(path) {
        if (!path) {
            return false
        }
        const items = canvas.widgetItems
        const widgets = []
        for (let i = 0; i < items.length; ++i) {
            const item = items[i]
            if (item.widgetId === undefined) {
                continue
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
        // ProjectIo.save は FileDialog 由来の `file:///` 形式 QUrl を期待する
        // ため、絶対パスを `file://` プレフィックス付きで URL 化して渡す。
        // E2E は macOS / Linux でのみ走る（Windows MinGW は HMI_ENABLE_E2E=OFF）
        // ため POSIX 絶対パス前提でよい。
        const url = Qt.resolvedUrl("file://" + path)
        return projectIo.save(url, "Sample", "Main", widgets)
    }

    // Task 19: 起動時自動ロード。`--open <path>` で初期 JSON URL が渡された
    // 場合のみ projectIo.load() を呼んで Canvas を再構築する。Simulator の
    // Main.qml と同じパターン（Task 8 で確立）。E2E の「保存 → 別プロセスで
    // 開いて再現」ループはこの分岐に依存する。
    Component.onCompleted: {
        if (initialJsonUrl && initialJsonUrl.toString() !== "") {
            const result = projectIo.load(initialJsonUrl)
            if (!result || !result.ok) {
                console.warn("起動時プロジェクト読込に失敗:", initialJsonUrl)
                return
            }
            canvas.widgetModel = result.widgets
            console.log("起動時プロジェクト読込:", initialJsonUrl,
                        "widgets =", result.widgets.length)
        }
    }

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
