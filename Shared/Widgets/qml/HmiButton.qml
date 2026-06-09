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

    // Task 34: テキスト配置の入力。enum を人間可読な **文字列**で受ける
    // （hAlign: "left"/"center"/"right"、vAlign: "top"/"middle"/"bottom"。空 = 未指定）。
    // 下の resolvedHAlign / resolvedVAlign で `Text.horizontalAlignment` 等の enum へ
    // マッピングする（不正値・空は中央＝既定にフォールバック）。
    property string hAlign: ""
    property string vAlign: ""

    // Task 34: 不透明度の入力。**`Item.opacity` 組込みと名前衝突するため公開入力は
    // `widgetOpacity`** にする（root は Rectangle = Item 派生で `opacity` は組込み。
    // T31 の `radius`→`cornerRadius` と同型の回避）。`-1` をセンチネル（未指定）にし、
    // 下の resolvedOpacity（`< 0`→1.0）を導出して組込み `opacity:` へ割り当てる。
    // `0.0`（完全透明）が正当値のため 0 を未指定に使えず -1 センチネルにする（borderWidth 同様）。
    property real widgetOpacity: -1

    // Task 42: 状態別スタイル。**`enabled` は `Item.enabled` 組込みと衝突するため公開入力は
    // `widgetEnabled`**（widgetOpacity と同型の回避）。false で淡色表示にする。
    // クリック自体は MouseArea を止めず（Editor の選択が clicked 経由のため）、実行（アクション）
    // 側で無効化する＝SimulatorCanvas.runClickActions が enabled を見る。
    // checkable / checked は `Item` に同名組込みが無いためそのまま公開できる。checked かつ
    // checkable のとき「押下中」風のトグル外観（背景を暗く + ボーダーを太く）にする。
    property bool widgetEnabled: true
    property bool checkable: false
    property bool checked: false

    // Task 34: 配置文字列 → Text の enum へのマッピング。空・不正値は中央寄せにフォールバック
    // （既定外観の単一ソースとして他の resolved* と揃える）。
    readonly property int resolvedHAlign: hAlign === "left" ? Text.AlignLeft
                                        : hAlign === "right" ? Text.AlignRight
                                        : Text.AlignHCenter
    readonly property int resolvedVAlign: vAlign === "top" ? Text.AlignTop
                                        : vAlign === "bottom" ? Text.AlignBottom
                                        : Text.AlignVCenter
    // Task 34: 未指定（`< 0`）のとき不透明度 1.0（完全不透明）にフォールバック。
    readonly property real resolvedOpacity: widgetOpacity >= 0 ? widgetOpacity : 1.0

    // 未指定（空 / 0）のときの既定外観。プロジェクト全体でここだけが既定値を持つ。
    readonly property color resolvedBackgroundColor: backgroundColor !== "" ? backgroundColor : "#4cc9f0"
    readonly property color resolvedTextColor: textColor !== "" ? textColor : "white"
    readonly property int resolvedFontSize: fontSize > 0 ? fontSize : 14

    // Task 31: 未指定（空 / `< 0`）のときの既定ボーダー＋角丸。従来ハードコードしていた
    // `#1d3557` / 1 / 4 をここへ移し、既定値の単一ソースにする。
    readonly property color resolvedBorderColor: borderColor !== "" ? borderColor : "#1d3557"
    readonly property int resolvedBorderWidth: borderWidth >= 0 ? borderWidth : 1
    readonly property int resolvedCornerRadius: cornerRadius >= 0 ? cornerRadius : 4

    // Task 36: クリックを通知する。Editor の複数選択（Shift / Ctrl クリックで加除）の
    // ため、押下時のキーボード modifiers を引数で渡す。Simulator は clicked に接続して
    // いないため影響なし（引数を無視する接続は従来どおり動く）。
    signal clicked(int modifiers)

    width: 120
    height: 40
    // Task 34: 不透明度は組込み `opacity` へ resolvedOpacity（未指定→1.0）を割り当てる。
    // 公開入力 widgetOpacity と組込み opacity を分けることで、未指定 Button が透明化する
    // 事故（-1 を組込み opacity に直接入れると起きる）を防ぐ。
    // Task 42: disabled（widgetEnabled=false）のとき淡色（0.4 倍）にする。
    opacity: root.resolvedOpacity * (root.widgetEnabled ? 1.0 : 0.4)
    // Task 31: 角丸・ボーダーは resolved*（HmiButton 1 箇所に集約した既定値）を参照する。
    radius: root.resolvedCornerRadius
    // press フィードバックは背景色から Qt.darker で導出する（個別の press 色を持たない）。
    // Task 42: ①disabled のときは press 暗転しない ②checked（トグル ON）のとき押下風に暗く。
    color: (mouseArea.pressed && root.widgetEnabled)
                ? Qt.darker(root.resolvedBackgroundColor, 1.2)
         : (root.checkable && root.checked)
                ? Qt.darker(root.resolvedBackgroundColor, 1.15)
         : root.resolvedBackgroundColor
    border.color: root.resolvedBorderColor
    // Task 42: checked（トグル ON）のときボーダーを太くして「押し込まれている」感を出す。
    border.width: root.resolvedBorderWidth + ((root.checkable && root.checked) ? 2 : 0)

    Text {
        // Task 34: 配置を効かせるため `anchors.centerIn` をやめ `anchors.fill` にして
        // Text の領域を Button 全体に広げ、horizontalAlignment / verticalAlignment で
        // テキストを寄せる（未指定は resolvedHAlign/VAlign で中央＝従来の見た目に一致）。
        anchors.fill: parent
        anchors.margins: 4
        text: root.text
        color: root.resolvedTextColor
        font.pixelSize: root.resolvedFontSize
        // Task 33: フォント詳細。bold/italic は bool をそのまま反映（既定 false）。
        // family は空文字のときシステム既定フォントになる（未指定のフォールバック）。
        font.bold: root.fontBold
        font.italic: root.fontItalic
        font.family: root.resolvedFontFamily
        // Task 34: 配置（文字列 → enum を resolved* でマップ。空・不正値は中央）。
        horizontalAlignment: root.resolvedHAlign
        verticalAlignment: root.resolvedVAlign
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: function(mouse) { root.clicked(mouse.modifiers) }
    }
}
