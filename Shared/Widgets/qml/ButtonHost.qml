import QtQuick

// Task RF-E: Button 種別の「Schema 値 → HmiButton プロパティ」受け渡しを
// Shared/Widgets へ集約するホスト QML。Editor（Canvas.qml）/ Simulator
// （SimulatorCanvas.qml）の Button delegate は、Task 47 の Loader + inline
// Component パターンでこの受け渡し部分がほぼ同形のまま型ごとに反復定義されていた。
// このホストはその重複部分だけを 1 箇所にまとめ、両アプリから再利用する。
// 対象は「表示専用 + binding 読取のみ」の種別（Button/Label/SimpleButton）に限定し、
// 読み書き両用 binding を持つ NumericField や binding 非対応の Trend/Meter は対象外
//（試作評価の結果、非対称性の吸収コストが見合わないため別途検討。Docs/refactoring-plan.md）。
//
// Editor（静的値をそのまま渡す）と Simulator（Task 41 の boundValue 経由で変数
// バインディングへ追従する）の非対称性は `resolveBound` フックで吸収する：
//   - Editor は resolveBound を渡さない（既定 null）→ 常に widget の静的値を使う。
//   - Simulator は resolveBound に `wrapper.boundValue`（Task 41 で確立した関数、
//     無改変で渡せる）を渡す → 対応 binding があればその変数の**生の値**を返す
//     （無ければ undefined）。String 化 / bool 化（coerce）はこのホストが行う
//     （呼び出し側に coerce 済みの値を要求しない）。
//
// `widget` は呼び出し側（delegate）が組み立てる、HmiButton の入力名をキーに持つ
// プレーンオブジェクト（例: { text, tag, backgroundColor, ... }）。JSON キー名との
// マッピング（radius→cornerRadius 等、Task 31/34/42 で確立済みの規約）は呼び出し側
// の責務のまま据え置く（Host は HmiButton の入力名だけを見る）。
Item {
    id: hostRoot

    // HmiButton の入力名をキーに持つ静的値の束。
    required property var widget

    // binding 追従の読み取りフック。null（既定）なら追従しない（Editor）。
    // 渡す場合は function(propertyName) -> 変数の生の値 or undefined（Simulator）。
    property var resolveBound: null

    // 選択中継（Editor）/ アクション実行（Simulator）に使うクリック通知。
    // HmiButton.clicked(int modifiers) をそのまま中継する。
    signal clicked(int modifiers)

    // resolveBound があり該当 binding があれば String 化した値、無ければ
    // widget の静的値（省略時は ""）を返す。text/backgroundColor/textColor で使う。
    function resolvedText(prop, staticValue) {
        if (hostRoot.resolveBound !== null) {
            const v = hostRoot.resolveBound(prop)
            if (v !== undefined) {
                return String(v)
            }
        }
        return staticValue !== undefined ? staticValue : ""
    }

    // resolveBound があり該当 binding があれば bool 化した値（VariableStore.coerce）、
    // 無ければ widget の静的値（省略時は false）を返す。checked で使う。
    // VariableStore は同一モジュール（HmiWidgets）内 singleton のため import 不要。
    function resolvedBool(prop, staticValue) {
        if (hostRoot.resolveBound !== null) {
            const v = hostRoot.resolveBound(prop)
            if (v !== undefined) {
                return VariableStore.coerce("bool", v)
            }
        }
        return staticValue !== undefined ? staticValue : false
    }

    HmiButton {
        // Task 47 由来の objectName（Editor/Simulator 両 delegate と対。E2E は
        // widget_<id>/hmiButton で参照する。Host を挟んでも Spix / unit の探索は
        // 再帰的〔objectName の無い中間ノードを跨いで検索〕なのでパスは変わらない）。
        objectName: "hmiButton"
        anchors.fill: parent

        text: hostRoot.resolvedText("text", hostRoot.widget.text)
        tag: hostRoot.widget.tag !== undefined ? hostRoot.widget.tag : ""
        backgroundColor: hostRoot.resolvedText("backgroundColor", hostRoot.widget.backgroundColor)
        textColor: hostRoot.resolvedText("textColor", hostRoot.widget.textColor)
        fontSize: hostRoot.widget.fontSize !== undefined ? hostRoot.widget.fontSize : 0
        borderColor: hostRoot.widget.borderColor !== undefined ? hostRoot.widget.borderColor : ""
        borderWidth: hostRoot.widget.borderWidth !== undefined ? hostRoot.widget.borderWidth : -1
        cornerRadius: hostRoot.widget.cornerRadius !== undefined ? hostRoot.widget.cornerRadius : -1
        fontBold: hostRoot.widget.fontBold !== undefined ? hostRoot.widget.fontBold : false
        fontItalic: hostRoot.widget.fontItalic !== undefined ? hostRoot.widget.fontItalic : false
        fontFamily: hostRoot.widget.fontFamily !== undefined ? hostRoot.widget.fontFamily : ""
        hAlign: hostRoot.widget.hAlign !== undefined ? hostRoot.widget.hAlign : ""
        vAlign: hostRoot.widget.vAlign !== undefined ? hostRoot.widget.vAlign : ""
        widgetOpacity: hostRoot.widget.widgetOpacity !== undefined ? hostRoot.widget.widgetOpacity : -1
        widgetEnabled: hostRoot.widget.widgetEnabled !== undefined ? hostRoot.widget.widgetEnabled : true
        checkable: hostRoot.widget.checkable !== undefined ? hostRoot.widget.checkable : false
        checked: hostRoot.resolvedBool("checked", hostRoot.widget.checked)

        onClicked: function(modifiers) { hostRoot.clicked(modifiers) }
    }
}
