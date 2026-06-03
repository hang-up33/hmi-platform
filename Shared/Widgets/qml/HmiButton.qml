import QtQuick

// 共有 Button Widget。
// QtQuick.Controls の Button との命名衝突を避けるためプレフィックス命名（CLAUDE.md 規約）。
// QtQuick だけで完結させ、Yocto / i.MX8MP 上の軽量実行を意識して Controls には依存しない。
//
// 将来 Shared/Schema の WidgetData (type="Button") からインスタンス化されることを想定し、
// 公開プロパティは text / tag に加え、Task 28 でスタイル（背景色 / 文字色 / 文字サイズ）を持つ。
//
// Task 28: スタイルの既定外観は **この HmiButton だけが持つ唯一の真実**。
// 公開入力（backgroundColor / textColor / fontSize）は空文字 / 0 を「未指定」とみなし、
// resolved* で既定値にフォールバックする。これにより Editor / Simulator の delegate は
// モデル値（空可）をそのまま渡すだけでよく、既定値を各 delegate に二重定義しなくて済む。
// 旧 JSON（スタイル省略）も従来と同じ見た目で描画される（後方互換）。
Rectangle {
    id: root

    property string text: "Button"
    property string tag: ""

    // Task 28: スタイル入力。色は "#RRGGBB"（空 = 未指定）、fontSize は px（0 = 未指定）。
    property string backgroundColor: ""
    property string textColor: ""
    property int fontSize: 0

    // 未指定（空 / 0）のときの既定外観。プロジェクト全体でここだけが既定値を持つ。
    readonly property color resolvedBackgroundColor: backgroundColor !== "" ? backgroundColor : "#4cc9f0"
    readonly property color resolvedTextColor: textColor !== "" ? textColor : "white"
    readonly property int resolvedFontSize: fontSize > 0 ? fontSize : 14

    signal clicked()

    width: 120
    height: 40
    radius: 4
    // press フィードバックは背景色から Qt.darker で導出する（個別の press 色を持たない）。
    color: mouseArea.pressed ? Qt.darker(root.resolvedBackgroundColor, 1.2)
                             : root.resolvedBackgroundColor
    border.color: "#1d3557"
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.resolvedTextColor
        font.pixelSize: root.resolvedFontSize
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
