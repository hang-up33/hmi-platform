import QtQuick
import QtQuick.Controls

// Task RF-G: InspectorPanel.qml のインラインコンポーネントだった色スウォッチを
// セクション分割に合わせて別ファイル化した（見た目・挙動は不変）。
// Task 46: hex TextField の隣に置く色スウォッチ（現在色のプレビュー兼
// ColorDialog の起動ボタン）。3 つの色フィールド（背景 / 文字 / ボーダー）で
// 使い回す。field の hex が妥当ならその色、
// 空・編集途中は fallback（HmiButton の resolved* 既定色 = 実際の描画色）を見せる。
Rectangle {
    id: swatch
    // InspectorPanel（スウォッチの一辺・ColorDialog 起動元の editorRoot を引く）。
    property var inspector: null
    // 連動する hex TextField（現在色の参照元・ColorDialog の書き戻し先）。
    property var field: null
    // 選択中 live Item へ書き戻すプロパティ名（"widgetBackgroundColor" 等）。
    property string targetProperty: ""
    // 未指定（空文字）のとき見せる既定色。HmiButton の resolved* と揃える。
    property color fallback: "white"

    width: inspector ? inspector.colorSwatchSize : 28
    height: width
    radius: 4
    border.color: "#999999"
    border.width: 1
    color: (field && field.text !== "" && field.acceptableInput)
        ? field.text : fallback

    ToolTip.text: qsTr("クリックで色を選択")
    ToolTip.visible: swatchArea.containsMouse
    ToolTip.delay: 600

    MouseArea {
        id: swatchArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: inspector.editorRoot.openColorDialog(
            swatch.field, swatch.targetProperty, swatch.fallback)
    }
}
