import QtQuick

// 共有 Button Widget。
// QtQuick.Controls の Button との命名衝突を避けるためプレフィックス命名（CLAUDE.md 規約）。
// QtQuick だけで完結させ、Yocto / i.MX8MP 上の軽量実行を意識して Controls には依存しない。
//
// 将来 Shared/Schema の WidgetData (type="Button") からインスタンス化されることを想定し、
// 公開プロパティは text / tag の 2 つに揃えている（座標・サイズは Item のデフォルトを利用）。
Rectangle {
    id: root

    property string text: "Button"
    property string tag: ""

    signal clicked()

    width: 120
    height: 40
    radius: 4
    color: mouseArea.pressed ? "#3a86ff" : "#4cc9f0"
    border.color: "#1d3557"
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: root.text
        color: "white"
        font.pixelSize: 14
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
