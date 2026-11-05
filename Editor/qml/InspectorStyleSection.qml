import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「背景・枠（背景色 / ボーダー / 角丸 / 不透明度）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: styleSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null

    // このセクション内の入力欄が編集フォーカス中か。InspectorPanel の
    // widgetEditFieldFocused（Canvas undo の 1 操作境界）がこれを OR する。
    readonly property bool editFieldFocused:
        inspectorBgColorField.activeFocus
        || inspectorBorderColorField.activeFocus
        || inspectorBorderWidthSpin.activeFocus
        || inspectorRadiusSpin.activeFocus
        || inspectorOpacitySpin.activeFocus
    title: qsTr("背景・枠")
    // Task W-E: SimpleButton は面色・縁取り・影をテーマ（light/dark）が
    // 決めるため、背景・枠セクションごと隠す（backgroundColor/border* は
    // SimpleButton では未使用＝plan §Schema「流さない」）。
    visible: !editorInspector.selectedIsSimpleButton

    // Task 29: 背景色（"#RRGGBB" hex の TextField）。空文字は HmiButton 側で
    // 既定外観にフォールバックされる（widgetBackgroundColor は空 = 未指定）。
    Label { text: qsTr("背景色 (#RRGGBB)") }
    // Task 46: hex TextField + 色スウォッチ（プレビュー / クリックで
    // ColorDialog）。手入力欄はそのまま残す（E2E / 既存導線を維持）。
    // 幅補正は文字色の Row と同じ（leftPadding ぶん詰める）。
    Row {
        width: parent.width - parent.leftPadding
        spacing: 6

        TextField {
            id: inspectorBgColorField
            objectName: "inspectorBgColorField"
            width: parent.width - editorInspector.colorSwatchReserve
            placeholderText: qsTr("#4cc9f0")
            // Codex PR #58 P2: 空 または 完全な #RRGGBB の時だけ live Item へ
            // 反映する。途中入力（"#ff"）や不正値（"redx"）が
            // widgetBackgroundColor に残ると JSON に無効色が保存され、
            // Simulator/Runtime の描画で無効色になるため。
            validator: RegularExpressionValidator {
                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
            }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.widgetBackgroundColor = text
                }
            }
            Connections {
                target: editorInspector.editorCanvas
                function onSelectedItemChanged() {
                    inspectorBgColorField.text = editorInspector.editorCanvas.selectedItem
                        ? editorInspector.editorCanvas.selectedItem.widgetBackgroundColor : ""
                }
            }
        }
        ColorSwatch {
            inspector: editorInspector
            objectName: "inspectorBgColorSwatch"
            anchors.verticalCenter: parent.verticalCenter
            field: inspectorBgColorField
            targetProperty: "widgetBackgroundColor"
            // 未指定時の既定色は Widget 種別の resolved* と揃える
            //（HmiButton=#4cc9f0 / HmiLabel=transparent / HmiNumericField=#ffffff /
            // HmiMeter=#0b1d2a）。Task 51: NumericField は入力欄らしい白背景。
            // Task M-C: Meter はスピードメーターらしい濃紺背景（#0b1d2a）が既定。
            fallback: (editorInspector.editorCanvas.selectedItem
                       && editorInspector.editorCanvas.selectedItem.widgetType === "Label")
                ? "transparent"
                : (editorInspector.editorCanvas.selectedItem
                   && editorInspector.editorCanvas.selectedItem.widgetType === "NumericField")
                    ? "#ffffff"
                : (editorInspector.editorCanvas.selectedItem
                   && editorInspector.editorCanvas.selectedItem.widgetType === "Meter")
                    ? "#0b1d2a" : "#4cc9f0"
        }
    }

    // Task 31: ボーダー＋角丸の編集。背景色 / 文字色 / 文字サイズ（Task 29）と
    // 同型の 2 本立て（onTextEdited/onValueModified で live Item へ書き戻し、
    // Connections.onSelectedItemChanged で表示同期）。数値は **0 が正当値**
    //（borderWidth=0=ボーダーなし、radius=0=角丸なし）なので、SpinBox の
    // from を 0 にし、未指定（-1）は HmiButton の既定（太さ 1 / 角丸 4）を表示する。
    Label {
        text: qsTr("ボーダー色 (#RRGGBB)")
        visible: !editorInspector.selectedIsLabel
    }
    // Task 46: hex TextField + 色スウォッチ（プレビュー / クリックで
    // ColorDialog）。手入力欄はそのまま残す（E2E / 既存導線を維持）。
    // 幅補正は文字色の Row と同じ（leftPadding ぶん詰める）。
    // Task 48: Label はフラット（ボーダー/角丸を持たない）ため、これら 3 項目
    // （ボーダー色 / 太さ / 角丸）を Label 選択時は隠す（背景色・不透明度は残す）。
    Row {
        width: parent.width - parent.leftPadding
        spacing: 6
        visible: !editorInspector.selectedIsLabel

        TextField {
            id: inspectorBorderColorField
            objectName: "inspectorBorderColorField"
            width: parent.width - editorInspector.colorSwatchReserve
            placeholderText: qsTr("#1d3557")
            // 背景色・文字色と同じく、空 または 完全な #RRGGBB の時だけ反映する
            //（途中入力・不正値を live Item に書き戻さない。Codex PR #58 P2）。
            validator: RegularExpressionValidator {
                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
            }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.widgetBorderColor = text
                }
            }
            Connections {
                target: editorInspector.editorCanvas
                function onSelectedItemChanged() {
                    inspectorBorderColorField.text = editorInspector.editorCanvas.selectedItem
                        ? editorInspector.editorCanvas.selectedItem.widgetBorderColor : ""
                }
            }
        }
        ColorSwatch {
            inspector: editorInspector
            objectName: "inspectorBorderColorSwatch"
            anchors.verticalCenter: parent.verticalCenter
            field: inspectorBorderColorField
            targetProperty: "widgetBorderColor"
            // 既定色は Widget 種別の resolvedBorderColor と揃える
            //（HmiButton=#1d3557 / HmiMeter=#9aa5b1）。
            fallback: (editorInspector.editorCanvas.selectedItem
                       && editorInspector.editorCanvas.selectedItem.widgetType === "Meter")
                ? "#9aa5b1" : "#1d3557"
        }
    }

    // ボーダー太さ / 角丸は SpinBox（from: 0 で 0 を選べる）。editable は付けない
    //（Task 27: editable な SpinBox は value プログラム設定で表示が更新されない不具合）。
    Label {
        text: qsTr("ボーダー太さ")
        visible: !editorInspector.selectedIsLabel
    }
    SpinBox {
        id: inspectorBorderWidthSpin
        objectName: "inspectorBorderWidthSpin"
        visible: !editorInspector.selectedIsLabel
        from: 0
        to: 32
        value: 1
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetBorderWidth = value
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                // -1/未指定は既定 1 を表示（HmiButton の resolvedBorderWidth と整合）。
                // 0 は正当値（ボーダーなし）なのでそのまま表示する。
                inspectorBorderWidthSpin.value = (it && it.widgetBorderWidth >= 0)
                    ? it.widgetBorderWidth : 1
            }
        }
    }

    Label {
        text: qsTr("角丸")
        visible: !editorInspector.selectedIsLabel
    }
    SpinBox {
        id: inspectorRadiusSpin
        objectName: "inspectorRadiusSpin"
        visible: !editorInspector.selectedIsLabel
        from: 0
        to: 200
        value: 4
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetRadius = value
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                // -1/未指定は既定 4 を表示（HmiButton の resolvedCornerRadius と整合）。
                // 0 は正当値（角丸なし）なのでそのまま表示する。
                inspectorRadiusSpin.value = (it && it.widgetRadius >= 0)
                    ? it.widgetRadius : 4
            }
        }
    }

    // Task 34: 不透明度は SpinBox（0–100% を 0.0–1.0 にスケール）。editable は
    // 付けない（Task 27 の SpinBox 不具合回避）。書き戻しは value/100.0、表示同期は
    // widgetOpacity*100（未指定 -1 は既定 100% を表示）。
    Label { text: qsTr("不透明度 (%)") }
    SpinBox {
        id: inspectorOpacitySpin
        objectName: "inspectorOpacitySpin"
        from: 0
        to: 100
        value: 100
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetOpacity = value / 100.0
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                // -1/未指定は既定 100%（不透明度 1.0）を表示
                //（HmiButton の resolvedOpacity と整合）。
                inspectorOpacitySpin.value = (it && it.widgetOpacity >= 0)
                    ? Math.round(it.widgetOpacity * 100) : 100
            }
        }
    }
}
