import QtQuick
import HmiWidgets

// HMI Simulator 用の読み取り専用キャンバス（Task 8）。
//
// Editor の Canvas.qml と似た構造だが、編集機能は持たない：
//   - EditableWidget でラップしない（ドラッグ不可）
//   - HmiButton を Repeater で直接配置する
//   - 子要素を外から追加する経路は持たない（widgetModel のみが描画ソース）
//
// QtQuick 標準の Canvas 型と衝突しないよう "SimulatorCanvas" のプレフィックス
// 命名を採用（CLAUDE.md「QtQuick 標準型と同名の QML ファイルを作らない」）。
Item {
    id: root

    property int canvasWidth: 800
    property int canvasHeight: 600

    // Widget 配置情報。Main.qml から projectLoader.load() の結果を流し込む。
    property var widgetModel: []

    // Task 41: 変数定義（[{name,type,initial}, ...]）。Main.qml から
    // projectLoader.load() の result.variables を流し込む。設定されると実行時の
    // 変数ストア（VariableStore）を初期値で初期化する。**読み取り専用アプリが
    // 初めて「動く」** ための土台で、Runtime はソース共有でそのまま実機にも効く。
    property var variableModel: []

    // JSON 読込が一度でも成功したか。widgetModel.length では「空 widgets の
    // 有効 JSON」と「未読込」を区別できないため独立フラグで持つ
    // （ScreenData::isValidJson は空 widgets 配列を許容する仕様のため）。
    property bool loaded: false

    // Task 41: 変数定義が差し替わったら実行ストアを初期値で初期化する。
    // VariableStore.values は再代入で通知されるため、これに追従するバインディング
    // （下の delegate の boundValue 経由）が再評価される。
    onVariableModelChanged: VariableStore.initFrom(variableModel)

    // Task 41: 変数名 → 型 を引く（setVariable の値を型に合わせて coerce するため）。
    // 定義に無い名前は string 既定。
    function variableType(name) {
        if (variableModel) {
            for (let i = 0; i < variableModel.length; ++i) {
                const d = variableModel[i]
                if (d && d.name === name) {
                    return d.type !== undefined ? d.type : "string"
                }
            }
        }
        return "string"
    }

    implicitWidth: canvasWidth
    implicitHeight: canvasHeight
    width: canvasWidth
    height: canvasHeight

    Rectangle {
        id: background
        anchors.fill: parent
        color: "white"
        border.color: "#888888"
        border.width: 1

        Repeater {
            model: root.widgetModel
            delegate: Item {
                id: wrapper
                required property var modelData
                // Task 20: Spix から `widget_<id>` で参照できるようにする
                // （Editor 側 EditableWidget と同じ命名規則）。
                objectName: "widget_" + (modelData.id !== undefined ? modelData.id : "")
                x: modelData.x !== undefined ? modelData.x : 0
                y: modelData.y !== undefined ? modelData.y : 0
                width: modelData.width !== undefined ? modelData.width : 120
                height: modelData.height !== undefined ? modelData.height : 40

                // Task 41: バインディング解決ヘルパー。property 名に対応する
                // binding（{property, variable}）があればその変数の現在値を返す。
                // 無ければ undefined（呼び出し側で modelData の静的値へフォールバック）。
                // この関数は評価中に VariableStore.values を読むため、それを使う
                // バインディング式は変数更新時に再評価される（QML の依存追跡は
                // 関数呼び出しを跨いで効く）。
                function boundValue(propertyName) {
                    const bindings = modelData.bindings
                    if (bindings) {
                        for (let i = 0; i < bindings.length; ++i) {
                            const b = bindings[i]
                            if (b && b.property === propertyName) {
                                return VariableStore.values[b.variable]
                            }
                        }
                    }
                    return undefined
                }

                // Task 41: onClick アクションを実行する（setVariable / toggleVariable）。
                // trigger は "onClick"（既定）のみ反応する。**trigger 省略 / 空も onClick
                // とみなす**：Schema の ActionData.trigger 既定が "onClick" で、Editor の
                // インスペクタ（Task 40）も "onClick" 固定で保存するため、未設定 = onClick
                // と解釈して取りこぼさない（将来 "onPress" 等を足す時はここで分岐を増やす）。
                // target / op が揃ったものだけ実行。
                // 値は変数の型に合わせて coerce する。読み取り専用アプリの「実行」概念は
                // ここだけに閉じ、選択 / 編集は持ち込まない原則を維持する。
                function runClickActions() {
                    const actions = modelData.actions
                    if (!actions) {
                        return
                    }
                    for (let i = 0; i < actions.length; ++i) {
                        const a = actions[i]
                        if (!a || !a.target) {
                            continue
                        }
                        if (a.trigger !== undefined && a.trigger !== ""
                                && a.trigger !== "onClick") {
                            continue
                        }
                        if (a.op === "setVariable") {
                            VariableStore.setValue(
                                a.target,
                                VariableStore.coerce(root.variableType(a.target), a.value))
                        } else if (a.op === "toggleVariable") {
                            VariableStore.toggle(a.target)
                        }
                    }
                }

                // Task 41: visible を binding 追従させる（最小デモの 1 つ）。
                // 該当 binding が無ければ常に表示（従来動作）。
                visible: {
                    const v = wrapper.boundValue("visible")
                    return v === undefined ? true : VariableStore.coerce("bool", v)
                }

                // MVP は Button のみ。将来 Widget 種別が増えたら type で分岐する。
                HmiButton {
                    // Task 30: E2E（Spix）から hmiSimulatorWindow/widget_<id>/hmiButton の
                    // パスで text / backgroundColor 等の描画値を getStringProperty 検証
                    // できるよう objectName を付与する（widget_<id> wrapper 命名と対）。
                    objectName: "hmiButton"
                    anchors.fill: parent
                    // Task 41: text / backgroundColor / textColor は binding があれば
                    // 変数の現在値へ追従し、無ければ modelData の静的値を使う
                    // （binding property の選択肢＝Editor の inspectorBindingPropCombo と対）。
                    text: {
                        const v = wrapper.boundValue("text")
                        return v !== undefined ? String(v)
                            : (wrapper.modelData.text !== undefined ? wrapper.modelData.text : "")
                    }
                    tag: wrapper.modelData.tag !== undefined ? wrapper.modelData.tag : ""
                    // Task 28: スタイル属性も HmiButton へ渡す（Editor delegate と対）。
                    // 未指定（空 / 0）は HmiButton 側で既定外観にフォールバックされる。
                    // Runtime は本ソースを共有するため、これだけで実機にも反映される。
                    // Task 41: 色は binding があれば変数へ追従（無ければ静的値）。
                    backgroundColor: {
                        const v = wrapper.boundValue("backgroundColor")
                        return v !== undefined ? String(v)
                            : (wrapper.modelData.backgroundColor !== undefined ? wrapper.modelData.backgroundColor : "")
                    }
                    textColor: {
                        const v = wrapper.boundValue("textColor")
                        return v !== undefined ? String(v)
                            : (wrapper.modelData.textColor !== undefined ? wrapper.modelData.textColor : "")
                    }
                    fontSize: wrapper.modelData.fontSize !== undefined ? wrapper.modelData.fontSize : 0
                    // Task 31: ボーダー＋角丸も HmiButton へ渡す（Editor delegate と対）。
                    // 角丸は radius（JSON キー）→ cornerRadius（HmiButton 入力名）にマップ。
                    // 未指定（空 / -1）は HmiButton 側で既定外観にフォールバックされる。
                    borderColor: wrapper.modelData.borderColor !== undefined ? wrapper.modelData.borderColor : ""
                    borderWidth: wrapper.modelData.borderWidth !== undefined ? wrapper.modelData.borderWidth : -1
                    cornerRadius: wrapper.modelData.radius !== undefined ? wrapper.modelData.radius : -1
                    // Task 33: フォント詳細も HmiButton へ渡す（Editor delegate と対）。
                    // 未指定（false / 空文字）は HmiButton 側で既定（太字/斜体なし・既定フォント）になる。
                    fontBold: wrapper.modelData.fontBold !== undefined ? wrapper.modelData.fontBold : false
                    fontItalic: wrapper.modelData.fontItalic !== undefined ? wrapper.modelData.fontItalic : false
                    fontFamily: wrapper.modelData.fontFamily !== undefined ? wrapper.modelData.fontFamily : ""
                    // Task 34: 配置 + 不透明度も HmiButton へ渡す（Editor delegate と対）。
                    // 不透明度は JSON キー opacity → HmiButton.widgetOpacity（組込み衝突回避）。
                    // 未指定（空 / -1）は HmiButton 側で既定（中央寄せ・不透明度 1.0）になる。
                    hAlign: wrapper.modelData.hAlign !== undefined ? wrapper.modelData.hAlign : ""
                    vAlign: wrapper.modelData.vAlign !== undefined ? wrapper.modelData.vAlign : ""
                    widgetOpacity: wrapper.modelData.opacity !== undefined ? wrapper.modelData.opacity : -1
                    // Task 41: クリックで紐づくアクションを実行する（変数更新 → binding 追従）。
                    // 読み取り専用アプリに初めて「実行」概念が入る箇所。引数 modifiers は使わない。
                    onClicked: wrapper.runClickActions()
                }
            }
        }
    }
}
