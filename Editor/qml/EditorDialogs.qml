import QtQuick
import QtQuick.Dialogs

// Task RF-A: Editor のダイアログ群（色選択 ×2 / ファイル保存・読込）。Main.qml の
// 肥大化解消のためまとめて切り出した（リファクタリング計画 RF-A。各ダイアログの
// ロジックは Main.qml 時代と同一）。呼び出しは open* 関数経由に統一し、Main.qml は
// 従来の関数名（openColorDialog / openSeriesColorDialog）から委譲するだけにする
// （インスペクタ各所の呼び出し箇所を変えないため）。
// Canvas / rootWindow への参照は受け口プロパティで受ける（同名バインドの自己参照
// 罠を避けるため別名＝MB-4 罠①）。projectIo は C++ の context property なので
// このファイルからもそのまま見える。
Item {
    id: root

    // Main.qml の Canvas（id: canvas）と Window（id: rootWindow）。
    property var editorCanvas: null
    property var editorRoot: null

    // Task 46: 色スウォッチクリックで共有 ColorDialog を開く。field = 書き戻し先の
    // hex TextField、targetProperty = 選択中 live Item のプロパティ名
    //（"widgetBackgroundColor" 等）、fallback = 未指定時の既定色（HmiButton の
    // resolved* と同じ値。ダイアログの初期色として使う）。
    function openInspectorColor(field, targetProperty, fallback) {
        if (!editorCanvas.selectedItem) {
            return
        }
        inspectorColorDialog.targetField = field
        inspectorColorDialog.targetProperty = targetProperty
        inspectorColorDialog.selectedColor =
            (field.text !== "" && field.acceptableInput) ? field.text : fallback
        inspectorColorDialog.open()
    }

    // Task 8B-D: 系列の線色を選ぶ専用 ColorDialog 起動。背景色等の openInspectorColor は
    // 「選択中 Item の単一プロパティ名」へ書き戻す方式だが、系列色は配列内 index への
    // 書き戻しが要るため別ダイアログ（seriesColorDialog）を使う。
    function openSeriesColor(index, currentHex) {
        if (!editorCanvas.selectedItem) {
            return
        }
        seriesColorDialog.targetIndex = index
        seriesColorDialog.selectedColor =
            (currentHex && /^#[0-9A-Fa-f]{6}$/.test(currentHex)) ? currentHex : "#4cc9f0"
        seriesColorDialog.open()
    }

    // ツールバーの「保存」「開く」から呼ぶ FileDialog の起動口。
    function openSaveDialog() {
        saveDialog.open()
    }

    function openOpenDialog() {
        openDialog.open()
    }

    // Task 46: 色スウォッチクリックで開く共有 ColorDialog。targetField /
    // targetProperty を差し替えて 3 つの色（背景 / 文字 / ボーダー）で使い回す。
    // 確定は CheckBox と同じ離散操作なので、明示 beginEdit/commitEdit で
    // 1 操作 = 1 件を undo へ積む（フォーカス境界を通らないため。Task 38 と同型）。
    ColorDialog {
        id: inspectorColorDialog
        title: qsTr("色を選択")
        property var targetField: null
        property string targetProperty: ""
        onAccepted: {
            if (!root.editorCanvas.selectedItem || !targetField) {
                return
            }
            // Schema は "#RRGGBB" 文字列を期待するため hex 化して書き戻す。
            // TextField の表示も更新する（プログラム代入は textEdited を発火
            // しないため二重書き戻しは起きない）。
            const hex = root.editorRoot.colorToHex(selectedColor)
            root.editorCanvas.beginEdit()
            root.editorCanvas.selectedItem[targetProperty] = hex
            root.editorCanvas.commitEdit()
            targetField.text = hex
        }
    }

    // Task 8B-D: Trend 系列の線色を選ぶ共有 ColorDialog（series 配列の index へ書き戻す）。
    // 色変更は離散操作なので明示 beginEdit/commitEdit で 1 件 undo へ積む（CheckBox と同型）。
    ColorDialog {
        id: seriesColorDialog
        title: qsTr("系列の線色を選択")
        property int targetIndex: -1
        onAccepted: {
            if (!root.editorCanvas.selectedItem || targetIndex < 0) {
                return
            }
            const hex = root.editorRoot.colorToHex(selectedColor)
            root.editorCanvas.beginEdit()
            root.editorRoot.updateSeries(targetIndex, "color", hex)
            root.editorCanvas.commitEdit()
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
            const widgets = root.editorCanvas.snapshotModel()
            // Task 39: 読み込んだ変数定義もそのまま保存へ渡す（失わないため）。
            const ok = projectIo.save(saveDialog.selectedFile, "Sample", "Main", widgets,
                                      root.editorRoot.projectVariables)
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
            // Task 40: 変数定義を widgetModel より先に設定（sync 時に ComboBox 選択肢を揃える）。
            root.editorRoot.projectVariables = result.variables !== undefined ? result.variables : []
            // Repeater の model を差し替えて Widget 群を再構築する
            root.editorCanvas.widgetModel = result.widgets
            root.editorCanvas.clearHistory()  // Task 38: 読込前プロジェクトの undo 履歴は破棄
            console.log("プロジェクト読込:", openDialog.selectedFile,
                        "widgets =", result.widgets.length)
        }
    }
}
