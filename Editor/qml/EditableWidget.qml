import QtQuick

// Editor 専用の編集ラッパー。
// 子要素をドラッグで動かせるようにし、自身（このItem）の x / y を更新する。
// HmiButton 等の共有 Widget は描画責務だけを持ち、ドラッグ等の編集操作はこちらに集約する。
// Simulator では使わない（Simulator は読み取り専用のため）。
//
// 構造のキモは MouseArea を子要素（container）の親階層に置き、
// `drag.filterChildren: true` を立てること。これにより、
//   1) 子の MouseArea（HmiButton 内の clicked / pressed）にまずイベントが届く
//   2) しきい値を超えるマウス移動を検出した時点で親 MouseArea が drag を発動して
//      イベントを奪う
// という Qt 標準の作法で、クリックとドラッグを両立できる。
//
// QML ファイル名は QtQuick 標準型と衝突しないことを CLAUDE.md で要請されており、
// "EditableWidget" は標準型に存在しないため安全。
Item {
    id: root

    // 子要素は container に直接配置される。Main.qml では HmiButton 1 個を入れて使う。
    default property alias content: container.data

    // ドラッグ中かどうか（将来：選択ハンドルや座標表示の切替に使う想定）
    readonly property bool dragging: dragArea.drag.active

    // Shared/Schema の WidgetData に書き出すためのメタ情報。
    // Task 6（JSON 保存）で参照する。子の HmiButton 等はこの値をバインディングで参照する。
    property string widgetId: ""
    property string widgetType: "Button"
    property string widgetText: ""
    property string widgetTag: ""

    // Task 25: 選択状態。値の所有は Canvas（root.selectedWidgetId）にあり、
    // この EditableWidget は「選ばれているか」を受け取って選択枠を描画するだけ
    // （plain な bool プロパティ）。結線は delegate 側（Canvas.qml）で
    // `selected: widgetId === root.selectedWidgetId` とバインドする。
    property bool selected: false

    // Task 25: クリックされて「選択して欲しい」要求を外へ伝えるシグナル。
    // QML の id はコンポーネントファイルを跨いで参照できないため、
    // EditableWidget から Canvas を直接触らず、このシグナル経由で結線する。
    // 引数名は QML 予約語 `id` / 既存プロパティ `widgetId` との衝突を避けて
    // `requestedId` とする。
    signal selectRequested(string requestedId)

    MouseArea {
        id: dragArea
        anchors.fill: parent
        drag.target: root
        drag.axis: Drag.XAndYAxis
        // 子（HmiButton 等）の MouseArea にイベントを先に渡しつつ、
        // ドラッグ閾値を超えたら親がイベントを奪う。これがないと
        // 子 Widget の clicked / pressed が常に発火しない。
        drag.filterChildren: true
        // 親（Canvas の widgetLayer）の外に出ないようクランプ
        drag.minimumX: 0
        drag.minimumY: 0
        drag.maximumX: root.parent ? root.parent.width - root.width : 0
        drag.maximumY: root.parent ? root.parent.height - root.height : 0
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        Item {
            id: container
            anchors.fill: parent
        }
    }

    // Task 25: 選択枠。selected 時のみ表示する。
    // dragArea より後に宣言して最前面へ重ね、内容（HmiButton）の上に枠を描く。
    // MouseArea を持たないためマウスイベントは透過し、ドラッグ/クリックを妨げない。
    // 負マージンで Widget をわずかに囲み、ボタン自身の境界線と重ならないようにする。
    Rectangle {
        id: selectionFrame
        anchors.fill: parent
        anchors.margins: -2
        visible: root.selected
        color: "transparent"
        radius: 4
        border.color: "#ff5d8f"
        border.width: 2
    }
}
