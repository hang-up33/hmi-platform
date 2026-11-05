import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「文字（文字色 / フォント / 配置）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: textSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null

    // このセクション内の入力欄が編集フォーカス中か。InspectorPanel の
    // widgetEditFieldFocused（Canvas undo の 1 操作境界）がこれを OR する。
    readonly property bool editFieldFocused:
        inspectorTextColorField.activeFocus
        || inspectorFontSizeSpin.activeFocus
        || inspectorFontFamilyCombo.activeFocus
        || inspectorHAlignCombo.activeFocus
        || inspectorVAlignCombo.activeFocus
    title: qsTr("文字")
    // Task W-E: SimpleButton はテーマが文字色・サイズを決める（ラベル文字列
    // 自体は「基本」の Text 欄で編集）ため、フォント詳細を隠す。
    visible: !editorInspector.selectedIsTrend && !editorInspector.selectedIsMeter
             && !editorInspector.selectedIsSimpleButton

    // フォント family は ComboBox。model 先頭に「(既定フォント)」を置き、
    // index 0 = 未指定（空文字 = システム既定）にマップする。残りは
    // Qt.fontFamilies()（生成時に一度評価）。読込 JSON の family が
    // システムに無い（model に無い）場合は表示だけ index 0 に落とし、
    // live Item の値は上書きしない（ユーザーが選び直すまで保持する）。
    Label { text: qsTr("フォント") }
    ComboBox {
        id: inspectorFontFamilyCombo
        objectName: "inspectorFontFamilyCombo"
        width: parent.width
        model: ["(既定フォント)"].concat(Qt.fontFamilies())
        // index 0（既定フォント）は空文字 = 未指定として書き戻す。
        onActivated: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetFontFamily =
                    (currentIndex === 0 ? "" : currentText)
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                const fam = it ? it.widgetFontFamily : ""
                const idx = fam
                    ? inspectorFontFamilyCombo.model.indexOf(fam) : 0
                inspectorFontFamilyCombo.currentIndex = idx >= 0 ? idx : 0
            }
        }
    }

    // 文字サイズは SpinBox（範囲 6〜96 px）。editable は付けない：
    // Task 27 で editable な SpinBox は value をプログラム設定しても
    // 表示テキストが更新されない不具合を確認したため（非 editable なら
    // value 設定で表示が正しく更新される）。0/未指定は HmiButton 側で
    // 既定 14px にフォールバックされるので、ここでは既定 14 を表示する。
    Label { text: qsTr("文字サイズ") }
    SpinBox {
        id: inspectorFontSizeSpin
        objectName: "inspectorFontSizeSpin"
        from: 6
        to: 96
        value: 14
        // ユーザー操作（valueModified）でのみ書き戻す。プログラムからの
        // value 代入では発火しないため書き戻しループは起きない。
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetFontSize = value
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                // 0/未指定は既定 14 を表示（HmiButton の resolvedFontSize と整合）。
                inspectorFontSizeSpin.value = (it && it.widgetFontSize > 0)
                    ? it.widgetFontSize : 14
            }
        }
    }

    // Task 33: フォント詳細（太字 / 斜体）。bool は CheckBox。編集は T26 以降と
    // 同じ 2 本立て + 明示 beginEdit/commitEdit（CheckBox はフォーカス境界に
    // 含まれないため離散操作として 1 件 undo へ積む）。
    CheckBox {
        id: inspectorFontBoldCheck
        objectName: "inspectorFontBoldCheck"
        text: qsTr("太字")
        // Task 38（Codex PR #77 [Major]）：CheckBox はフォーカス境界
        // （inspectorFieldFocused）に含まれず onToggled で live Item を直接
        // 変えるため、ここで明示的に beginEdit→commitEdit して 1 操作を
        // undo へ積む（離散操作なので開始即確定で 1 件）。
        onToggled: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.beginEdit()
                editorInspector.editorCanvas.selectedItem.widgetFontBold = checked
                editorInspector.editorCanvas.commitEdit()
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorFontBoldCheck.checked = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetFontBold : false
            }
        }
    }

    CheckBox {
        id: inspectorFontItalicCheck
        objectName: "inspectorFontItalicCheck"
        text: qsTr("斜体")
        // Task 38（Codex PR #77 [Major]）：太字 CheckBox と同様に明示で
        // undo へ積む（フォーカス境界に含まれないため）。
        onToggled: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.beginEdit()
                editorInspector.editorCanvas.selectedItem.widgetFontItalic = checked
                editorInspector.editorCanvas.commitEdit()
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorFontItalicCheck.checked = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetFontItalic : false
            }
        }
    }

    // Task 29: 文字色（"#RRGGBB" hex の TextField）。空文字は HmiButton 側で
    // 既定外観にフォールバックされる。編集は 2 本立て（onTextEdited で live
    // Item へ書き戻し、Connections.onSelectedItemChanged で表示同期）。
    Label { text: qsTr("文字色 (#RRGGBB)") }
    // Task 46: hex TextField + 色スウォッチ（プレビュー / クリックで
    // ColorDialog）。手入力欄はそのまま残す（E2E / 既存導線を維持）。
    // 幅は leftPadding（InspectorSection の content インデント）ぶん
    // 詰める：parent.width のままだと右端のスウォッチがインデント分
    // はみ出して ScrollView の clip に切られる。
    Row {
        width: parent.width - parent.leftPadding
        spacing: 6

        TextField {
            id: inspectorTextColorField
            objectName: "inspectorTextColorField"
            width: parent.width - editorInspector.colorSwatchReserve
            placeholderText: qsTr("white")
            // Codex PR #58 P2: 空 または 完全な #RRGGBB の時だけ反映する
            //（途中入力・不正値を live Item に書き戻さない）。
            validator: RegularExpressionValidator {
                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
            }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.widgetTextColor = text
                }
            }
            Connections {
                target: editorInspector.editorCanvas
                function onSelectedItemChanged() {
                    inspectorTextColorField.text = editorInspector.editorCanvas.selectedItem
                        ? editorInspector.editorCanvas.selectedItem.widgetTextColor : ""
                }
            }
        }
        ColorSwatch {
            inspector: editorInspector
            objectName: "inspectorTextColorSwatch"
            anchors.verticalCenter: parent.verticalCenter
            field: inspectorTextColorField
            targetProperty: "widgetTextColor"
            // 未指定時の既定色は Widget 種別の resolved* と揃える
            //（HmiButton=white / HmiLabel=#1d3557 / HmiNumericField=#1d3557）。
            // Task 51: NumericField も Label と同じ濃文字（#1d3557）が既定。
            fallback: (editorInspector.editorCanvas.selectedItem
                       && (editorInspector.editorCanvas.selectedItem.widgetType === "Label"
                           || editorInspector.editorCanvas.selectedItem.widgetType === "NumericField"))
                ? "#1d3557" : "white"
        }
    }

    // Task 34: テキスト配置（水平 / 垂直）。配置は ComboBox で、表示ラベルと
    // enum 文字列を parallel な values 配列でマップする（index 0 = "(既定:中央)"
    // = 空文字 = 未指定）。2 本立て（onActivated で書き戻し、
    // Connections.onSelectedItemChanged で表示同期）。
    Label { text: qsTr("水平配置") }
    ComboBox {
        id: inspectorHAlignCombo
        objectName: "inspectorHAlignCombo"
        width: parent.width
        // 表示ラベル（model）と書き戻す enum 文字列（values）を index で対応させる。
        readonly property var values: ["", "left", "center", "right"]
        model: [qsTr("(既定:中央)"), qsTr("左"), qsTr("中央"), qsTr("右")]
        onActivated: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetHAlign = values[currentIndex]
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                const v = it ? it.widgetHAlign : ""
                const idx = inspectorHAlignCombo.values.indexOf(v)
                inspectorHAlignCombo.currentIndex = idx >= 0 ? idx : 0
            }
        }
    }

    Label { text: qsTr("垂直配置") }
    ComboBox {
        id: inspectorVAlignCombo
        objectName: "inspectorVAlignCombo"
        width: parent.width
        readonly property var values: ["", "top", "middle", "bottom"]
        model: [qsTr("(既定:中央)"), qsTr("上"), qsTr("中央"), qsTr("下")]
        onActivated: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetVAlign = values[currentIndex]
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                const v = it ? it.widgetVAlign : ""
                const idx = inspectorVAlignCombo.values.indexOf(v)
                inspectorVAlignCombo.currentIndex = idx >= 0 ? idx : 0
            }
        }
    }
}
