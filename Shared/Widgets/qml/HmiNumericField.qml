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

    // Task 53: bound 変数が real（浮動小数）型なら true。validator を DoubleValidator に切替え、
    // commitValue の正規化を整数丸めなしにする。false（既定 = int）は IntValidator + Math.trunc。
    // Widget 自身は real/int を持たず、delegate が bound 変数型から導出して渡す（plan Phase 6-B）。
    property bool isReal: false

    // Task 54: 数値範囲（入力 clamp 用）。**負値が正当なので数値センチネル不可**＝presence
    // フラグ（hasMin / hasMax）で未指定を表す（WidgetData の hasMinValue / hasMaxValue 由来）。
    // - validator：hasMin / hasMax のときだけ bottom / top を設定する（未指定側は付けない）。
    // - clamp：commitValue の正規化後、範囲外は境界へ丸める（拒否でなく clamp）。
    // 型は real（double 境界）。int 変数では QML 側で IntValidator の bottom/top へ丸めて渡す。
    property real minValue: 0
    property real maxValue: 0
    property bool hasMin: false
    property bool hasMax: false

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

    // 直近 commit した正規化済み値。Enter→blur のように `onEditingFinished` が短時間に
    // 二度発火しても、同じ値の再確定（重複 valueCommitted / 余分な setValue）を抑止する
    // （CodeRabbit PR #105）。フォーカス取得（新しい編集セッション開始）でクリアし、
    // 同じ値を入れ直した場合は改めて確定できるようにする。
    property string _lastCommittedText: ""

    // 現在の TextField のテキストで valueCommitted(text) を通知するだけに留める。
    // **root.text は命令的に書き換えない**：Simulator の delegate は text を
    // boundValue("value") にバインドしており、ここで root.text へ代入すると外部 binding が
    // 切れて以後変数に追従しなくなる（CodeRabbit PR #104 指摘）。表示への反映は delegate の
    // write-back（変数更新 → boundValue 再評価）に一本化する（write 結線は Task 51）。
    // TextField.onEditingFinished からも呼ぶ。公開メソッドなので invokeMethod でも叩ける。
    //
    // 確定値は **ASCII の整数文字列へ正規化**してから emit する：
    // `IntValidator` は Qt の仕様上、既定 locale で **locale 固有の数字・桁区切り**（例 "1,234"、
    // Arabic の "١٢٣"）も受理する。消費側（VariableStore.coerce → parseInt(raw, 10)）はこれらを
    // 誤読する（"1,234"→1 / "١٢٣"→NaN→0）。そこで IntValidator と**同じ `Qt.locale()`** で確定値を
    // 数値化し、ASCII の整数文字列へ直してから emit する（Codex PR #105。validator と同一 locale で
    // 解釈するので、どの locale でも入力と整合する）。パースできない（空 / 不正）ときは raw のまま
    // 下流の coerce に委ねる（`Number.fromLocaleString` は不正入力で例外を投げるため try で囲う）。
    // Task 54: 実効境界（clamp / validator 共通）。型に合わせて丸め、**境界逆転（min > max）は
    // 入れ替えて正規化**する（CodeRabbit PR #113）。未指定側は null。
    // - int は IntValidator の bottom=ceil / top=floor と揃えるため ceil(min)/floor(max)。
    // - real は境界そのまま。
    // - hasMin && hasMax で lo > hi になったら swap し、clamp が max 側へ押し込む・validator が
    //   bottom > top になる破綻を防ぐ。
    function _effectiveBounds() {
        var lo = root.hasMin ? (root.isReal ? root.minValue : Math.ceil(root.minValue)) : null;
        var hi = root.hasMax ? (root.isReal ? root.maxValue : Math.floor(root.maxValue)) : null;
        if (lo !== null && hi !== null && lo > hi) {
            var t = lo; lo = hi; hi = t;
        }
        return { lo: lo, hi: hi };
    }

    function commitValue() {
        var cleaned = field.text;
        try {
            // 確定値のパース locale は型で分ける（Codex PR #112 [P2]）：
            // - real：表示値は変数ストアの JS 数値由来で **常に ASCII の小数点**（"36.5"）。
            //   よって validator・表示・commit をすべて **C locale（ASCII）** に揃える。
            //   system locale（例：小数点カンマ）で再パースすると、編集せず focus/blur しただけの
            //   "36.5" が桁区切り誤読され 365 等を書き戻すため、real は必ず C locale で解釈する。
            // - int：従来どおり system `Qt.locale()`。IntValidator が locale 桁区切り / locale 固有
            //   数字も受理する契約（PR #105）を維持し、それらを ASCII 整数へ正規化する。
            var loc = root.isReal ? Qt.locale("C") : Qt.locale();
            var n = Number.fromLocaleString(loc, field.text);
            if (!isNaN(n)) {
                // real は整数丸めせず（小数を保つ）、int は従来どおり Math.trunc。
                n = root.isReal ? n : Math.trunc(n);
                // Task 54: 範囲外は **拒否でなく clamp**（確定時に境界へ丸める）。実効境界
                // （`_effectiveBounds`）は validator と共通＝型に合わせた丸め + 境界逆転の正規化済み。
                // 未指定側（null）は無制限。
                var b = _effectiveBounds();
                if (b.lo !== null && n < b.lo)
                    n = b.lo;
                if (b.hi !== null && n > b.hi)
                    n = b.hi;
                // real は **固定小数表記**へ整形する（Codex PR #112 [P2]）：素の `String(1e-7)` は
                // `"1e-7"` のような指数表記になり、StandardNotation 固定の DoubleValidator が
                // それを Invalid 扱いにして次回編集で矛盾する。`_toFixedNotation` で指数を展開し
                // ASCII 固定小数へ直す。int は指数化しないので従来どおり String で十分
                // （clamp 後の n は Math.trunc 済み整数 or ceil/floor の整数なので桁化けしない）。
                cleaned = root.isReal ? _toFixedNotation(n) : String(n);
            }
        } catch (e) {
            // パース不能（空 / 不正）は raw のまま
        }
        // 同一値の二重確定（Enter→blur で onEditingFinished が二度走る等）はスキップする。
        if (cleaned === root._lastCommittedText)
            return;
        root._lastCommittedText = cleaned;
        root.valueCommitted(cleaned);
    }

    // real の確定値を **指数表記にしない ASCII 固定小数文字列**へ整形する（Codex PR #112 [P2]）。
    // JS の `String(n)` は `1e-7` / `1e+21` のような指数表記を生むが、DoubleValidator は
    // StandardNotation（指数非対応）なので、書き戻した表示が自身の validator と矛盾する。
    // 指数表記を**文字列操作で**固定小数へ展開する（toFixed は >= 1e21 で指数を返すため使わない。
    // 桁ずらしは精度損失なし）。指数を含まない通常値（"36.5" 等）はそのまま返す。
    function _toFixedNotation(n) {
        var s = String(n);
        if (s.indexOf("e") === -1 && s.indexOf("E") === -1)
            return s;  // 既に固定小数表記
        var m = s.match(/^(-?)(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$/);
        if (!m)
            return s;  // 想定外の形式はそのまま
        var sign = m[1];
        var digits = m[2] + (m[3] || "");       // 仮数の全有効桁（小数点除去）
        var pointPos = m[2].length + parseInt(m[4], 10);  // 展開後の小数点位置
        var result;
        if (pointPos <= 0)
            result = "0." + "0".repeat(-pointPos) + digits;            // 0.000…digits
        else if (pointPos >= digits.length)
            result = digits + "0".repeat(pointPos - digits.length);    // digits000…
        else
            result = digits.slice(0, pointPos) + "." + digits.slice(pointPos);
        if (result.indexOf(".") !== -1)
            result = result.replace(/\.?0+$/, "");  // 余分な末尾ゼロ / 小数点を除去
        return sign + result;
    }

    // real の **表示値**を固定小数 ASCII へ整形する（Codex PR #112 [Minor]）。delegate は
    // bound 変数値を `String(v)` で流すため、初期値 / 外部 setVariable が `0.0000001` / `1e21`
    // 相当だと表示が `1e-7` / `1e+21` の指数表記になり、StandardNotation 固定の DoubleValidator と
    // 矛盾する（commitValue で避けた矛盾が表示・外部更新経路に残る）。表示テキストにも同じ
    // `_toFixedNotation` を通して固定小数へ揃える。int（isReal:false）や空・非数値は素通し。
    function _displayText(s) {
        if (!root.isReal)
            return s;
        if (s === undefined || s === null || String(s).trim() === "")
            return s;  // 空は 0 化せずそのまま
        var n = Number(s);
        return isNaN(n) ? s : _toFixedNotation(n);
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
        // delegate が流す表示テキスト。読み（変数追従）はこの宣言バインドで効く。
        // real は `_displayText` で固定小数へ整形して指数表記を避ける（Codex PR #112 [Minor]）。
        text: root._displayText(root.text)
        // Task 51: フォーカス取得時のみ宣言バインド `text: root.text` を**外す**（現在値を
        // 保ったまま imperative 代入で binding を切る）。これをしないと編集中に外部から同変数が
        // 更新されると入力中の値が上書きされ、確定時に意図しない値を書き戻す（Codex PR #105 P2）。
        // **確定 + 再バインドは `onEditingFinished` に集約**する（Enter / フォーカス喪失の双方で
        // 発火する単一の確定点）。フォーカス喪失でここで再バインドしてしまうと、確定処理より
        // 先に表示が旧 root.text へ戻り入力が失われるため、loss 側では再バインドしない
        // （Codex PR #105 P1 の「再バインドを editingFinished 後へ deferred」推奨に沿う）。
        onActiveFocusChanged: {
            if (activeFocus) {
                field.text = field.text       // 現在値を保持したまま `text: root.text` バインドを外す
                root._lastCommittedText = ""  // 新しい編集セッション＝同じ値でも改めて確定可にする
            }
        }
        // 数値のみ許可。Task 53: real 変数なら DoubleValidator（小数点入力を許可）、
        // int 変数なら IntValidator。validator は bound 変数型から導出した root.isReal で切替える。
        // DoubleValidator は locale の小数点を使う（commitValue は同一 Qt.locale() で解釈し ASCII
        // 数値へ正規化するので整合する）。notation は StandardNotation（指数表記を許容しない方向）。
        // Task 54: 数値範囲（hasMin / hasMax）は各 validator の bottom / top に反映済み（下記定義）。
        validator: root.isReal
            ? doubleValidator
            : intValidator
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

        // 入力確定（Enter / フォーカス喪失の単一の確定点）：**先に commitValue() で typed 値を
        // 確定**（delegate が変数へ write → boundValue 再評価で root.text 更新）し、**その後に**
        // `Qt.binding` で `text: root.text` を貼り直して確定値（coerce 後）へ表示を復帰させる。
        // 順序が重要：先に貼り直すと確定前に表示が旧 root.text へ戻り入力が失われる（Codex PR #105 P1）。
        onEditingFinished: {
            root.commitValue()
            field.text = Qt.binding(function() { return root._displayText(root.text) })
        }
    }

    // Task 53: validator は isReal で切替える。inline 三項では Component を 2 つ持てないため
    // id 付きで定義し、TextField.validator で参照する。非ビジュアルなので配置位置は任意。
    // DoubleValidator は **C locale**（ASCII 小数点）に固定する（Codex PR #112 [P2]）：
    // 表示・commit と同じ locale に揃え、ASCII の表示値 "36.5" が自身の validator で
    // Invalid 扱いにならないようにする（system locale 既定だと小数点カンマ環境で破綻）。
    //
    // Task 54: 数値範囲を validator の bottom / top にも反映する（入力時の拒否。確定時 clamp と
    // 二段で担保）。境界は **`_effectiveBounds` で clamp と共通化**（型に合わせた丸め〔int は
    // ceil/floor〕+ 境界逆転 min>max の swap 正規化、CodeRabbit PR #113）。未指定側（null）は
    // 型のデフォルト全域へ戻す（IntValidator は INT_MIN〜INT_MAX、DoubleValidator は ±inf）。
    // これにより int 変数で min=2.5 のとき "2" を入力拒否・確定 clamp で 3 に揃う。
    IntValidator {
        id: intValidator
        bottom: { var b = root._effectiveBounds(); return b.lo !== null ? b.lo : -2147483648 }
        top: { var b = root._effectiveBounds(); return b.hi !== null ? b.hi : 2147483647 }
    }
    DoubleValidator {
        id: doubleValidator
        locale: "C"
        notation: DoubleValidator.StandardNotation
        bottom: { var b = root._effectiveBounds(); return b.lo !== null ? b.lo : -Infinity }
        top: { var b = root._effectiveBounds(); return b.hi !== null ? b.hi : Infinity }
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
