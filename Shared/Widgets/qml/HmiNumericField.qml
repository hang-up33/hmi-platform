import QtQuick
import QtQuick.Controls

// Task 50: 共有 NumericField Widget（数値入力）。Phase 6 の最初の **入力 Widget**。
//
// HmiButton / HmiLabel と同じ **resolved\* フォールバック方式**（未指定値を Widget 側で
// 既定へ解決＝既定外観の単一ソース）を踏襲しつつ、内部実装に **QtQuick.Controls の
// `TextField` + `IntValidator`** を使う初の Widget（Shared/Widgets が初めて
// QtQuick.Controls に依存。import のみで動く＝CMake 明示リンク不要）。
//
// SpinBox ではなく TextField + IntValidator を使う（editable SpinBox の表示更新バグ回避＝
// Task 27 の教訓）。背景・枠は TextField の `background:` を Rectangle に差し替えて
// resolved な背景色・ボーダーを当てる。
//
// Button と違い以下を持たない：checkable / checked（状態トグル＝Button 専用）・
// クリックアクション（書きは入力確定で行う＝Task 51）。
//
// 読み書きの役割分担（Phase 6 設計指針）：
//   - 読み（表示）：delegate が boundValue("value") で変数値を text に流す（Task 50 でやる）
//   - 書き（入力確定）：commitValue() が valueCommitted(text) を emit し、delegate が
//     変数へ書き戻す（**結線は Task 51**。Task 50 では HmiNumericField 側に口だけ用意）。
//
// editable で Editor / Simulator を出し分ける（Button/Label の選択中継と一様化）：
//   - Editor キャンバス（editable:false）：TextField を readOnly + activeFocusOnPress:false に
//     して入力を奪わせず、上に重ねた選択用 MouseArea を enabled:true にして clicked を中継。
//   - Simulator/Runtime（editable:true）：TextField が入力を受ける。選択用 MouseArea は
//     enabled:false（Simulator は clicked を選択に使わない）。
Rectangle {
    id: root

    // 表示テキスト（数値の文字列表現）。delegate が静的値 / 変数追従値を流す。
    property string text: "0"

    // 入力可否。既定 true（Simulator）。Editor では false にして読取専用表示にする。
    property bool editable: true

    // スタイル入力。色は "#RRGGBB"（空 = 未指定）、fontSize は px（0 = 未指定）。
    // HmiButton / HmiLabel と同じく「未指定 = 空文字 / 0」を許し resolved* で既定へ。
    property string backgroundColor: ""
    property string textColor: ""
    property int fontSize: 0

    // ボーダー＋角丸。色は "#RRGGBB"（空 = 未指定）。数値は **`-1` = 未指定**
    // （0 は「ボーダー / 角丸なし」の正当値なので 0 を未指定に使えない。HmiButton と同型）。
    property string borderColor: ""
    property int borderWidth: -1
    property int cornerRadius: -1

    // フォント詳細。bold/italic は bool（既定 false）。fontFamily は空文字 = 未指定。
    property bool fontBold: false
    property bool fontItalic: false
    property string fontFamily: ""

    // テキスト配置（hAlign: "left"/"center"/"right"、vAlign: "top"/"middle"/"bottom"。空 = 未指定）。
    property string hAlign: ""
    property string vAlign: ""

    // 不透明度の入力。`Item.opacity` 組込みと衝突するため公開入力は `widgetOpacity`
    // （HmiButton / HmiLabel と同型の回避）。`-1` をセンチネル（未指定）にする。
    property real widgetOpacity: -1

    // `enabled` は `Item.enabled` 組込みと衝突するため公開入力は `widgetEnabled`。
    // false で淡色表示にする（Button / Label と同型）。
    property bool widgetEnabled: true

    // 未指定（空 / 0 / -1）のときの既定外観。プロジェクト全体でここだけが NumericField の
    // 既定値を持つ（Button / Label と同じ集約パターン）。
    // **入力欄らしい既定**：背景=白（#ffffff）/ 文字色=濃色（#1d3557、Label と同じ）/
    // 枠=細いグレー（#9aa5b1, 幅 1）/ 角丸=4。Button の鮮やかな塗り / Label の透明とは違う。
    readonly property color resolvedBackgroundColor: backgroundColor !== "" ? backgroundColor : "#ffffff"
    readonly property color resolvedTextColor: textColor !== "" ? textColor : "#1d3557"
    readonly property int resolvedFontSize: fontSize > 0 ? fontSize : 14

    readonly property color resolvedBorderColor: borderColor !== "" ? borderColor : "#9aa5b1"
    readonly property int resolvedBorderWidth: borderWidth >= 0 ? borderWidth : 1
    readonly property int resolvedCornerRadius: cornerRadius >= 0 ? cornerRadius : 4

    // 空文字を font.family に直接束縛すると Qt/macOS で記号フォント等へ化けるため、
    // 未指定時はアプリ既定フォントへフォールバックする（HmiButton / HmiLabel と同じ対処）。
    readonly property string resolvedFontFamily: fontFamily !== "" ? fontFamily
                                                                   : Qt.application.font.family

    // 配置文字列 → enum。**数値入力の既定は右寄せ（hAlign）/ 中央（vAlign）**
    // （数値フィールドの慣習。Button=中央/中央・Label=左/中央 とは別の既定）。
    readonly property int resolvedHAlign: hAlign === "left" ? Text.AlignLeft
                                        : hAlign === "center" ? Text.AlignHCenter
                                        : Text.AlignRight
    readonly property int resolvedVAlign: vAlign === "top" ? Text.AlignTop
                                        : vAlign === "bottom" ? Text.AlignBottom
                                        : Text.AlignVCenter
    // 未指定（`< 0`）のとき不透明度 1.0（完全不透明）にフォールバック。
    readonly property real resolvedOpacity: widgetOpacity >= 0 ? widgetOpacity : 1.0

    // 選択中継用 clicked（Editor の選択に使う。modifiers は複数選択の加除用）。
    // HmiButton / HmiLabel の clicked(int modifiers) と同形。Simulator は接続しない。
    signal clicked(int modifiers)

    // 入力確定の通知。delegate がこれを受けて変数へ write する（**結線は Task 51**）。
    // E2E（Spix）は実テキスト入力を発火できないため commitValue() を invokeMethod で叩く。
    signal valueCommitted(string text)

    // 現在の TextField のテキストで valueCommitted(text) を通知するだけに留める。
    // **root.text は命令的に書き換えない**：Simulator の delegate は text を
    // boundValue("value") にバインドしており、ここで root.text へ代入すると外部 binding が
    // 切れて以後変数に追従しなくなる（CodeRabbit PR #104 指摘）。表示への反映は delegate の
    // write-back（変数更新 → boundValue 再評価）に一本化する（write 結線は Task 51）。
    // TextField.onEditingFinished からも呼ぶ。公開メソッドなので invokeMethod でも叩ける。
    function commitValue() {
        root.valueCommitted(field.text);
    }

    width: 120
    height: 40
    // 不透明度は組込み `opacity` へ resolvedOpacity（未指定→1.0）を割り当てる。
    // disabled（widgetEnabled=false）のとき淡色（0.4 倍）にする（Button / Label と同型）。
    opacity: root.resolvedOpacity * (root.widgetEnabled ? 1.0 : 0.4)
    // root 自体は透明にして、見た目の背景・枠は TextField.background（Rectangle）に持たせる。
    color: "transparent"
    border.width: 0

    TextField {
        id: field
        objectName: "numericTextField"
        anchors.fill: parent
        // editable:false（Editor）では readOnly にして入力を奪わせない。
        readOnly: !root.editable
        activeFocusOnPress: root.editable
        enabled: root.widgetEnabled
        // delegate が流す表示テキスト。activeFocus 中の同期抑止（カーソル飛び対策）は
        // Task 51（write 経路）で扱う。Task 50 は読み取り表示のみ。
        text: root.text
        // 数値のみ許可（int）。MVP は int 変数のみ（real / min-max は別承認）。
        validator: IntValidator {}
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        color: root.resolvedTextColor
        font.pixelSize: root.resolvedFontSize
        font.bold: root.fontBold
        font.italic: root.fontItalic
        font.family: root.resolvedFontFamily
        horizontalAlignment: root.resolvedHAlign
        verticalAlignment: root.resolvedVAlign
        leftPadding: 6
        rightPadding: 6
        topPadding: 0
        bottomPadding: 0

        // 背景・枠は resolved* を当てた Rectangle に差し替える（Controls の既定枠を使わない）。
        background: Rectangle {
            color: root.resolvedBackgroundColor
            radius: root.resolvedCornerRadius
            border.color: root.resolvedBorderColor
            border.width: root.resolvedBorderWidth
        }

        // 入力確定（Enter / フォーカス喪失）で commitValue() を呼ぶ。delegate が
        // valueCommitted を受けて変数へ書く（結線は Task 51）。
        onEditingFinished: root.commitValue()
    }

    // 選択用 MouseArea。TextField の **上** に重ね、editable:false（Editor）のときだけ
    // enabled にして clicked を中継する（TextField がフォーカス / 入力を奪う罠への対処）。
    // editable:true（Simulator）では無効化し TextField が入力を受ける。
    MouseArea {
        id: selectArea
        objectName: "numericSelectArea"
        anchors.fill: parent
        enabled: !root.editable
        onClicked: function(mouse) { root.clicked(mouse.modifiers) }
    }
}
