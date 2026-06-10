import QtQuick
import QtQuick.Controls

// Task 44: インスペクタの折りたたみ可能なセクション。ヘッダ（タイトル + ▼/▶）を
// クリックすると開閉し、子要素は内部の content Column へ流し込まれる。Phase 4 で
// 平坦に積み上がったインスペクタ項目をグループ化し、関連プロパティを集約する。
//
// 使い方：
//   InspectorSection {
//       title: qsTr("基本")
//       // ここに置いた子要素が content に入る（parent は内部 content Column を指す）
//       Label { text: qsTr("Text") }
//       TextField { width: parent.width; ... }
//   }
//
// 注意（[[qml-module-conventions]]）：`default property alias content` で受けた子の
// `parent` は内部 content を指す。子で `width: parent.width` と書けば content の幅
// （= セクション幅 = インスペクタ可用幅）に追従する。
Column {
    id: section

    // セクション見出し（ヘッダに太字で表示）。
    property alias title: titleLabel.text
    // 開閉状態。既定は開。詳細セクション等は `expanded: false` で閉じて始める。
    property bool expanded: true
    // 子要素の流し込み先（既定プロパティ）。
    default property alias content: contentColumn.data

    width: parent ? parent.width : implicitWidth
    spacing: 6

    // ヘッダ（クリックで開閉）。
    Rectangle {
        width: parent.width
        height: headerRow.implicitHeight + 10
        color: "#ececec"
        radius: 3

        Row {
            id: headerRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            spacing: 6

            Label {
                // ▼ = 開, ▶ = 閉。
                text: section.expanded ? "▼" : "▶"
                color: "#555555"
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                id: titleLabel
                font.bold: true
                color: "#555555"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: section.expanded = !section.expanded
        }
    }

    // 中身。折りたたみ時は visible:false（Column ポジショナは非表示の子を詰めるため
    // セクションごと高さ 0 になる）。Connections 等の非ビジュアル要素もここに入れて
    // よい（visible は描画のみに影響し、インスタンス化・バインディングは維持される）。
    Column {
        id: contentColumn
        width: parent.width
        spacing: 8
        visible: section.expanded
        // 左に少しインデントしてヘッダとの階層を視覚化する。
        leftPadding: 4
    }
}
