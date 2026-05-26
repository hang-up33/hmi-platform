import QtQuick
import HmiWidgets

// HMI 編集用のキャンバス。
// 白背景 + 枠線を持つ固定サイズの編集領域を表す。
//
// Task 7 で動的化：内部に Repeater + EditableWidget を持ち、widgetModel に
// 流し込まれた配列（{id,type,x,y,width,height,text,tag}）から Widget を生成する。
// 初期値は Task 4/5/6 で利用していた btn001 1 件のみで、起動時の見た目は従来通り。
// JSON 読込時は Main.qml から widgetModel を差し替えればキャンバスが再構築される。
Item {
    id: root

    // キャンバスの論理サイズ（外部からプロパティで指定可能）
    property int canvasWidth: 800
    property int canvasHeight: 600

    // Widget 配置情報。Main.qml の Open 結果や Save 後の再代入で差し替える。
    property var widgetModel: [
        { id: "btn001", type: "Button", x: 100, y: 50, width: 120, height: 40,
          text: "Start", tag: "PLC.START" }
    ]

    // 配置されている Widget 群（Task 6 の JSON 保存で走査するため公開）
    property alias widgetItems: widgetLayer.children

    // Task 18: 新規 Widget 追加用の単調増加カウンタ（実用上の最大連番）。
    // 初期 widgetModel に btn001 が含まれているので 1 から始める。Main.qml の
    // Open で widgetModel が差し替わった場合に備え、`addWidget()` は採番前に
    // 必ず現在の widgetModel を走査して max ID と比較し、大きい方の次を採用する
    // （Codex Task 18 P1 指摘）。
    property int widgetIdCounter: 1

    // Task 18: 既定サイズ/位置で Widget を 1 個追加する。Main.qml の追加
    // ボタンから呼ばれる。E2E（Spix）からは追加ボタンの mouseClick 経由で
    // 同じパスを通る。
    function addWidget() {
        // 既存モデルから btnNNN 形式の最大連番を走査し、カウンタと比較する。
        // 読込で外部 JSON が入った後の追加でも ID が衝突しないよう保つ。
        let maxFound = widgetIdCounter
        for (let i = 0; i < widgetModel.length; ++i) {
            const existingId = widgetModel[i].id
            if (typeof existingId !== "string") {
                continue
            }
            const m = existingId.match(/^btn(\d+)$/)
            if (!m) {
                continue
            }
            const n = parseInt(m[1], 10)
            if (n > maxFound) {
                maxFound = n
            }
        }
        widgetIdCounter = maxFound + 1
        const id = "btn" + String(widgetIdCounter).padStart(3, "0")
        const newWidget = {
            id: id,
            type: "Button",
            x: 50, y: 200, width: 120, height: 40,
            text: "New", tag: ""
        }
        // QML の property var(array) は in-place push でバインディングが
        // 発火しないことがある。新しい配列を代入することで Repeater に確実
        // にモデル変更を通知する。
        widgetModel = widgetModel.concat([newWidget])
    }

    implicitWidth: canvasWidth
    implicitHeight: canvasHeight
    width: canvasWidth
    height: canvasHeight

    Rectangle {
        id: background
        anchors.fill: parent
        color: "white"
        border.color: "#888888"
        border.width: 1

        Item {
            id: widgetLayer
            anchors.fill: parent

            Repeater {
                model: root.widgetModel
                delegate: EditableWidget {
                    id: wrapper
                    required property var modelData
                    widgetId: modelData.id !== undefined ? modelData.id : ""
                    widgetType: modelData.type !== undefined ? modelData.type : "Button"
                    widgetText: modelData.text !== undefined ? modelData.text : ""
                    widgetTag: modelData.tag !== undefined ? modelData.tag : ""
                    // Task 18: Spix から `widget_<id>` で参照できるようにする。
                    objectName: "widget_" + widgetId
                    x: modelData.x !== undefined ? modelData.x : 0
                    y: modelData.y !== undefined ? modelData.y : 0
                    width: modelData.width !== undefined ? modelData.width : 120
                    height: modelData.height !== undefined ? modelData.height : 40

                    // 現状 MVP は Button のみ。型分岐は将来 Widget 種別が増えた時に拡張。
                    HmiButton {
                        anchors.fill: parent
                        // EditableWidget の content alias は内部 container を指すため、
                        // parent 経由ではなく wrapper の id 経由でメタを参照する
                        // （CLAUDE.md の "default property alias の parent 罠" 参照）。
                        text: wrapper.widgetText
                        tag: wrapper.widgetTag
                    }
                }
            }
        }
    }
}
