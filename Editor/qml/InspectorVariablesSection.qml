import QtQuick
import QtQuick.Controls

// Task RF-G: インスペクタの「変数定義（Task 40 / 44。選択に依らず常時表示）」セクション。
// InspectorPanel.qml の肥大化解消のため、セクション単位で別ファイルへ切り出した
//（objectName・編集ロジック・Schema は不変）。パネル本体（選択中 Item・型判定・
// フォーカス集約など）への参照は受け口 editorInspector で受ける（同名バインドの
// 自己参照罠を避けるため別名＝MB-4 罠①）。
InspectorSection {
    id: variablesSection

    // InspectorPanel（パネル本体）。
    property var editorInspector: null
    objectName: "variablePanel"
    title: qsTr("変数定義")

    Repeater {
        model: editorInspector.editorRoot.projectVariables
        delegate: Column {
            id: varRow
            required property var modelData
            required property int index
            // Phase 7 / MB-1: source を持つ変数は PLC レジスタ写像つき
            //（接続先 + レジスタ）の編集欄を展開する。
            readonly property var rowSource:
                varRow.modelData.source !== undefined ? varRow.modelData.source : null
            // Phase 9 / OP-1: 接続 proto（"modbusTcp" / "opcua"）。欠落時は modbusTcp。
            readonly property string rowProto:
                (varRow.rowSource && varRow.rowSource.proto !== undefined
                 && varRow.rowSource.proto !== "") ? varRow.rowSource.proto : "modbusTcp"
            width: parent.width
            spacing: 4

            Row {
                width: parent.width
                spacing: 4

                TextField {
                    id: varNameField
                    objectName: "variableName_" + varRow.index
                    width: 80
                    text: varRow.modelData.name !== undefined ? varRow.modelData.name : ""
                    placeholderText: qsTr("名前")
                    // **空名・重複名を保存しない**：空名は VariableData.isValidJson が
                    // 無効としプロジェクト全体が再読込不能になり（Codex PR #80 [P1]）、
                    // 重複名は VariableStore（名前キー map）で後勝ちになり参照先を
                    // 区別できなくなる（Codex PR #80 [P2]）。どちらも元の名前へ戻す
                    // （削除は × ボタンで行う）。
                    onEditingFinished: {
                        if (text.length > 0
                                && !editorInspector.editorRoot.isVariableNameTaken(varRow.index, text)) {
                            editorInspector.editorRoot.updateVariable(varRow.index, "name", text)
                        } else {
                            text = Qt.binding(function() {
                                return varRow.modelData.name !== undefined
                                    ? varRow.modelData.name : ""
                            })
                        }
                    }
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }
                ComboBox {
                    objectName: "variableType_" + varRow.index
                    width: 80
                    model: ["bool", "int", "real", "string"]
                    currentIndex: Math.max(0, model.indexOf(varRow.modelData.type))
                    onActivated: editorInspector.editorRoot.updateVariable(varRow.index, "type", currentText)
                }
                TextField {
                    objectName: "variableInitial_" + varRow.index
                    width: 60
                    text: varRow.modelData.initial !== undefined ? varRow.modelData.initial : ""
                    placeholderText: qsTr("初期値")
                    onEditingFinished: editorInspector.editorRoot.updateVariable(varRow.index, "initial", text)
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }
                Button {
                    objectName: "variableDelete_" + varRow.index
                    text: qsTr("×")
                    onClicked: editorInspector.editorRoot.removeVariable(varRow.index)
                }
            }

            // Phase 7 / MB-1: PLC 接続写像（source）の有効化トグル。
            // チェックで variable.source を付ける（内部変数 ↔ PLC 変数）。
            CheckBox {
                objectName: "variableSourceEnabled_" + varRow.index
                text: qsTr("PLC レジスタに割当")
                checked: varRow.rowSource !== null
                onToggled: editorInspector.editorRoot.setVariableSourceEnabled(varRow.index, checked)
            }

            // 接続先 + レジスタ写像の編集欄（source ありのときのみ）。実通信はせず
            // 入力値を JSON（保存時 connections[] と variable.source）へ書くだけ。
            Grid {
                objectName: "variableSourceGrid_" + varRow.index
                visible: varRow.rowSource !== null
                columns: 2
                rowSpacing: 4
                columnSpacing: 6
                leftPadding: 12

                // Phase 9 / OP-1: プロトコル選択。modbusTcp（host/port/unitId/reg/
                // address）と opcua（endpoint/nodeId）で下の入力欄を出し分ける。
                Label { text: qsTr("プロトコル") }
                ComboBox {
                    objectName: "variableSourceProto_" + varRow.index
                    width: 120
                    model: ["modbusTcp", "opcua"]
                    currentIndex: Math.max(0, model.indexOf(varRow.rowProto))
                    onActivated: editorInspector.editorRoot.updateVariableSourceProto(varRow.index, currentText)
                }

                // --- Modbus 用フィールド（proto === "modbusTcp" のとき表示） ---
                Label {
                    text: qsTr("ホスト")
                    visible: varRow.rowProto === "modbusTcp"
                }
                TextField {
                    objectName: "variableSourceHost_" + varRow.index
                    visible: varRow.rowProto === "modbusTcp"
                    width: 120
                    text: varRow.rowSource ? (varRow.rowSource.host !== undefined ? varRow.rowSource.host : "") : ""
                    placeholderText: qsTr("192.168.0.10")
                    onEditingFinished: editorInspector.editorRoot.updateVariableSource(varRow.index, "host", text)
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }

                Label {
                    text: qsTr("ポート")
                    visible: varRow.rowProto === "modbusTcp"
                }
                TextField {
                    objectName: "variableSourcePort_" + varRow.index
                    visible: varRow.rowProto === "modbusTcp"
                    width: 80
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1; top: 65535 }
                    text: varRow.rowSource ? String(varRow.rowSource.port !== undefined ? varRow.rowSource.port : 502) : ""
                    placeholderText: qsTr("502")
                    onEditingFinished: if (acceptableInput) editorInspector.editorRoot.updateVariableSource(varRow.index, "port", parseInt(text, 10))
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }

                Label {
                    text: qsTr("Unit ID")
                    visible: varRow.rowProto === "modbusTcp"
                }
                TextField {
                    objectName: "variableSourceUnitId_" + varRow.index
                    visible: varRow.rowProto === "modbusTcp"
                    width: 80
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 0; top: 255 }
                    text: varRow.rowSource ? String(varRow.rowSource.unitId !== undefined ? varRow.rowSource.unitId : 1) : ""
                    placeholderText: qsTr("1")
                    onEditingFinished: if (acceptableInput) editorInspector.editorRoot.updateVariableSource(varRow.index, "unitId", parseInt(text, 10))
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }

                Label {
                    text: qsTr("レジスタ")
                    visible: varRow.rowProto === "modbusTcp"
                }
                ComboBox {
                    objectName: "variableSourceReg_" + varRow.index
                    visible: varRow.rowProto === "modbusTcp"
                    width: 120
                    model: ["coil", "discrete", "input", "holding"]
                    currentIndex: Math.max(0, model.indexOf(varRow.rowSource ? varRow.rowSource.reg : "holding"))
                    onActivated: editorInspector.editorRoot.updateVariableSource(varRow.index, "reg", currentText)
                }

                // address は 0 始まりのプロトコル番地（JSON / 内部の正準は 0 ベース）。
                Label {
                    text: qsTr("アドレス")
                    visible: varRow.rowProto === "modbusTcp"
                }
                TextField {
                    objectName: "variableSourceAddress_" + varRow.index
                    visible: varRow.rowProto === "modbusTcp"
                    width: 80
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 0; top: 65535 }
                    text: varRow.rowSource ? String(varRow.rowSource.address !== undefined ? varRow.rowSource.address : 0) : ""
                    placeholderText: qsTr("0")
                    onEditingFinished: if (acceptableInput) editorInspector.editorRoot.updateVariableSource(varRow.index, "address", parseInt(text, 10))
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }

                // --- OPC-UA 用フィールド（proto === "opcua" のとき表示） ---
                Label {
                    text: qsTr("エンドポイント")
                    visible: varRow.rowProto === "opcua"
                }
                TextField {
                    objectName: "variableSourceEndpoint_" + varRow.index
                    visible: varRow.rowProto === "opcua"
                    width: 180
                    text: varRow.rowSource ? (varRow.rowSource.endpoint !== undefined ? varRow.rowSource.endpoint : "") : ""
                    placeholderText: qsTr("opc.tcp://192.168.0.20:4840")
                    onEditingFinished: editorInspector.editorRoot.updateVariableSource(varRow.index, "endpoint", text)
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }

                Label {
                    text: qsTr("ノード ID")
                    visible: varRow.rowProto === "opcua"
                }
                TextField {
                    objectName: "variableSourceNodeId_" + varRow.index
                    visible: varRow.rowProto === "opcua"
                    width: 180
                    text: varRow.rowSource ? (varRow.rowSource.nodeId !== undefined ? varRow.rowSource.nodeId : "") : ""
                    placeholderText: qsTr("ns=2;s=Spindle.Temp")
                    onEditingFinished: editorInspector.editorRoot.updateVariableSource(varRow.index, "nodeId", text)
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }

                // ポーリング周期は両プロトコル共通。OPC-UA は購読が主なので poll=0
                //（購読のみ）を許す＝下限を proto で切替える（opcua→0 / modbusTcp→1）。
                // Codex/CodeRabbit PR #140。
                Label { text: qsTr("ポーリング(ms)") }
                TextField {
                    objectName: "variableSourcePoll_" + varRow.index
                    width: 80
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator {
                        bottom: varRow.rowProto === "opcua" ? 0 : 1
                        top: 600000
                    }
                    text: varRow.rowSource
                        ? String(varRow.rowSource.poll !== undefined
                                 ? varRow.rowSource.poll
                                 : (varRow.rowProto === "opcua" ? 0 : 1000))
                        : ""
                    placeholderText: varRow.rowProto === "opcua" ? qsTr("0") : qsTr("1000")
                    onEditingFinished: if (acceptableInput) editorInspector.editorRoot.updateVariableSource(varRow.index, "poll", parseInt(text, 10))
                    onActiveFocusChanged: editorInspector.variableFieldFocusCount += activeFocus ? 1 : -1
                }
            }

            Rectangle {
                visible: varRow.index < editorInspector.editorRoot.projectVariables.length - 1
                width: parent.width
                height: 1
                color: "#eeeeee"
            }
        }
    }

    Button {
        objectName: "addVariableButton"
        text: qsTr("変数を追加")
        onClicked: editorInspector.editorRoot.addVariable()
    }
}
