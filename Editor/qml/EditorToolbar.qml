import QtQuick
import QtQuick.Controls

// Task RF-A: Editor 上部ツールバー。Main.qml の肥大化解消のため Row ごと切り出した
// （リファクタリング計画 RF-A。ボタン構成・objectName・挙動は Main.qml 時代と同一＝
// 既存 E2E 互換。Spix のパス `hmiEditorWindow/<objectName>` は無名の中間 Item を
// 透過するため、この Row 自身には objectName を付けない）。
// Canvas への参照は受け口プロパティ editorCanvas で受ける（`canvas: canvas` のような
// 同名バインドは右辺が自分自身に解決される罠があるため別名にする＝MB-4 罠①）。
// 開く / 保存ダイアログは Main.qml 側の所有物なので、シグナルで依頼だけ送る。
Row {
    id: root

    // Main.qml の Canvas（id: canvas）。ボタン群の操作先。
    property var editorCanvas: null

    // 「開く」「保存」ボタンが押されたことを Main.qml（FileDialog の所有者）へ通知する。
    signal openRequested()
    signal saveRequested()

    spacing: 8

    // Task 18 / 48: Widget 追加。E2E からは objectName で参照する。
    // Task 48: 横展開で種別が増えたため「ボタン追加」と明示し、隣に「ラベル追加」を足す。
    // objectName（addWidgetButton）と挙動（Button を追加）は据え置き＝既存 E2E 互換。
    Button {
        objectName: "addWidgetButton"
        text: qsTr("ボタン追加")
        onClicked: root.editorCanvas.addWidget("Button")
    }

    // Task 48: ラベル（表示専用 Widget）追加。同じ addWidget を type 違いで呼ぶ。
    Button {
        objectName: "addLabelButton"
        text: qsTr("ラベル追加")
        onClicked: root.editorCanvas.addWidget("Label")
    }

    // Task 51: 数値入力（NumericField）追加。Phase 6 の最初の入力 Widget。
    // 同じ addWidget を type 違いで呼ぶ（ホワイトリストに "NumericField" を追加済み）。
    Button {
        objectName: "addNumericButton"
        text: qsTr("数値入力追加")
        onClicked: root.editorCanvas.addWidget("NumericField")
    }

    // Task T-C: トレンドグラフ（Trend）追加。Phase 8 の最初の表示 Widget（ライブ
    // 折れ線）。同じ addWidget を type 違いで呼ぶ（ホワイトリストに "Trend" を追加済み）。
    Button {
        objectName: "addTrendButton"
        text: qsTr("トレンド追加")
        onClicked: root.editorCanvas.addWidget("Trend")
    }

    // Task M-C: メーター（Meter）追加。Phase 10 の表示 Widget（車のスピードメーター風＝
    // 円弧 + 針）。同じ addWidget を type 違いで呼ぶ（ホワイトリストに "Meter" を追加済み）。
    Button {
        objectName: "addMeterButton"
        text: qsTr("メーター追加")
        onClicked: root.editorCanvas.addWidget("Meter")
    }

    Button {
        text: qsTr("開く")
        onClicked: root.openRequested()
    }

    Button {
        text: qsTr("保存")
        onClicked: root.saveRequested()
    }

    // Task 35: グリッドスナップ ON/OFF トグル。canvas.snapEnabled を駆動し、
    // ON でドラッグ / リサイズが格子に吸着しグリッド線も表示される。
    // 編集時の補助のみで JSON には保存しない。
    CheckBox {
        objectName: "snapToggle"
        text: qsTr("スナップ")
        checked: root.editorCanvas ? root.editorCanvas.snapEnabled : false
        onToggled: root.editorCanvas.snapEnabled = checked
    }

    // Task 37: コピー / ペースト / 複製。ショートカット（Cmd/Ctrl+C/V・Ctrl+Shift+D）
    // と同じ Canvas 関数を叩く（ボタンは発見性とヘッドレススクショ用）。
    Button {
        objectName: "copyButton"
        text: qsTr("コピー")
        enabled: root.editorCanvas ? root.editorCanvas.selectedWidgetIds.length > 0 : false
        onClicked: root.editorCanvas.copySelected()
    }
    Button {
        objectName: "pasteButton"
        text: qsTr("ペースト")
        enabled: root.editorCanvas ? root.editorCanvas.clipboard.length > 0 : false
        onClicked: root.editorCanvas.pasteClipboard()
    }
    Button {
        objectName: "duplicateButton"
        text: qsTr("複製")
        enabled: root.editorCanvas ? root.editorCanvas.selectedWidgetIds.length > 0 : false
        onClicked: root.editorCanvas.duplicateSelected()
    }

    // Task 38: undo / redo ボタン（ショートカットと同じ Canvas 関数）。
    Button {
        objectName: "undoButton"
        text: qsTr("元に戻す")
        enabled: root.editorCanvas ? root.editorCanvas.canUndo : false
        onClicked: root.editorCanvas.undo()
    }
    Button {
        objectName: "redoButton"
        text: qsTr("やり直す")
        enabled: root.editorCanvas ? root.editorCanvas.canRedo : false
        onClicked: root.editorCanvas.redo()
    }
}
