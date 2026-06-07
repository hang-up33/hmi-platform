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

    // Task 25: 選択中 Widget の id。選択状態の所有者はここ（Canvas）に集約する。
    // 各 EditableWidget は delegate 側で `selected: widgetId === selectedWidgetId`
    // をバインドし、自身が選ばれているかを受け取る。空文字 "" は未選択。
    // Main.qml はこの値をインスペクタ（Task 26 以降）の編集対象解決に使う。
    property string selectedWidgetId: ""

    // 配置されている Widget 群（Task 6 の JSON 保存で走査するため公開）
    property alias widgetItems: widgetLayer.children

    // Task 26: 選択中の live な EditableWidget を解決して公開する。
    // selectedWidgetId と widgetItems(= widgetLayer.children) の **両方** に依存
    // するバインドなので、addWidget() / 読込で widgetModel を再代入して Repeater
    // が delegate を作り直しても（childrenChanged 発火）、同一 id の **新しい live
    // Item** に解決し直される（破棄済みの古い Item を掴み続けない）。Codex PR #52
    // P2 指摘への回答：再生成後の再解決はこの reactive 依存で担保し、tst_canvas.qml
    // の test_selected_item_reresolves_after_add で回帰固定する。選択状態の所有を
    // Canvas に一元化するため、Main.qml のインスペクタはこの canvas.selectedItem を
    // 参照する。
    property var selectedItem: resolveSelectedItem(selectedWidgetId, widgetItems)

    function resolveSelectedItem(selectedId, items) {
        if (!selectedId) {
            return null
        }
        for (let i = 0; i < items.length; ++i) {
            // Repeater 自身など widgetId を持たない子は除外する。
            if (items[i] && items[i].widgetId === selectedId) {
                return items[i]
            }
        }
        return null
    }

    // Task 18: 新規 Widget 追加用の単調増加カウンタ（実用上の最大連番）。
    // 初期 widgetModel に btn001 が含まれているので 1 から始める。Main.qml の
    // Open で widgetModel が差し替わった場合に備え、`addWidget()` は採番前に
    // 必ず現在の widgetModel を走査して max ID と比較し、大きい方の次を採用する
    // （Codex Task 18 P1 指摘）。
    property int widgetIdCounter: 1

    // Task 26: 現在 live な EditableWidget 群から widgetModel 互換の配列を
    // 生成する（= 編集中の真実である live Item を配列へスナップショット）。
    // widgetModel（var 配列）は in-place 変更でバインディング通知が出ないため、
    // 構造変更（追加 / 削除）時はこの関数で **インスペクタ編集やドラッグ位置を
    // 含む現在値** を取り込んでから再代入する。これをせず古い widgetModel を
    // 直接 concat すると、Repeater 再生成で未保存の編集が古い値へ戻る
    // （Codex PR #52 P2 指摘）。Main.qml の保存経路（saveTo / onAccepted）も
    // 同じ走査をしていたため本関数に集約して共用する。
    function snapshotModel() {
        const items = widgetItems
        const result = []
        for (let i = 0; i < items.length; ++i) {
            const item = items[i]
            // Repeater 自身など widgetId を持たない子はスキップ
            if (item.widgetId === undefined) {
                continue
            }
            result.push({
                id: item.widgetId,
                type: item.widgetType,
                x: Math.round(item.x),
                y: Math.round(item.y),
                width: Math.round(item.width),
                height: Math.round(item.height),
                text: item.widgetText,
                tag: item.widgetTag,
                // Task 28: スタイル属性も live Item からスナップショットして保存に乗せる。
                backgroundColor: item.widgetBackgroundColor,
                textColor: item.widgetTextColor,
                fontSize: item.widgetFontSize,
                // Task 31: ボーダー＋角丸も live Item から取り込む（-1 = 未指定）。
                borderColor: item.widgetBorderColor,
                borderWidth: item.widgetBorderWidth,
                radius: item.widgetRadius,
                // Task 33: フォント詳細も live Item から取り込む（bool / 空文字 = 未指定）。
                fontBold: item.widgetFontBold,
                fontItalic: item.widgetFontItalic,
                fontFamily: item.widgetFontFamily
            })
        }
        return result
    }

    // Task 18: 既定サイズ/位置で Widget を 1 個追加する。Main.qml の追加
    // ボタンから呼ばれる。E2E（Spix）からは追加ボタンの mouseClick 経由で
    // 同じパスを通る。
    function addWidget() {
        // Task 26: 古い widgetModel を直接 concat せず、現在の live Item 群を
        // スナップショットしてから追加する。これによりインスペクタでの未保存
        // 編集（text/tag）やドラッグ後の位置が、追加に伴う Repeater 再生成で
        // 巻き戻らない（Codex PR #52 指摘）。
        const snapshot = snapshotModel()

        // 既存 id（live Item 由来）から btnNNN 形式の最大連番を走査し、
        // カウンタと比較する。読込で外部 JSON が入った後の追加でも ID が
        // 衝突しないよう保つ。
        let maxFound = widgetIdCounter
        for (let i = 0; i < snapshot.length; ++i) {
            const existingId = snapshot[i].id
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
        snapshot.push(newWidget)
        // 新しい配列を代入することで Repeater に確実にモデル変更を通知する。
        widgetModel = snapshot
    }

    // Task 29: 選択中（または指定 id）の Widget を削除する。addWidget() と対称で、
    // 構造変更（削除）なので live Item 群をスナップショット → 該当 id を除いた配列を
    // 再代入して Repeater をリトリガする（var 配列据え置き＝Phase 4 設計指針）。
    // これにより未保存の他 widget の編集（text/座標/スタイル）が巻き戻らない。
    // 削除後は選択を解除（selectedWidgetId = ""）し、selectedItem も null に解決される。
    // 引数省略時は現在の選択 id を対象にする。Main.qml の削除ボタンから呼ばれる。
    function deleteWidget(targetId) {
        const id = (targetId !== undefined && targetId !== "")
            ? targetId : selectedWidgetId
        if (!id) {
            return
        }
        const snapshot = snapshotModel()
        const next = []
        for (let i = 0; i < snapshot.length; ++i) {
            if (snapshot[i].id !== id) {
                next.push(snapshot[i])
            }
        }
        // 削除対象が選択中なら選択を解除する。先に解除しておくことで、
        // 配列再代入に伴う Repeater 再生成中も破棄済み Item を掴まない。
        if (selectedWidgetId === id) {
            selectedWidgetId = ""
        }
        widgetModel = next
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

        // Task 25: 背景クリックで選択解除。widgetLayer より前に宣言することで
        // 後続の widgetLayer（Widget 群）が上に重なり、Widget 上のクリックは
        // 各 HmiButton の MouseArea が消費する。空きキャンバスへのクリックだけが
        // ここまで落ちてきて選択を解除する。
        MouseArea {
            id: backgroundClickArea
            anchors.fill: parent
            onClicked: root.selectedWidgetId = ""
        }

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
                    // Task 28: スタイル属性を modelData → wrapper メタへ流す（未指定は空 / 0）。
                    widgetBackgroundColor: modelData.backgroundColor !== undefined ? modelData.backgroundColor : ""
                    widgetTextColor: modelData.textColor !== undefined ? modelData.textColor : ""
                    widgetFontSize: modelData.fontSize !== undefined ? modelData.fontSize : 0
                    // Task 31: ボーダー＋角丸も流す（未指定は空 / -1。0 は正当値なので -1 を既定にする）。
                    widgetBorderColor: modelData.borderColor !== undefined ? modelData.borderColor : ""
                    widgetBorderWidth: modelData.borderWidth !== undefined ? modelData.borderWidth : -1
                    widgetRadius: modelData.radius !== undefined ? modelData.radius : -1
                    // Task 33: フォント詳細を流す（未指定は false / 空文字）。
                    widgetFontBold: modelData.fontBold !== undefined ? modelData.fontBold : false
                    widgetFontItalic: modelData.fontItalic !== undefined ? modelData.fontItalic : false
                    widgetFontFamily: modelData.fontFamily !== undefined ? modelData.fontFamily : ""
                    // Task 18: Spix から `widget_<id>` で参照できるようにする。
                    objectName: "widget_" + widgetId
                    x: modelData.x !== undefined ? modelData.x : 0
                    y: modelData.y !== undefined ? modelData.y : 0
                    width: modelData.width !== undefined ? modelData.width : 120
                    height: modelData.height !== undefined ? modelData.height : 40

                    // Task 25: 選択状態の結線。EditableWidget からは Canvas の id
                    // （root）が見えないため、可視な delegate 側で双方向を結ぶ：
                    //  - 自分が選択中かを selectedWidgetId との一致で受け取る
                    //  - クリックされたら selectRequested 経由で selectedWidgetId を更新
                    selected: wrapper.widgetId === root.selectedWidgetId
                    onSelectRequested: function(requestedId) {
                        root.selectedWidgetId = requestedId
                    }

                    // 現状 MVP は Button のみ。型分岐は将来 Widget 種別が増えた時に拡張。
                    HmiButton {
                        anchors.fill: parent
                        // EditableWidget の content alias は内部 container を指すため、
                        // parent 経由ではなく wrapper の id 経由でメタを参照する
                        // （CLAUDE.md の "default property alias の parent 罠" 参照）。
                        text: wrapper.widgetText
                        tag: wrapper.widgetTag
                        // Task 28: スタイル属性を HmiButton（唯一の真実）へ渡す。
                        // 空 / 0 は HmiButton 側で既定外観にフォールバックされる。
                        backgroundColor: wrapper.widgetBackgroundColor
                        textColor: wrapper.widgetTextColor
                        fontSize: wrapper.widgetFontSize
                        // Task 31: ボーダー＋角丸を渡す。角丸は widgetRadius → cornerRadius に
                        // マップする（HmiButton の公開入力名は radius 衝突回避で cornerRadius）。
                        // 空 / -1 は HmiButton 側で既定外観にフォールバックされる。
                        borderColor: wrapper.widgetBorderColor
                        borderWidth: wrapper.widgetBorderWidth
                        cornerRadius: wrapper.widgetRadius
                        // Task 33: フォント詳細を HmiButton へ渡す（空 / false は既定にフォールバック）。
                        fontBold: wrapper.widgetFontBold
                        fontItalic: wrapper.widgetFontItalic
                        fontFamily: wrapper.widgetFontFamily
                        // Task 25: ドラッグ用の親 MouseArea は drag.filterChildren 下で
                        // クリックを発火しない（子が消費する）。よってクリック検出は
                        // HmiButton 側の clicked を中継して選択要求に使う。
                        onClicked: wrapper.selectRequested(wrapper.widgetId)
                    }
                }
            }
        }
    }
}
