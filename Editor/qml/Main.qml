import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import HmiEditor
import HmiWidgets

Window {
    id: rootWindow
    // Task 26: 右側インスペクタ（幅 260px）を足したぶん、キャンバス（800px）が
    // 隠れないようウィンドウ幅を広げる（1024 → 1280）。
    width: 1280
    height: 768
    visible: true
    title: qsTr("HMI Editor")
    // Task 18: Spix からのパス解決のため Window 自身に objectName を付与する。
    // Spix のテストランナーは `hmiEditorWindow/<objectName>` の形で操作対象
    // QML Item を指定する。
    objectName: "hmiEditorWindow"

    // Task 26: 選択中の live な EditableWidget はインスペクタの編集対象。
    // 解決ロジックと所有は Canvas に集約した（canvas.selectedItem）。Repeater
    // 再生成後も同一 id の新しい live Item に解決し直される（Codex PR #52 P2 指摘
    // への回答。詳細は Canvas.qml の selectedItem コメント）。インスペクタは
    // この live Item を直接 two-way 編集する（widgetModel の var 配列は据え置き
    // ＝Phase 4 設計指針、delegate 再生成を起こさない）。

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
        // Task 26: live Item 群のスナップショット（インスペクタ編集を含む現在値）
        // を Canvas に集約した snapshotModel() で取得する。
        const widgets = canvas.snapshotModel()
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

        // Task 26: 右側インスペクタ。選択中 Widget の text / tag を編集する。
        // 編集対象は canvas.selectedWidgetId が指す live な EditableWidget
        // （canvas.selectedItem で解決）。Simulator / Runtime は読み取り専用の
        // ため、この編集 UI は Editor のみが持つ（Phase 4 ルール）。
        Rectangle {
            id: inspector
            objectName: "inspectorPanel"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 260
            color: "#f5f5f5"
            border.color: "#cccccc"
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Label {
                    text: qsTr("インスペクタ")
                    font.pixelSize: 16
                    font.bold: true
                }

                // 未選択時の案内
                Label {
                    objectName: "inspectorEmptyLabel"
                    visible: canvas.selectedItem === null
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#888888"
                    text: qsTr("Widget を選択してください")
                }

                // 選択中の編集フォーム
                Column {
                    objectName: "inspectorForm"
                    visible: canvas.selectedItem !== null
                    width: parent.width
                    spacing: 8

                    Label {
                        objectName: "inspectorIdLabel"
                        color: "#555555"
                        text: qsTr("ID: ") + (canvas.selectedItem
                            ? canvas.selectedItem.widgetId : "")
                    }

                    Label { text: qsTr("Text") }
                    TextField {
                        id: inspectorTextField
                        objectName: "inspectorTextField"
                        width: parent.width
                        // ユーザー入力のみ選択中 Item へ書き戻す
                        // （textEdited はプログラム変更では発火しない）。
                        // Item.widgetText 更新で HmiButton の text バインドが即追従する。
                        onTextEdited: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetText = text
                            }
                        }
                        // 選択が変わったら表示値を選択 Item の値へ更新する。
                        // text を直接バインドするとユーザー入力でバインディングが
                        // 切れ、選択切替時に追従しなくなるため明示更新する。
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorTextField.text = canvas.selectedItem
                                    ? canvas.selectedItem.widgetText : ""
                            }
                        }
                    }

                    Label { text: qsTr("Tag") }
                    TextField {
                        id: inspectorTagField
                        objectName: "inspectorTagField"
                        width: parent.width
                        onTextEdited: {
                            if (canvas.selectedItem) {
                                canvas.selectedItem.widgetTag = text
                            }
                        }
                        Connections {
                            target: canvas
                            function onSelectedItemChanged() {
                                inspectorTagField.text = canvas.selectedItem
                                    ? canvas.selectedItem.widgetTag : ""
                            }
                        }
                    }
                }
            }
        }

        // キャンバスをインスペクタを除いた左側スペースの中央に配置。
        // Task 7 で Widget 表示は Canvas 内部の Repeater + widgetModel に移譲した。
        // 初期表示の btn001 もモデル初期値で再現している。
        // Task 18: E2E（Spix）からドラッグの drop 先として参照するため objectName を付与。
        Canvas {
            id: canvas
            objectName: "canvas"
            canvasWidth: 800
            canvasHeight: 600
            anchors.verticalCenter: parent.verticalCenter
            x: (parent.width - inspector.width - width) / 2
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
            // Canvas 上の live EditableWidget 群を Shared/Schema 互換の Widget
            // リストへ変換（Task 26 で Canvas.snapshotModel() に集約・共用）。
            const widgets = canvas.snapshotModel()
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
