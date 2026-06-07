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

    // Task 31: ボーダー＋角丸の入力。色は "#RRGGBB"（空 = 未指定）。
    // 数値は **`-1` = 未指定**（borderWidth=0 / cornerRadius=0 は「ボーダー / 角丸なし」の
    // 正当値なので 0 を未指定に使えない。Schema の -1 センチネルと揃える）。
    // root は Rectangle で `radius` は組込みプロパティのため、角丸の公開入力は
    // **`cornerRadius`** に改名して衝突を避け、下で `radius:` へ割り当てる。
    property string borderColor: ""
    property int borderWidth: -1
    property int cornerRadius: -1

    // Task 33: フォント詳細の入力。bold/italic は bool（既定 false = 太字/斜体なし）。
    // fontFamily は空文字 = 未指定（システム既定フォント）。bool は false 自体が
    // 「指定なし」と一致するため -1 のようなセンチネルは不要で素直に渡せる。
    property bool fontBold: false
    property bool fontItalic: false
    property string fontFamily: ""

    // Task 33: 未指定（空）のときの既定フォント。**空文字を font.family に直接束縛
    // してはいけない**：Qt/macOS では空 family が記号フォント等へ化け、テキストが
    // 文字化けした（実機確認。bold/italic 指定時はたまたま解決されたが既定時に破綻）。
    // 既定はアプリの既定フォント（Qt.application.font.family）にフォールバックし、
    // 既定外観の単一ソースとして他の resolved* と揃える。
    readonly property string resolvedFontFamily: fontFamily !== "" ? fontFamily
                                                                   : Qt.application.font.family

    // 未指定（空 / 0）のときの既定外観。プロジェクト全体でここだけが既定値を持つ。
    readonly property color resolvedBackgroundColor: backgroundColor !== "" ? backgroundColor : "#4cc9f0"
    readonly property color resolvedTextColor: textColor !== "" ? textColor : "white"
    readonly property int resolvedFontSize: fontSize > 0 ? fontSize : 14

    // Task 31: 未指定（空 / `< 0`）のときの既定ボーダー＋角丸。従来ハードコードしていた
    // `#1d3557` / 1 / 4 をここへ移し、既定値の単一ソースにする。
    readonly property color resolvedBorderColor: borderColor !== "" ? borderColor : "#1d3557"
    readonly property int resolvedBorderWidth: borderWidth >= 0 ? borderWidth : 1
    readonly property int resolvedCornerRadius: cornerRadius >= 0 ? cornerRadius : 4

    signal clicked()

    width: 120
    height: 40
    // Task 31: 角丸・ボーダーは resolved*（HmiButton 1 箇所に集約した既定値）を参照する。
    radius: root.resolvedCornerRadius
    // press フィードバックは背景色から Qt.darker で導出する（個別の press 色を持たない）。
    color: mouseArea.pressed ? Qt.darker(root.resolvedBackgroundColor, 1.2)
                             : root.resolvedBackgroundColor
    border.color: root.resolvedBorderColor
    border.width: root.resolvedBorderWidth

    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.resolvedTextColor
        font.pixelSize: root.resolvedFontSize
        // Task 33: フォント詳細。bold/italic は bool をそのまま反映（既定 false）。
        // family は空文字のときシステム既定フォントになる（未指定のフォールバック）。
        font.bold: root.fontBold
        font.italic: root.fontItalic
        font.family: root.resolvedFontFamily
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
