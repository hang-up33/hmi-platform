import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「Trend 詳細（点数 / Y 軸 / 線色 / 周期 / 系列）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: trendSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null

    // このセクション内の入力欄が編集フォーカス中か。InspectorPanel の
    // widgetEditFieldFocused（Canvas undo の 1 操作境界）がこれを OR する。
    readonly property bool editFieldFocused:
        inspectorPointCountSpin.activeFocus
        || inspectorYMinField.activeFocus
        || inspectorYMaxField.activeFocus
        || inspectorLineColorField.activeFocus
        || inspectorSampleMsSpin.activeFocus
        || inspectorYTickCountSpin.activeFocus
    objectName: "inspectorTrendSection"
    title: qsTr("Trend 詳細")
    visible: editorInspector.selectedIsTrend

    // 点数 N（直近何点を表示するか）。0/未指定は HmiTrend 側で既定 60 へ解決。
    // SpinBox（editable なし）で from を 2 にし（折れ線は 2 点以上で意味を持つ）、
    // 未指定（widgetPointCount<=0）は既定 60 を表示する。
    Label { text: qsTr("点数 (N)") }
    SpinBox {
        id: inspectorPointCountSpin
        objectName: "inspectorPointCountSpin"
        from: 2
        to: 2000
        value: 60
        ToolTip.text: qsTr("直近に表示するサンプル点数。満杯になると最古を捨てて横スクロールします")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetPointCount = value
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                // 0/未指定は既定 60 を表示（HmiTrend の resolvedPointCount と整合）。
                inspectorPointCountSpin.value = (it && it.widgetPointCount > 0)
                    ? it.widgetPointCount : 60
            }
        }
    }

    // Y 軸 最小値（presence 方式）。空欄 = 未指定（hasYMin=false → 自動スケール）、
    // 値を入れると hasYMin=true。負値・小数も許す（NumericField min と同型の
    // RegularExpressionValidator＝空 または 数値）。
    Label { text: qsTr("Y 軸 最小値") }
    TextField {
        id: inspectorYMinField
        objectName: "inspectorYMinField"
        width: parent.width
        placeholderText: qsTr("(自動)")
        onActiveFocusChanged: if (activeFocus) selectAll()
        validator: RegularExpressionValidator {
            regularExpression: /^(-?\d*\.?\d*)$/
        }
        ToolTip.text: qsTr("グラフ下端の値。空欄でデータから自動スケールします")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                var t = text.trim()
                var nv = Number(t)
                if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                    editorInspector.editorCanvas.selectedItem.widgetHasYMin = false
                } else {
                    editorInspector.editorCanvas.selectedItem.widgetYMin = nv
                    editorInspector.editorCanvas.selectedItem.widgetHasYMin = true
                }
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorYMinField.text =
                    (editorInspector.editorCanvas.selectedItem && editorInspector.editorCanvas.selectedItem.widgetHasYMin)
                        ? String(editorInspector.editorCanvas.selectedItem.widgetYMin) : ""
            }
        }
    }

    Label { text: qsTr("Y 軸 最大値") }
    TextField {
        id: inspectorYMaxField
        objectName: "inspectorYMaxField"
        width: parent.width
        placeholderText: qsTr("(自動)")
        onActiveFocusChanged: if (activeFocus) selectAll()
        validator: RegularExpressionValidator {
            regularExpression: /^(-?\d*\.?\d*)$/
        }
        ToolTip.text: qsTr("グラフ上端の値。空欄でデータから自動スケールします")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onTextEdited: {
            if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                var t = text.trim()
                var nv = Number(t)
                if (t === "" || t === "-" || t === "." || isNaN(nv)) {
                    editorInspector.editorCanvas.selectedItem.widgetHasYMax = false
                } else {
                    editorInspector.editorCanvas.selectedItem.widgetYMax = nv
                    editorInspector.editorCanvas.selectedItem.widgetHasYMax = true
                }
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorYMaxField.text =
                    (editorInspector.editorCanvas.selectedItem && editorInspector.editorCanvas.selectedItem.widgetHasYMax)
                        ? String(editorInspector.editorCanvas.selectedItem.widgetYMax) : ""
            }
        }
    }

    // 線色（"#RRGGBB" hex の TextField + 色スウォッチ）。背景色等と同じ
    // 2 本立て + ColorDialog 起動（Task 46）。空 = 未指定＝既定線色 #4cc9f0。
    Label { text: qsTr("線色 (#RRGGBB)") }
    Row {
        width: parent.width - parent.leftPadding
        spacing: 6

        TextField {
            id: inspectorLineColorField
            objectName: "inspectorLineColorField"
            width: parent.width - editorInspector.colorSwatchReserve
            placeholderText: qsTr("#4cc9f0")
            validator: RegularExpressionValidator {
                regularExpression: /^(#[0-9A-Fa-f]{6})?$/
            }
            onTextEdited: {
                if (editorInspector.editorCanvas.selectedItem && acceptableInput) {
                    editorInspector.editorCanvas.selectedItem.widgetLineColor = text
                }
            }
            Connections {
                target: editorInspector.editorCanvas
                function onSelectedItemChanged() {
                    inspectorLineColorField.text = editorInspector.editorCanvas.selectedItem
                        ? editorInspector.editorCanvas.selectedItem.widgetLineColor : ""
                }
            }
        }
        ColorSwatch {
            inspector: editorInspector
            objectName: "inspectorLineColorSwatch"
            anchors.verticalCenter: parent.verticalCenter
            field: inspectorLineColorField
            targetProperty: "widgetLineColor"
            // HmiTrend.resolvedLineColor の既定と揃える。
            fallback: "#4cc9f0"
        }
    }

    // サンプル周期[ms]。0/未指定は HmiTrend 側で「変更時サンプルのみ」(方式 A)。
    // >0 で周期 Timer 駆動(方式 B)。SpinBox（editable なし）で from を 0 にし
    // 0=変更時のみを選べるようにする。
    Label { text: qsTr("サンプル周期 (ms)") }
    SpinBox {
        id: inspectorSampleMsSpin
        objectName: "inspectorSampleMsSpin"
        from: 0
        to: 600000
        value: 0
        stepSize: 100
        ToolTip.text: qsTr("0 = 変数の変化時のみ取り込み。1 以上で指定ミリ秒ごとに周期サンプリングします")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetSampleMs = value
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                // 0/未指定はそのまま 0（変更時サンプルのみ）を表示する。
                inspectorSampleMsSpin.value = (it && it.widgetSampleMs > 0)
                    ? it.widgetSampleMs : 0
            }
        }
    }

    // ── 軸 / 凡例（Task 8B-D） ──
    // グリッド線 / 凡例の表示トグルと Y 目盛り本数。いずれも既定 OFF /
    // 既定本数（HmiTrend が 0/負値 → 4 に解決）。CheckBox は離散操作なので
    // 明示 beginEdit/commitEdit、SpinBox は onValueModified の 2 本立て。
    Rectangle { width: parent.width; height: 1; color: "#dddddd" }
    Label { text: qsTr("軸 / 凡例"); font.bold: true; color: "#555555" }

    CheckBox {
        id: inspectorShowGridCheck
        objectName: "inspectorShowGridCheck"
        text: qsTr("グリッド線を表示")
        ToolTip.text: qsTr("水平グリッド線と Y 軸目盛りラベルを描画します")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onToggled: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.beginEdit()
                editorInspector.editorCanvas.selectedItem.widgetShowGrid = checked
                editorInspector.editorCanvas.commitEdit()
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorShowGridCheck.checked = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetShowGrid : false
            }
        }
    }

    CheckBox {
        id: inspectorShowLegendCheck
        objectName: "inspectorShowLegendCheck"
        text: qsTr("凡例を表示")
        ToolTip.text: qsTr("系列の色スウォッチとラベルを凡例として描画します")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onToggled: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.beginEdit()
                editorInspector.editorCanvas.selectedItem.widgetShowLegend = checked
                editorInspector.editorCanvas.commitEdit()
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                inspectorShowLegendCheck.checked = editorInspector.editorCanvas.selectedItem
                    ? editorInspector.editorCanvas.selectedItem.widgetShowLegend : false
            }
        }
    }

    // Y 目盛り本数。0/未指定は HmiTrend 側で既定 4 へ解決。
    // SpinBox（editable なし）で from を 0（=既定）にする。
    Label { text: qsTr("Y 目盛り本数") }
    SpinBox {
        id: inspectorYTickCountSpin
        objectName: "inspectorYTickCountSpin"
        from: 0
        to: 20
        value: 0
        ToolTip.text: qsTr("Y 軸の目盛り本数。0 で既定（4 本）。グリッド線表示時に効きます")
        ToolTip.visible: hovered
        ToolTip.delay: 600
        onValueModified: {
            if (editorInspector.editorCanvas.selectedItem) {
                editorInspector.editorCanvas.selectedItem.widgetYTickCount = value
            }
        }
        Connections {
            target: editorInspector.editorCanvas
            function onSelectedItemChanged() {
                const it = editorInspector.editorCanvas.selectedItem
                inspectorYTickCountSpin.value = (it && it.widgetYTickCount > 0)
                    ? it.widgetYTickCount : 0
            }
        }
    }

    // ── 系列（Task 8B-D） ──
    // 複数系列の編集。各行 = 変数 ComboBox + 線色（hex TextField + スウォッチ）
    // + 凡例ラベル TextField + 削除ボタン。系列は selectedItem.widgetSeries を
    // 配列丸ごと置換で編集する（updateSeries/addSeries/removeSeries）。系列 0 件
    // でも単系列パス（線色 / value バインド）が後方互換で描く。
    Rectangle { width: parent.width; height: 1; color: "#dddddd" }
    Label { text: qsTr("系列"); font.bold: true; color: "#555555" }

    // 系列行の Repeater。model は live Item の widgetSeries。選択切替・
    // 配列置換のたびに widgetSeries が変わり Repeater が再構築される。
    Repeater {
        id: inspectorSeriesRepeater
        objectName: "inspectorSeriesRepeater"
        model: editorInspector.selectedIsTrend && editorInspector.editorCanvas.selectedItem
            ? editorInspector.editorCanvas.selectedItem.widgetSeries : []
        delegate: Column {
            id: seriesRow
            required property var modelData
            required property int index
            width: parent ? parent.width : 0
            spacing: 4

            Row {
                width: parent.width
                spacing: 4

                // 変数 ComboBox（凡例ラベル空のときの既定表示にも使われる）。
                ComboBox {
                    objectName: "seriesVariable_" + seriesRow.index
                    width: 100
                    model: editorInspector.editorRoot.variableNameModel()
                    currentIndex: {
                        const v = seriesRow.modelData
                            && seriesRow.modelData.variable !== undefined
                            ? seriesRow.modelData.variable : ""
                        return Math.max(0, model.indexOf(v))
                    }
                    // "(未選択)" は空文字へ畳む（variableNameModel の先頭）。
                    onActivated: editorInspector.updateSeries(
                        seriesRow.index, "variable",
                        currentIndex === 0 ? "" : currentText)
                }
                Button {
                    objectName: "seriesDelete_" + seriesRow.index
                    text: qsTr("×")
                    onClicked: editorInspector.removeSeries(seriesRow.index)
                }
            }

            Row {
                width: parent.width
                spacing: 6

                TextField {
                    id: seriesColorField
                    objectName: "seriesColor_" + seriesRow.index
                    width: 100
                    text: seriesRow.modelData
                        && seriesRow.modelData.color !== undefined
                        ? seriesRow.modelData.color : ""
                    placeholderText: qsTr("(既定色)")
                    validator: RegularExpressionValidator {
                        regularExpression: /^(#[0-9A-Fa-f]{6})?$/
                    }
                    onEditingFinished: if (acceptableInput)
                        editorInspector.updateSeries(seriesRow.index, "color", text)
                    onActiveFocusChanged:
                        editorInspector.seriesFieldFocusCount += activeFocus ? 1 : -1
                }
                // 色スウォッチ（クリックで系列専用 ColorDialog）。
                Rectangle {
                    objectName: "seriesColorSwatch_" + seriesRow.index
                    anchors.verticalCenter: parent.verticalCenter
                    width: editorInspector.colorSwatchSize
                    height: editorInspector.colorSwatchSize
                    radius: 4
                    border.color: "#999999"
                    border.width: 1
                    color: (seriesColorField.text !== ""
                            && seriesColorField.acceptableInput)
                        ? seriesColorField.text : "#4cc9f0"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editorInspector.editorRoot.openSeriesColorDialog(
                            seriesRow.index, seriesColorField.text)
                    }
                }
            }

            // 凡例ラベル（空 = 変数名へフォールバック）。
            TextField {
                objectName: "seriesLabel_" + seriesRow.index
                width: parent.width
                text: seriesRow.modelData
                    && seriesRow.modelData.label !== undefined
                    ? seriesRow.modelData.label : ""
                placeholderText: qsTr("凡例ラベル（空=変数名）")
                onEditingFinished:
                    editorInspector.updateSeries(seriesRow.index, "label", text)
                onActiveFocusChanged:
                    editorInspector.seriesFieldFocusCount += activeFocus ? 1 : -1
            }

            Rectangle { width: parent.width; height: 1; color: "#eeeeee" }
        }
    }

    Button {
        objectName: "addSeriesButton"
        text: qsTr("系列を追加")
        onClicked: editorInspector.addSeries()
    }
}
