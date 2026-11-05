import QtQuick
import QtQuick.Controls

// Task 26 / 44: 右側インスペクタ本体。選択中 Widget の各プロパティを編集する。
// 編集対象は editorCanvas.selectedWidgetId が指す live な EditableWidget
//（editorCanvas.selectedItem で解決）。Simulator / Runtime は読み取り専用のため、
// この編集 UI は Editor のみが持つ（Phase 4 ルール）。項目は InspectorSection で
// グループ化してある（基本 / 文字 / 背景・枠 / 状態 / 動作 / 詳細）。
//
// Task RF-B: Main.qml の肥大化解消のため、インスペクタのフォーム本体と
// インスペクタ専用のヘルパー（フォーカス集約プロパティ / 型判定 / アクション・
// バインディング・系列・幾何の編集関数 / ColorSwatch）をまとめて切り出した
//（リファクタリング計画 RF-B。objectName・編集ロジック・Schema は不変）。
// Canvas / Window への参照は受け口プロパティで受ける（同名バインドの自己参照罠を
// 避けるため別名＝MB-4 罠①）。Project レベルの変数定義（projectVariables）と
// その編集ヘルパー、ダイアログ起動は Window 側の所有のまま editorRoot 経由で呼ぶ。
//
// Task RF-G: 本ファイルも 2,372 行に膨らんだため、各 InspectorSection を
// Inspector<Name>Section.qml へ、色スウォッチを ColorSwatch.qml へ切り出した。
// ここに残るのは選択状態に依存する共有ヘルパー（型判定・フォーカス集約・系列編集）と
// セクションの並びだけ。セクション側は受け口 editorInspector（= root）経由で参照する。
Rectangle {
    id: root
    objectName: "inspectorPanel"
    width: 260
    color: "#f5f5f5"
    border.color: "#cccccc"
    border.width: 1

    // Main.qml の Canvas（id: canvas）と Window（id: rootWindow）。
    property var editorCanvas: null
    property var editorRoot: null

    // Task 40: 変数パネルの動的 TextField（Repeater 由来で id 固定できない）の編集中フラグ。
    // Delete ショートカットの抑止に使う（各行が onActiveFocusChanged で増減する）。
    property int variableFieldFocusCount: 0

    // Task 8B-D: Trend 系列パネルの動的 TextField（色 / 凡例ラベル、Repeater 由来で
    // id 固定できない）の編集中フラグ。変数定義（widget undo に載せない）と違い、系列は
    // widget 内データなので widget undo 境界（widgetEditFieldFocused）にも含める。
    // Delete ショートカット抑止（inspectorFieldFocused）にも入れる。
    property int seriesFieldFocusCount: 0

    // Task RF-G: アクション / バインディング編集の実体は InspectorActionSection.qml へ
    // 移した。Main.qml（プロジェクト読込後の再同期）から呼ばれるため外部 API として転送する。
    function applyActionFromInspector() { actionSection.applyActionFromInspector() }
    function syncActionToInspector() { actionSection.syncActionToInspector() }
    function applyBindingFromInspector() { actionSection.applyBindingFromInspector() }
    function syncBindingToInspector() { actionSection.syncBindingToInspector() }

    // Task 8B-D: Trend 系列エディタ。系列は選択中 live Item の widgetSeries
    //（[{variable, color, label}] 配列）を真実とし、**配列を丸ごと置換**して編集する
    // （アクション / バインディングと同じ流儀＝in-place 変更しないので参照共有でも安全）。
    // 系列の追加 / 削除は構造変更なので pushUndo() で 1 件積む（CheckBox と同じ離散操作。
    // 連続編集〔色 hex 手入力 / ラベル入力〕は各 TextField のフォーカス境界が
    // beginEdit/commitEdit を拾うため明示しない）。
    function currentSeries() {
        const it = root.editorCanvas.selectedItem
        if (!it || it.widgetSeries === undefined || it.widgetSeries === null) {
            return []
        }
        return it.widgetSeries
    }
    function addSeries() {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        root.editorCanvas.pushUndo()
        const next = currentSeries().slice()
        next.push({ variable: "", color: "", label: "" })
        root.editorCanvas.selectedItem.widgetSeries = next
    }
    function removeSeries(index) {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        const next = currentSeries().slice()
        if (index < 0 || index >= next.length) {
            return
        }
        root.editorCanvas.pushUndo()
        next.splice(index, 1)
        root.editorCanvas.selectedItem.widgetSeries = next
    }
    function updateSeries(index, key, value) {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        const next = currentSeries().slice()
        if (index < 0 || index >= next.length) {
            return
        }
        // 行オブジェクトを複製してから書き換える（live/undo の参照共有を切る）。
        const row = {
            variable: next[index].variable !== undefined ? next[index].variable : "",
            color: next[index].color !== undefined ? next[index].color : "",
            label: next[index].label !== undefined ? next[index].label : ""
        }
        row[key] = value
        next[index] = row
        root.editorCanvas.selectedItem.widgetSeries = next
    }

    // Task 26: 選択中の live な EditableWidget はインスペクタの編集対象。
    // 解決ロジックと所有は Canvas に集約した（editorCanvas.selectedItem）。Repeater
    // 再生成後も同一 id の新しい live Item に解決し直される（Codex PR #52 P2 指摘
    // への回答。詳細は Canvas.qml の selectedItem コメント）。インスペクタは
    // この live Item を直接 two-way 編集する（widgetModel の var 配列は据え置き
    // ＝Phase 4 設計指針、delegate 再生成を起こさない）。

    // Task RF-G: 幾何欄の同期の実体は InspectorBasicSection.qml へ移した（外部 API として転送）。
    function syncGeometryFields() { basicSection.syncGeometryFields() }

    // 座標・サイズの数値欄を ↑/↓ キーで増減する（Shift で ±10）。SpinBox 化された
    // 文字サイズ・ボーダー・角丸・不透明度は標準の矢印キー増減が効くのに対し、
    // X/Y/幅/高さ は TextField + IntValidator（Task 27 の SpinBox 不具合回避）で
    // キー増減が無く「キーボードで微調整できない」差があったため補う。現在値を
    // validator の範囲（bottom/top）へ clamp し、表示と選択中 live Item の両方を
    // 更新する（onTextEdited と同じ書き戻し経路）。フォーカス中の編集なので undo は
    // focus 由来の beginEdit/commitEdit が 1 操作として拾う。
    function nudgeGeometry(field, prop, step) {
        if (!root.editorCanvas.selectedItem) {
            return
        }
        const v = field.validator
        let cur = parseInt(field.text)
        if (isNaN(cur)) {
            cur = v.bottom
        }
        const next = Math.max(v.bottom, Math.min(v.top, cur + step))
        field.text = String(next)
        root.editorCanvas.selectedItem[prop] = next
    }

    // Task 46: 色スウォッチの一辺と、色 TextField がスウォッチ用に空ける幅
    //（スウォッチ + Row spacing 6）。3 つの色フィールドで共有する
    //（CodeRabbit PR #99 nitpick: マジックナンバー 34 の重複を定数化）。
    readonly property int colorSwatchSize: 28
    readonly property int colorSwatchReserve: colorSwatchSize + 6

    // Task 38: 選択中 Widget を編集するインスペクタ欄が編集フォーカス中か。これらの
    // 変更は Canvas の widgetModel に入る（snapshotModel が拾う）ため、Canvas undo の
    // 1 操作境界（beginEdit/commitEdit）のトリガにする。
    // Task 40: 変数定義欄（variableFieldFocusCount）は **ここに含めない**。変数編集は
    // editorRoot.projectVariables を変えるだけで Canvas の widgetModel には入らず、
    // Canvas undo スタックには載らない。リネーム時は widget 参照も書き換えるが、それも
    // beginEdit/commitEdit の外で行うため undo に載らず、変数定義と widget 参照が
    // 常に一致したまま動く（混ぜると Undo で widget 参照だけ旧名に戻り参照切れになる）。
    readonly property bool widgetEditFieldFocused:
        basicSection.editFieldFocused
        || textSection.editFieldFocused
        || styleSection.editFieldFocused
        || trendSection.editFieldFocused
        || meterSection.editFieldFocused
        || simpleButtonSection.editFieldFocused
        || actionSection.editFieldFocused
        || detailSection.editFieldFocused
        // Task 8B-D: 系列パネルの動的入力欄（色 / 凡例ラベル）も undo 境界に含める。
        || root.seriesFieldFocusCount > 0

    // Task 29 / 37: インスペクタのどれかの入力欄が編集フォーカス中か。Delete / Copy /
    // Paste / Duplicate のショートカットは、フィールド編集中（文字削除やテキストの
    // コピペに同じキーを使う）に奪うと困るため、このガードで無効化する。
    // Task 37 で Delete のインライン列挙をこの単一プロパティに集約した（重複排除）。
    // Task 40: 変数定義欄（variableFieldFocusCount）も Delete ガードには含める（変数名
    // を Backspace/Delete で消すときに widget が消えないように）が、Canvas undo の
    // widgetEditFieldFocused とは分離する（上のコメント参照）。
    readonly property bool inspectorFieldFocused:
        widgetEditFieldFocused
        || root.variableFieldFocusCount > 0

    // Task 48: 選択中 Widget が Label 型か。型に応じてインスペクタの無関係セクション /
    // 項目を隠す（Label は状態・クリックアクション・ボーダー/角丸を非表示。背景色・
    // 不透明度・バインディング・基本・文字・詳細は表示）。editorCanvas.selectedItem は単一選択時
    // のみ非 null なので、複数 / 未選択では false（単一編集フォーム自体が出ない）。
    // **objectName・編集ロジック・Schema は不変で、表示（visible）切替のみ**（plan Task 48）。
    readonly property bool selectedIsLabel:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "Label"

    // Task 51: 選択中 Widget が NumericField 型か。NumericField は入力 Widget で、状態
    // （有効/トグル/初期オン）とクリックアクションを持たない（書きは入力確定＝binding で行う）。
    // 背景・枠・文字・配置・不透明度・バインディングは持つ（背景・枠は Label と違い全部表示）。
    readonly property bool selectedIsNumericField:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "NumericField"

    // Task T-C: 選択中 Widget が Trend 型か。Trend は表示専用（ライブ折れ線）で、状態
    //（トグル/初期オン）・クリックアクション・文字（フォント）を持たない。背景・枠（グラフ枠）・
    // 不透明度・有効・バインディング（サンプル対象変数 = value 読み）は持つ。Trend 詳細
    //（点数 / Y 軸 / 線色 / 周期）は selectedIsTrend で出し分ける。
    readonly property bool selectedIsTrend:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "Trend"

    // Task M-C: 選択中 Widget が Meter 型か。Meter は表示専用（車のスピードメーター風＝
    // 円弧 + 針）で、状態（トグル/初期オン）・クリックアクション・文字（フォント）を持たない。
    // 背景・枠（メーター枠）・不透明度・有効・バインディング（表示対象変数 = value 読み）は持つ。
    // Meter 詳細（範囲 min/max / 弧色 / 針色 / 目盛り数 / 単位）は selectedIsMeter で出し分ける。
    readonly property bool selectedIsMeter:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "Meter"

    // Task W-E: 選択中 Widget が SimpleButton 型か。SimpleButton はテーマが外観を決めるため
    // 文字（フォント）・背景・枠セクションを隠し、固有の「シンプルボタン詳細」（形状 / テーマ /
    // 差し色 / 長押し時間）を出す。状態（有効 + ON/OFF＝checked）とバインディング（checked の
    // 値源）は表示する。クリックアクションは持たない（状態遷移は checked binding 経路へ一本化。
    // toggleVariable アクションと併用すると二重トグルになるため。Codex PR #164 [P2]）。
    readonly property bool selectedIsSimpleButton:
        root.editorCanvas.selectedItem !== null && root.editorCanvas.selectedItem.widgetType === "SimpleButton"

    // Task 51 / T-C / M-C: クリックアクション（onClick）を扱える Widget か（= Button のみ）。Label /
    // NumericField / Trend / Meter はクリックアクションを持たないため、`!selectedIsLabel && …`
    // を毎回連結せず派生プロパティへまとめる（今後の入力 / 表示 Widget 追加で破綻しにくい。
    // 新たに「クリックアクション非対応」種別が増えたらここだけ直せばよい）。Trend / Meter は
    // Label の既存抑制（selectedIsLabel）と独立に AND するだけで競合しない（派生 1 本に集約）。
    // Task W-E: SimpleButton もクリックアクション非対応（長押しトグル＝checked binding 経路のみ）。
    readonly property bool selectedSupportsClickAction:
        !selectedIsLabel && !selectedIsNumericField && !selectedIsTrend && !selectedIsMeter
        && !selectedIsSimpleButton

    // Task 38: インスペクタの Widget 編集を undo の 1 操作境界にする。どれかの入力欄が
    // フォーカスを得た時に前状態を保留（beginEdit）し、全フィールドからフォーカスが
    // 外れた時に確定（commitEdit、状態が変わっていれば 1 件積む）。これで「フィールドを
    // 触った 1 セッション = 1 undo」になり、キーストロークごとに積まれない。
    onWidgetEditFieldFocusedChanged: {
        if (widgetEditFieldFocused) {
            root.editorCanvas.beginEdit()
        } else {
            root.editorCanvas.commitEdit()
        }
    }

    // Task 31 (Codex PR #64 P2): border/radius でインスペクタ項目が増え、既定の
    // 1280x768 では角丸 SpinBox / 削除ボタンが下端に押し出されてアクセス不能に
    // なるため、フォーム全体を ScrollView に載せて縦スクロール可能にする。
    // contentWidth: availableWidth で横スクロールバーは出さない。
    ScrollView {
        id: inspectorScroll
        anchors.fill: parent
        anchors.margins: 12
        contentWidth: availableWidth
        clip: true

        // インスペクタを端まで送ったときに「ぐいーっ」と伸びて跳ね返る
        // overshoot（既定の DragAndOvershootBounds）を止め、端でピタッと
        // 止める。ScrollView の実体 Flickable（contentItem）へ設定する。
        Component.onCompleted: contentItem.boundsBehavior = Flickable.StopAtBounds

        Column {
            width: inspectorScroll.availableWidth
            spacing: 8

            Label {
                text: qsTr("インスペクタ")
                font.pixelSize: 16
                font.bold: true
            }

            // Task W-C（Phase 11）: サンプルパレット（選択に依らず常時表示）。プリセットを
            // 実 Widget の見た目で並べ、セルのクリックでキャンバス中央へ追加する。
            SamplePalette {
                objectName: "samplePalette"
                onPresetActivated: function(preset) {
                    root.editorCanvas.addPresetWidget(preset)
                }
            }

            // Task 40 / 44: Project レベルの変数定義パネル（選択に依らず常時表示）。
            // 変数の追加 / 削除 / 名前・型・初期値の編集を行い、editorRoot.projectVariables を
            // 駆動する。アクション target / バインディング variable の ComboBox 選択肢になる。
            // Task 44: 折りたたみ可能なセクションに収める。
            InspectorVariablesSection {
                id: variablesSection
                editorInspector: root
            }

            Rectangle { width: parent.width; height: 1; color: "#dddddd" }

            // 未選択時の案内（Task 36: 0 個選択のときのみ）
            Label {
                objectName: "inspectorEmptyLabel"
                visible: root.editorCanvas.selectedWidgetIds.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#888888"
                text: qsTr("Widget を選択してください")
            }

            // Task 36: 複数選択時のパネル。単一プロパティ編集は単一選択時のみとし、
            // 複数選択時は「N 個選択中」+ 一括整列 / 分布 / 削除のアクションを提供する。
            Column {
                objectName: "inspectorMultiPanel"
                visible: root.editorCanvas.selectedWidgetIds.length > 1
                width: parent.width
                spacing: 8

                Label {
                    objectName: "inspectorMultiLabel"
                    width: parent.width
                    font.bold: true
                    text: root.editorCanvas.selectedWidgetIds.length + qsTr(" 個選択中")
                }

                Label { text: qsTr("整列"); color: "#555555" }
                // 水平方向の整列（左 / 中央 / 右）
                Row {
                    spacing: 4
                    Button { objectName: "alignLeftButton";    text: qsTr("左");   onClicked: root.editorCanvas.alignSelected("left") }
                    Button { objectName: "alignHCenterButton"; text: qsTr("中央"); onClicked: root.editorCanvas.alignSelected("hcenter") }
                    Button { objectName: "alignRightButton";   text: qsTr("右");   onClicked: root.editorCanvas.alignSelected("right") }
                }
                // 垂直方向の整列（上 / 中央 / 下）
                Row {
                    spacing: 4
                    Button { objectName: "alignTopButton";     text: qsTr("上");   onClicked: root.editorCanvas.alignSelected("top") }
                    Button { objectName: "alignVCenterButton"; text: qsTr("中央"); onClicked: root.editorCanvas.alignSelected("vcenter") }
                    Button { objectName: "alignBottomButton";  text: qsTr("下");   onClicked: root.editorCanvas.alignSelected("bottom") }
                }

                Label { text: qsTr("等間隔分布（3 個以上）"); color: "#555555" }
                Row {
                    spacing: 4
                    Button { objectName: "distributeHButton"; text: qsTr("水平"); onClicked: root.editorCanvas.distributeSelected("h") }
                    Button { objectName: "distributeVButton"; text: qsTr("垂直"); onClicked: root.editorCanvas.distributeSelected("v") }
                }

                Button {
                    objectName: "inspectorMultiDeleteButton"
                    text: qsTr("選択をすべて削除")
                    onClicked: root.editorCanvas.deleteWidgets(root.editorCanvas.selectedWidgetIds)
                }
            }

            // 選択中の編集フォーム（Task 44: InspectorSection でグループ化）。
            Column {
                objectName: "inspectorForm"
                visible: root.editorCanvas.selectedItem !== null
                width: parent.width
                spacing: 8

                // ── 基本 : Text / 座標・サイズ ──
                InspectorBasicSection {
                    id: basicSection
                    editorInspector: root
                }

                // ── 文字 : フォント / 文字サイズ / 太字 / 斜体 / 文字色 / 配置 ──
                // Task T-C / M-C: Trend / Meter は文字を持たない（表示専用の折れ線グラフ /
                // メーター）ため文字セクションを丸ごと隠す（型出し分けは visible のみ）。
                InspectorTextSection {
                    id: textSection
                    editorInspector: root
                }

                // ── 背景・枠 : 背景色 / ボーダー / 角丸 / 不透明度 ──
                InspectorStyleSection {
                    id: styleSection
                    editorInspector: root
                }

                // ── Trend 詳細（Trend 選択時のみ）: 点数 N / Y 軸 min・max / 線色 / 周期 ──
                // Task T-C: Trend 固有の編集 UI。型出し分けは visible のみ（objectName・
                // 編集ロジック・Schema 不変）。点数 / 周期は int（SpinBox）、Y 軸 min/max は
                // double で **負値も正当なので presence チェック方式**（NumericField の min/max
                // を手本）。線色は色スウォッチ + ColorDialog（Task 46 の色入力を手本）。
                // すべて 2 本立て（onValueModified/onTextEdited で live Item へ書き戻し、
                // Connections.onSelectedItemChanged で表示同期）。
                InspectorTrendSection {
                    id: trendSection
                    editorInspector: root
                }

                // ── Meter 詳細（Meter 選択時のみ）: 範囲 min/max / 弧色 / 針色 / 目盛り数 / 単位 ──
                // Task M-C: Meter 固有の編集 UI。型出し分けは visible のみ（objectName・
                // 編集ロジック・Schema 不変）。範囲 min/max は double で **負値も正当なので
                // presence チェック方式**（Trend の Y 軸 min/max・NumericField の min/max を手本）。
                // 弧色 / 針色は色スウォッチ + ColorDialog（Task 46 の色入力を手本）。目盛り数は
                // int（SpinBox）、単位は素の TextField。すべて 2 本立て（onValueModified/
                // onTextEdited で live Item へ書き戻し、Connections.onSelectedItemChanged で表示同期）。
                InspectorMeterSection {
                    id: meterSection
                    editorInspector: root
                }

                // ── シンプルボタン詳細（SimpleButton 選択時のみ）: 形状 / テーマ / 差し色 / 長押し時間 ──
                // Task W-E: SimpleButton 固有の編集 UI。型出し分けは visible のみ（objectName・
                // 編集ロジック・Schema 不変）。形状 / テーマは hAlign と同じ「表示ラベル model +
                // parallel な values 配列」の ComboBox（index 0 = 未指定 = 空文字 = HmiSimpleButton
                // の resolved* が既定へ解決）。差し色は色スウォッチ + ColorDialog（弧色と同型）、
                // 長押し時間は SpinBox（0 = 既定 800ms。tickCount と同じ 0 センチネル）。
                InspectorSimpleButtonSection {
                    id: simpleButtonSection
                    editorInspector: root
                }

                // ── 状態 : 有効 / チェック可能 / チェック状態 ──
                // Task 48 / 51: Label（表示専用）はセクションごと隠す。**NumericField は
                // 「有効」だけ出す**（トグル / 初期オンは Button 専用）。NumericField も
                // `widgetEnabled` を内部 TextField.enabled に流すため、`enabled:false` を含む
                // JSON を開いたとき Editor で有効に戻せるよう「有効」チェックを残す
                // （Codex PR #105 P2）。トグル / 初期オンは `selectedSupportsClickAction`
                // ＝ Button のみで出し分ける（objectName・中身は不変、visible のみ）。
                InspectorStateSection {
                    id: stateSection
                    editorInspector: root
                }

                // ── 動作 : クリック時アクション / バインディング ──
                InspectorActionSection {
                    id: actionSection
                    editorInspector: root
                }

                // ── 詳細（既定で閉）: ID / 外部タグ ──
                // Task 45: 技術的・通常編集しない項目（読み取り専用の ID、機能未配線の
                // 外部タグ）をここへまとめ、既定で折りたたんで通常の編集を邪魔しない。
                InspectorDetailSection {
                    id: detailSection
                    editorInspector: root
                }

                // Task 29: 削除ボタン。構造変更（削除）は Canvas.deleteWidget() に
                // 集約する（addWidget と対称：live Item をスナップショット → 該当 id
                // を除いて再代入 → 選択解除）。これで未保存の他 widget 編集が
                // 巻き戻らない（Phase 4 設計指針）。
                Button {
                    objectName: "inspectorDeleteButton"
                    text: qsTr("削除")
                    onClicked: {
                        if (root.editorCanvas.selectedWidgetId) {
                            root.editorCanvas.deleteWidget(root.editorCanvas.selectedWidgetId)
                        }
                    }
                }
            }
        }
    }
}
