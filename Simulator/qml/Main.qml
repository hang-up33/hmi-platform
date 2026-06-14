import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Dialogs
import HmiSimulator
// 変数デバッグパネル（下記）が VariableStore（実行時の変数現在値ストア）を直接読むため。
import HmiWidgets

Window {
    id: rootWindow
    width: 1024
    height: 768
    visible: true
    title: qsTr("HMI Simulator")
    // Task 20: Spix からの参照パス解決のため Window に objectName を付与する。
    // Editor 側（hmiEditorWindow）と同じ命名規則。
    objectName: "hmiSimulatorWindow"

    // 変数デバッグパネルの表示状態（既定は非表示）。ツールバーの「変数」トグルで切替える。
    property bool showVarPanel: false

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

            // 変数（タグ）デバッグパネルの表示トグル。checkable:false のボタンに checked を
            // バインドした時のように「見た目は変わらないが内部の変数値は変化している」ケースを、
            // 実行時の現在値を一覧表示して確認できるようにする（Simulator は読み取り専用の
            // 試験環境なのでデバッグ表示があると挙動確認が速い）。
            Button {
                id: varPanelToggle
                objectName: "varPanelToggle"
                text: qsTr("変数")
                checkable: true
                checked: rootWindow.showVarPanel
                onClicked: rootWindow.showVarPanel = !rootWindow.showVarPanel
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

        // ── 変数（タグ）デバッグパネル ──────────────────────────────
        // 実行時の変数現在値（VariableStore.values）と定義（canvas.variableModel）を
        // ライブ表示する。VariableStore.values は再代入で変更通知されるため、各行の値
        // バインディング（VariableStore.values[name]）は setVariable / toggleVariable /
        // 入力確定で変数が変わるたび自動更新される（Task 41 の boundValue と同じ依存追跡）。
        // 用途：checkable:false のボタンに checked をバインドした等「見た目は不変でも内部値は
        // 変化している」ケースを、画面で直接確認できるようにする。
        Rectangle {
            id: varPanel
            objectName: "varPanel"
            visible: rootWindow.showVarPanel
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 8
            width: 260
            color: "#fbfbfb"
            border.color: "#bbbbbb"
            border.width: 1
            radius: 4

            // 既定 1024px 幅では中央 800px キャンバスと右 260px パネルが重なるため、
            // パネル上のクリック / ホイールが背後の HmiButton・入力 Widget の MouseArea へ
            // 抜けてアクションや入力を誤発火させ得る（Codex PR #109 P2）。パネル全面で
            // 全ボタン + ホイールを消費して下層へのイベント貫通を止める。
            // **下の Column より前に宣言する**（＝低 z-order）のは意図的：表示専用の Label は
            // イベントを消費しないので空白部のクリックはこの MouseArea が拾い、かつ将来
            // Column 内に操作可能な子を足してもそちらが上位で先にイベントを受けられる
            // （このキャッチャーが Column の子を塞がない）。(CodeRabbit PR #109 nit)
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true
                onWheel: function(wheel) { wheel.accepted = true }
            }

            // ヘッダ（固定）。変数行は下の ScrollView 内でスクロールする。
            Label {
                id: varPanelHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                text: qsTr("変数（タグ）")
                font.bold: true
                color: "#333333"
            }

            // 変数行のスクロール領域（Codex PR #109 P3）。変数定義がパネル高さを超える
            // 件数でも全行を閲覧できるよう、Repeater を高さ制約付き ScrollView + clip に入れる。
            ScrollView {
                id: varScroll
                anchors.top: varPanelHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 10
                anchors.topMargin: 6
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                Column {
                    width: varScroll.availableWidth
                    spacing: 6

                    // 定義が無い（変数未設定の JSON）ときの案内。
                    Label {
                        objectName: "varPanelEmptyHint"
                        width: parent.width
                        visible: !canvas.variableModel || canvas.variableModel.length === 0
                        text: qsTr("変数が定義されていません")
                        color: "#888888"
                        wrapMode: Text.WordWrap
                    }

                    // 各変数を 1 行（name : value）で表示。type も添える。
                    Repeater {
                        model: canvas.variableModel
                        delegate: Row {
                            required property var modelData
                            objectName: "varRow_" + (modelData && modelData.name !== undefined
                                                     ? modelData.name : "")
                            width: parent.width
                            spacing: 6

                            Label {
                                width: parent.width * 0.5
                                elide: Text.ElideRight
                                color: "#444444"
                                text: (modelData ? modelData.name : "")
                                      + " (" + (modelData && modelData.type !== undefined
                                                ? modelData.type : "string") + ")"
                            }
                            Label {
                                objectName: "varValue"
                                width: parent.width * 0.5 - parent.spacing
                                elide: Text.ElideRight
                                font.bold: true
                                color: "#1d3557"
                                // 現在値（VariableStore.values）をライブ表示。未初期化は "—"。
                                text: {
                                    if (!modelData || modelData.name === undefined) {
                                        return "—"
                                    }
                                    const v = VariableStore.values[modelData.name]
                                    return v === undefined ? "—" : String(v)
                                }
                            }
                        }
                    }
                }
            }
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
                // Task 41: 変数定義を widgetModel より先に設定し、delegate 生成時に
                // 変数ストアが初期化済みになるようにする（binding の初期表示を正す）。
                canvas.variableModel = result.variables !== undefined ? result.variables : []
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
            // Task 41: 変数定義を widgetModel より先に設定する（上記 onCompleted と同様）。
            canvas.variableModel = result.variables !== undefined ? result.variables : []
            canvas.widgetModel = result.widgets
            canvas.loaded = true
            console.log("プロジェクト読込:", openDialog.selectedFile,
                        "widgets =", result.widgets.length)
        }
    }
}
