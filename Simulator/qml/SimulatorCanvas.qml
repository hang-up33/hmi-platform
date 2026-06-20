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

    // Phase 7 / MB-4: Modbus マスタ（Main.qml から渡す。テスト等では null のまま）。
    // ユーザー操作（NumericField 確定 / Button アクション）で VariableStore を更新した
    // **直後だけ** writeVariable を呼んで PLC へ書く。読込（variableUpdated→setValue）由来の
    // 変化では呼ばないので「読込→書戻し」のループが起きない（経路で分離する設計）。
    // writeVariable は source 無し / 読取専用レジスタの変数では no-op なので、呼ぶ側は
    // 変数が PLC source を持つか気にせず一律に呼んでよい。
    // **名前は context property の "modbusController" と意図的に変える**：QML のバインド右辺は
    // 代入先（canvas）のプロパティを先に解決するため、同名にすると self-reference になり
    // 常に null を指す（バインドが自分自身を見る）。別名にして Main.qml から context property を渡す。
    property var plcController: null

    // Phase 7 / MB-4: 変数を VariableStore 更新と同じ操作で PLC へも書く共通ヘルパー。
    // ユーザー操作経路（writeBoundValue / runClickActions）からのみ呼ぶ。
    function writeToPlc(name, value) {
        if (plcController !== null) {
            plcController.writeVariable(name, value)
        }
    }

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

                // Task 51: boundValue の **書き**版（入力 Widget 用）。propertyName に対応する
                // binding（{property, variable}）があれば、その変数へ raw を変数の型に coerce して
                // 書き戻す。NumericField の入力確定（valueCommitted）から呼ぶ。これで binding が
                // 「読み書き両用」になる（表示=boundValue の読み / 入力=writeBoundValue の書き）。
                // Schema 無改変＝既存 bindings を双方向に使うだけ（plan Phase 6 設計指針）。
                // 対応 binding が無ければ何もしない（書き戻し先が無い＝no-op）。runClickActions と
                // 同じく VariableStore.setValue を呼ぶので、他 binding の追従も同経路で効く。
                function writeBoundValue(propertyName, raw) {
                    const bindings = modelData.bindings
                    if (bindings) {
                        for (let i = 0; i < bindings.length; ++i) {
                            const b = bindings[i]
                            if (b && b.property === propertyName) {
                                const coerced =
                                    VariableStore.coerce(root.variableType(b.variable), raw)
                                VariableStore.setValue(b.variable, coerced)
                                // Phase 7 / MB-4: ユーザー入力確定なので PLC へも書く
                                // （読込由来でない＝ループしない）。
                                root.writeToPlc(b.variable, coerced)
                                return
                            }
                        }
                    }
                }

                // Task 53: propertyName に対応する binding が指す変数の型を返す（無ければ ""）。
                // NumericField の isReal 導出に使う（bound 変数が "real" なら real 入力）。
                function boundVariableType(propertyName) {
                    const bindings = modelData.bindings
                    if (bindings) {
                        for (let i = 0; i < bindings.length; ++i) {
                            const b = bindings[i]
                            if (b && b.property === propertyName) {
                                return root.variableType(b.variable)
                            }
                        }
                    }
                    return ""
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
                    // Task 42: disabled（enabled=false）の Button はクリックしてもアクションを
                    // 実行しない（「クリック無効」の実体。視覚の淡色は HmiButton.widgetEnabled）。
                    if (modelData.enabled === false) {
                        return
                    }
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
                            const coerced =
                                VariableStore.coerce(root.variableType(a.target), a.value)
                            VariableStore.setValue(a.target, coerced)
                            // Phase 7 / MB-4: ユーザー操作（クリック）由来なので PLC へも書く。
                            root.writeToPlc(a.target, coerced)
                        } else if (a.op === "toggleVariable") {
                            VariableStore.toggle(a.target)
                            // トグル後の現在値を PLC へ書く（coil 等の出力操作）。
                            root.writeToPlc(a.target, VariableStore.values[a.target])
                        }
                    }
                }

                // Task 41: visible を binding 追従させる（最小デモの 1 つ）。
                // 該当 binding が無ければ常に表示（従来動作）。
                visible: {
                    const v = wrapper.boundValue("visible")
                    return v === undefined ? true : VariableStore.coerce("bool", v)
                }

                // Task 47: 型分岐の足場（Editor Canvas.qml と対）。modelData.type に応じて
                // HmiButton / HmiLabel を Loader + inline Component の 2 分岐で描き分ける。
                // Runtime は本ソースを共有するため、これだけで実機にも型分岐が効く。
                // Label は **binding（text/textColor/backgroundColor/visible）追従のみ**で、
                // click action は結線しない（表示専用＝役割分担「読み⊂全 Widget・書き⊂対話 Widget」）。
                Loader {
                    anchors.fill: parent
                    sourceComponent: wrapper.modelData.type === "Label" ? labelComponent
                                   : wrapper.modelData.type === "NumericField" ? numericComponent
                                   : wrapper.modelData.type === "Trend" ? trendComponent
                                                                        : buttonComponent
                }

                Component {
                    id: buttonComponent
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
                        // Task 42: 状態別スタイルも HmiButton へ渡す（Editor delegate と対）。
                        // enabled は JSON キー enabled → HmiButton.widgetEnabled（組込み衝突回避）。
                        // 未指定は既定（enabled=true / checkable=false / checked=false）になる。
                        widgetEnabled: wrapper.modelData.enabled !== undefined ? wrapper.modelData.enabled : true
                        checkable: wrapper.modelData.checkable !== undefined ? wrapper.modelData.checkable : false
                        // Task 42: checked は binding があれば変数へ追従（toggleVariable + Binding で
                        // トグル連動）、無ければ modelData の初期値（静的）を使う。
                        checked: {
                            const v = wrapper.boundValue("checked")
                            return v !== undefined ? VariableStore.coerce("bool", v)
                                : (wrapper.modelData.checked !== undefined ? wrapper.modelData.checked : false)
                        }
                        // Task 41: クリックで紐づくアクションを実行する（変数更新 → binding 追従）。
                        // 読み取り専用アプリに初めて「実行」概念が入る箇所。引数 modifiers は使わない。
                        onClicked: wrapper.runClickActions()
                    }
                }

                Component {
                    id: labelComponent
                    HmiLabel {
                        // Task 47: 型分岐の観察用 objectName（HmiButton と対。E2E は hmiLabel で参照）。
                        objectName: "hmiLabel"
                        anchors.fill: parent
                        // Task 47: Label の binding 対応プロパティ（text / textColor /
                        // backgroundColor）は HmiButton と同じ boundValue 経路で変数へ追従させる。
                        // visible binding は wrapper(Item) 側で共通に効くため、ここでは扱わない。
                        text: {
                            const v = wrapper.boundValue("text")
                            return v !== undefined ? String(v)
                                : (wrapper.modelData.text !== undefined ? wrapper.modelData.text : "")
                        }
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
                        fontBold: wrapper.modelData.fontBold !== undefined ? wrapper.modelData.fontBold : false
                        fontItalic: wrapper.modelData.fontItalic !== undefined ? wrapper.modelData.fontItalic : false
                        fontFamily: wrapper.modelData.fontFamily !== undefined ? wrapper.modelData.fontFamily : ""
                        hAlign: wrapper.modelData.hAlign !== undefined ? wrapper.modelData.hAlign : ""
                        vAlign: wrapper.modelData.vAlign !== undefined ? wrapper.modelData.vAlign : ""
                        widgetOpacity: wrapper.modelData.opacity !== undefined ? wrapper.modelData.opacity : -1
                        widgetEnabled: wrapper.modelData.enabled !== undefined ? wrapper.modelData.enabled : true
                        // Label は表示専用＝onClicked を action 実行へ結線しない（クリックは無反応）。
                    }
                }

                Component {
                    id: numericComponent
                    HmiNumericField {
                        // Task 50: 型分岐の観察用 objectName（HmiButton / HmiLabel と対。
                        // E2E / unit は hmiNumericField で参照）。
                        objectName: "hmiNumericField"
                        anchors.fill: parent
                        // Task 51: Simulator/Runtime は live 編集＝editable:true。ユーザーが数値を
                        // 入力し確定すると下の onValueCommitted で binding の指す変数へ write する。
                        // Editor キャンバス（読取専用＝editable:false）との出し分けは delegate で行う。
                        editable: true
                        // Task 53: bound 変数（binding {property:"value"}）が real 型なら DoubleValidator +
                        // 小数保持の commit。int / 未 bind は false（IntValidator）。Editor キャンバスは
                        // editable:false で validator 非適用なので isReal:false 固定でよい。
                        isReal: wrapper.boundVariableType("value") === "real"
                        // Task 50: 読み（表示）。binding {property:"value"} があれば変数の
                        // 現在値を表示し、無ければ modelData の静的 text を使う（Label の text
                        // 追従と同じ boundValue 経路）。
                        text: {
                            const v = wrapper.boundValue("value")
                            return v !== undefined ? String(v)
                                : (wrapper.modelData.text !== undefined ? wrapper.modelData.text : "")
                        }
                        backgroundColor: wrapper.modelData.backgroundColor !== undefined ? wrapper.modelData.backgroundColor : ""
                        textColor: wrapper.modelData.textColor !== undefined ? wrapper.modelData.textColor : ""
                        fontSize: wrapper.modelData.fontSize !== undefined ? wrapper.modelData.fontSize : 0
                        borderColor: wrapper.modelData.borderColor !== undefined ? wrapper.modelData.borderColor : ""
                        borderWidth: wrapper.modelData.borderWidth !== undefined ? wrapper.modelData.borderWidth : -1
                        cornerRadius: wrapper.modelData.radius !== undefined ? wrapper.modelData.radius : -1
                        fontBold: wrapper.modelData.fontBold !== undefined ? wrapper.modelData.fontBold : false
                        fontItalic: wrapper.modelData.fontItalic !== undefined ? wrapper.modelData.fontItalic : false
                        fontFamily: wrapper.modelData.fontFamily !== undefined ? wrapper.modelData.fontFamily : ""
                        hAlign: wrapper.modelData.hAlign !== undefined ? wrapper.modelData.hAlign : ""
                        vAlign: wrapper.modelData.vAlign !== undefined ? wrapper.modelData.vAlign : ""
                        widgetOpacity: wrapper.modelData.opacity !== undefined ? wrapper.modelData.opacity : -1
                        widgetEnabled: wrapper.modelData.enabled !== undefined ? wrapper.modelData.enabled : true
                        // Task 54: 数値範囲 + presence を流す（presence は未指定時 false）。
                        // validator bottom/top + 確定時 clamp に効く（HmiNumericField 側で処理）。
                        minValue: wrapper.modelData.minValue !== undefined ? wrapper.modelData.minValue : 0
                        maxValue: wrapper.modelData.maxValue !== undefined ? wrapper.modelData.maxValue : 0
                        hasMin: wrapper.modelData.hasMinValue !== undefined ? wrapper.modelData.hasMinValue : false
                        hasMax: wrapper.modelData.hasMaxValue !== undefined ? wrapper.modelData.hasMaxValue : false
                        // Task 51: 入力確定（valueCommitted）で binding {property:"value"} の指す
                        // 変数へ書き戻す（読み書き両用 binding の **書き**）。binding が無ければ no-op。
                        // 書き込み後は VariableStore.values が更新され、表示（boundValue("value")）も
                        // 他の同変数 binding も追従する。読み取り専用アプリの「実行（書き戻し）」は
                        // ここに閉じ、選択 / 編集 UI は持ち込まない原則を維持する。
                        onValueCommitted: function(text) {
                            wrapper.writeBoundValue("value", text)
                        }
                    }
                }

                Component {
                    id: trendComponent
                    HmiTrend {
                        // Task T-B: 型分岐の観察用 objectName（他 Widget と対。
                        // E2E / unit は hmiTrend で参照）。
                        objectName: "hmiTrend"
                        anchors.fill: parent
                        // Simulator/Runtime はライブ実行＝live:true。value 変化 / 周期で
                        // リングバッファへ取り込む。Runtime は本ソース共有で自動継承。
                        live: true
                        // サンプル源（単系列後方互換）：binding {property:"value"} の指す変数の
                        // 現在値へ追従する（Label の text 追従と同じ boundValue 経路＝読みのみ。
                        // 書きはしない）。無 bind 時は modelData.value（無ければ 0）。series 非空時は
                        // value は使われず seriesValues が源になる。
                        value: {
                            const v = wrapper.boundValue("value")
                            return v !== undefined ? Number(v)
                                : (wrapper.modelData.value !== undefined ? Number(wrapper.modelData.value) : 0)
                        }
                        // Task 8B-B: 複数系列モデルを素通しで流す（[{variable, color, label}]）。
                        series: wrapper.modelData.series !== undefined && wrapper.modelData.series !== null ? wrapper.modelData.series : []
                        // 各系列の現在値を VariableStore から供給する。**関数評価中に
                        // VariableStore.values を読むことで依存追跡が効き**、変数更新で式が
                        // 再評価され seriesValues が更新→ HmiTrend が取り込む（boundValue 同型）。
                        seriesValues: {
                            const ss = wrapper.modelData.series
                            if (ss === undefined || ss === null || ss.length === 0) {
                                return []
                            }
                            const out = []
                            for (let i = 0; i < ss.length; ++i) {
                                const varName = ss[i] ? ss[i].variable : ""
                                const raw = (varName !== undefined && varName !== "")
                                    ? VariableStore.values[varName] : undefined
                                out.push(raw !== undefined ? Number(raw) : 0)
                            }
                            return out
                        }
                        // Trend 固有フィールド（未指定は 0 / 空 / presence false）。
                        pointCount: wrapper.modelData.pointCount !== undefined ? wrapper.modelData.pointCount : 0
                        yMin: wrapper.modelData.yMin !== undefined ? wrapper.modelData.yMin : 0
                        yMax: wrapper.modelData.yMax !== undefined ? wrapper.modelData.yMax : 0
                        hasYMin: wrapper.modelData.hasYMin !== undefined ? wrapper.modelData.hasYMin : false
                        hasYMax: wrapper.modelData.hasYMax !== undefined ? wrapper.modelData.hasYMax : false
                        lineColor: wrapper.modelData.lineColor !== undefined ? wrapper.modelData.lineColor : ""
                        sampleMs: wrapper.modelData.sampleMs !== undefined ? wrapper.modelData.sampleMs : 0
                        // Task 8B-D: 軸/凡例フラグを流す（既定 OFF＝後方互換）。
                        showGrid: wrapper.modelData.showGrid !== undefined ? wrapper.modelData.showGrid : false
                        showLegend: wrapper.modelData.showLegend !== undefined ? wrapper.modelData.showLegend : false
                        yTickCount: wrapper.modelData.yTickCount !== undefined ? wrapper.modelData.yTickCount : 0
                        // 背景・枠スタイル（Editor delegate と対）。
                        backgroundColor: wrapper.modelData.backgroundColor !== undefined ? wrapper.modelData.backgroundColor : ""
                        borderColor: wrapper.modelData.borderColor !== undefined ? wrapper.modelData.borderColor : ""
                        borderWidth: wrapper.modelData.borderWidth !== undefined ? wrapper.modelData.borderWidth : -1
                        cornerRadius: wrapper.modelData.radius !== undefined ? wrapper.modelData.radius : -1
                        widgetOpacity: wrapper.modelData.opacity !== undefined ? wrapper.modelData.opacity : -1
                        widgetEnabled: wrapper.modelData.enabled !== undefined ? wrapper.modelData.enabled : true
                        // Trend は表示専用＝clicked を action へ結線しない。
                    }
                }
            }
        }
    }
}
