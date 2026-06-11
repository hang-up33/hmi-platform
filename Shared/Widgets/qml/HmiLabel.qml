import QtQuick

// Task 47: 共有 Label Widget（表示専用）。Phase 5 横展開の最初の新 Widget 種別。
//
// QtQuick.Controls の Label との命名衝突を避けるためプレフィックス命名（CLAUDE.md 規約）。
// QtQuick だけで完結させ、Yocto / i.MX8MP 上の軽量実行を意識して Controls には依存しない。
//
// HmiButton と同じ **resolved\* フォールバック方式**（未指定値を Widget 側で既定へ解決）を
// 踏襲した、文字表示に絞った Widget。Button と違い以下を持たない：
//   - ボーダー（borderColor / borderWidth / cornerRadius）：Label の既定はフラット
//   - checkable / checked（状態トグル＝対話 Button 専用）
//   - クリックアクション実行（runClickActions）：Label は表示専用
//
// 既定値（resolved\*）は HmiLabel に集約する（Button と同じ思想）。Button と違う既定：
//   - 背景 = **透明**（backgroundColor:"" → "transparent"）
//   - ボーダー無し
//   - textColor 既定は可読性のため濃色（#1d3557）
//   - hAlign 既定は **左寄せ**（ラベルらしさ。未指定 "" → Text.AlignLeft）
//
// binding（変数追従）は text / textColor / visible / backgroundColor を対象に Simulator 側
// delegate で結線する（HmiLabel 自体は静的に描くだけで、追従ロジックは delegate に閉じる）。
// 選択用 `signal clicked(int modifiers)` + MouseArea を持ち、Editor の選択中継に使う
// （Simulator では action へ繋がない＝表示専用）。HmiButton の clicked(int modifiers) と同形。
Rectangle {
    id: root

    property string text: "Label"

    // スタイル入力。色は "#RRGGBB"（空 = 未指定）、fontSize は px（0 = 未指定）。
    // HmiButton と同じく「未指定 = 空文字 / 0」を許し、resolved* で既定へフォールバックする。
    property string backgroundColor: ""
    property string textColor: ""
    property int fontSize: 0

    // フォント詳細。bold/italic は bool（既定 false = 太字/斜体なし）。
    // fontFamily は空文字 = 未指定（システム既定フォント）。
    property bool fontBold: false
    property bool fontItalic: false
    property string fontFamily: ""

    // テキスト配置。enum を人間可読な文字列で受ける
    // （hAlign: "left"/"center"/"right"、vAlign: "top"/"middle"/"bottom"。空 = 未指定）。
    property string hAlign: ""
    property string vAlign: ""

    // 不透明度の入力。**`Item.opacity` 組込みと名前衝突するため公開入力は `widgetOpacity`**
    // にする（HmiButton と同型の回避）。`-1` をセンチネル（未指定）にし、resolvedOpacity を
    // 導出して組込み `opacity:` へ割り当てる（0.0 が正当値のため 0 を未指定に使えない）。
    property real widgetOpacity: -1

    // **`enabled` は `Item.enabled` 組込みと衝突するため公開入力は `widgetEnabled`**
    // （HmiButton と同型の回避）。false で淡色表示にする。Label は表示専用なので
    // クリック実行は無いが、淡色プレビュー（無効状態の見た目）は揃える。
    property bool widgetEnabled: true

    // 未指定（空 / 0 / 空文字）のときの既定外観。プロジェクト全体でここだけが Label の
    // 既定値を持つ（HmiButton の resolved* と同じ集約パターン）。
    // **背景は透明・文字色は濃色・配置は左寄せ**が HmiButton との既定差分。
    readonly property color resolvedBackgroundColor: backgroundColor !== "" ? backgroundColor : "transparent"
    readonly property color resolvedTextColor: textColor !== "" ? textColor : "#1d3557"
    readonly property int resolvedFontSize: fontSize > 0 ? fontSize : 14

    // 空文字を font.family に直接束縛すると Qt/macOS で記号フォント等へ化けるため、
    // 未指定時はアプリ既定フォントへフォールバックする（HmiButton と同じ対処）。
    readonly property string resolvedFontFamily: fontFamily !== "" ? fontFamily
                                                                   : Qt.application.font.family

    // 配置文字列 → Text の enum へのマッピング。**Label の既定は左寄せ（hAlign）/ 中央（vAlign）**。
    // 空・不正値は既定へフォールバック（既定外観の単一ソース）。
    readonly property int resolvedHAlign: hAlign === "center" ? Text.AlignHCenter
                                        : hAlign === "right" ? Text.AlignRight
                                        : Text.AlignLeft
    readonly property int resolvedVAlign: vAlign === "top" ? Text.AlignTop
                                        : vAlign === "bottom" ? Text.AlignBottom
                                        : Text.AlignVCenter
    // 未指定（`< 0`）のとき不透明度 1.0（完全不透明）にフォールバック。
    readonly property real resolvedOpacity: widgetOpacity >= 0 ? widgetOpacity : 1.0

    // クリックを通知する（Editor の選択中継に使う。modifiers は複数選択の加除用）。
    // HmiButton.clicked(int modifiers) と同形。Simulator は接続しない＝表示専用。
    signal clicked(int modifiers)

    width: 120
    height: 40
    // 不透明度は組込み `opacity` へ resolvedOpacity（未指定→1.0）を割り当てる。
    // disabled（widgetEnabled=false）のとき淡色（0.4 倍）にする（HmiButton と同型）。
    opacity: root.resolvedOpacity * (root.widgetEnabled ? 1.0 : 0.4)
    color: root.resolvedBackgroundColor
    // Label の既定はフラット（ボーダーなし）。背景が透明なら枠も見えない。
    border.width: 0

    Text {
        // 配置を効かせるため `anchors.fill` にして Text の領域を Label 全体へ広げ、
        // horizontalAlignment / verticalAlignment で寄せる（HmiButton と同じ）。
        anchors.fill: parent
        anchors.margins: 4
        text: root.text
        color: root.resolvedTextColor
        font.pixelSize: root.resolvedFontSize
        font.bold: root.fontBold
        font.italic: root.fontItalic
        font.family: root.resolvedFontFamily
        horizontalAlignment: root.resolvedHAlign
        verticalAlignment: root.resolvedVAlign
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: function(mouse) { root.clicked(mouse.modifiers) }
    }
}
