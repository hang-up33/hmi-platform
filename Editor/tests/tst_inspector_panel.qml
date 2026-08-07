import QtQuick
import QtTest

// Task RF-B: Main.qml から切り出したインスペクタ本体（InspectorPanel.qml）の回帰テスト。
//
// 観点（抽出で壊れやすい「ファイルを跨いだ参照」を突く）：
//   - 受け口プロパティ（editorCanvas / editorRoot）越しに Canvas / Window を参照できること
//   - 抽出した派生プロパティ（selectedIsLabel / selectedSupportsClickAction）が
//     選択中 Widget の型で切り替わること
//   - 抽出した関数が **同一ファイル内の入力欄 id** を解決できること
//     （syncGeometryFields → inspectorXField 等のテキストが選択 Item の幾何に追従）
//   - 系列編集（addSeries / updateSeries / removeSeries）が選択 Item の
//     widgetSeries を置換すること（EditorDialogs の系列色ダイアログの書き戻し先）
//   - フォーカス集約プロパティ（inspectorFieldFocused）が既定 false であること
//     （Main.qml の Delete / コピペ ショートカットのガードが参照する）
//
// 配置：Canvas.qml / InspectorPanel.qml を Qt.resolvedUrl で直接ロードする
//   （本体構造を変えないテスト方式。tst_canvas.qml / tst_sample_palette.qml と同じ）。
//   Window（Main.qml）側は Project レベルの変数定義とダイアログ起動だけを持つので、
//   テストでは同じ口を持つスタブ（editorRootStub）で置き換える。
TestCase {
    id: testCase
    name: "InspectorPanel"
    when: windowShown
    visible: true
    width: 1040
    height: 700

    property var canvas: null
    property var panel: null

    Item {
        id: stage
        anchors.fill: parent
    }

    // Main.qml（Window）が持つ口のうち、インスペクタが editorRoot 経由で呼ぶものだけを模す。
    QtObject {
        id: editorRootStub
        property var projectVariables: []
        property int openColorDialogCount: 0
        property int openSeriesColorDialogCount: 0
        function variableNameModel() {
            const names = ["(未選択)"];
            for (let i = 0; i < projectVariables.length; ++i) {
                names.push(projectVariables[i].name);
            }
            return names;
        }
        function addVariable() {}
        function updateVariable(index, key, value) {}
        function removeVariable(index) {}
        function isVariableNameTaken(index, name) { return false; }
        function setVariableSourceEnabled(index, enabled) {}
        function updateVariableSource(index, key, value) {}
        function updateVariableSourceProto(index, proto) {}
        function openColorDialog(field, targetProperty, fallback) { ++openColorDialogCount; }
        function openSeriesColorDialog(index, currentHex) { ++openSeriesColorDialogCount; }
    }

    Component.onCompleted: {
        const canvasComp = Qt.createComponent(Qt.resolvedUrl("../qml/Canvas.qml"));
        if (canvasComp.status !== Component.Ready) {
            console.error("Canvas の読込に失敗:", canvasComp.errorString());
            return;
        }
        canvas = canvasComp.createObject(stage, { x: 0, y: 0 });

        const panelComp = Qt.createComponent(Qt.resolvedUrl("../qml/InspectorPanel.qml"));
        if (panelComp.status !== Component.Ready) {
            console.error("InspectorPanel の読込に失敗:", panelComp.errorString());
            return;
        }
        panel = panelComp.createObject(stage, {
            x: 780, y: 0, height: 700,
            editorCanvas: canvas, editorRoot: editorRootStub
        });
    }

    function init() {
        verify(canvas !== null, "Canvas が未ロード");
        verify(panel !== null, "InspectorPanel が未ロード");
        canvas.clearHistory();
        canvas.selectedWidgetIds = [];
        canvas.widgetModel = [
            { id: "btn001", type: "Button", x: 100, y: 50, width: 120, height: 40, text: "Start" },
            { id: "lbl001", type: "Label", x: 20, y: 200, width: 90, height: 24, text: "Label" },
            { id: "trd001", type: "Trend", x: 300, y: 300, width: 200, height: 120 }
        ];
        tryVerify(function() { return canvas.widgetItems.length > 0; }, 1000,
                  "delegate の生成待ちがタイムアウト");
    }

    // objectName を再帰探索する（インスペクタは ScrollView / Column の深い入れ子）。
    function findByObjectName(item, name) {
        if (!item) {
            return null;
        }
        if (item.objectName === name) {
            return item;
        }
        for (let i = 0; i < item.children.length; ++i) {
            const found = findByObjectName(item.children[i], name);
            if (found) {
                return found;
            }
        }
        return null;
    }

    // 抽出後もパネル自身の objectName は不変（E2E / Spix のパス解決に使う）。
    function test_01_object_name_preserved() {
        compare(panel.objectName, "inspectorPanel");
        verify(findByObjectName(panel, "samplePalette") !== null, "サンプルパレットが無い");
        verify(findByObjectName(panel, "variablePanel") !== null, "変数定義パネルが無い");
        verify(findByObjectName(panel, "inspectorForm") !== null, "単一選択フォームが無い");
    }

    // 型による派生プロパティ（表示の出し分け）が選択に追従する。
    function test_02_type_flags_follow_selection() {
        canvas.selectedWidgetIds = ["btn001"];
        compare(panel.selectedIsLabel, false);
        compare(panel.selectedIsTrend, false);
        compare(panel.selectedSupportsClickAction, true);

        canvas.selectedWidgetIds = ["lbl001"];
        compare(panel.selectedIsLabel, true);
        compare(panel.selectedSupportsClickAction, false);

        canvas.selectedWidgetIds = ["trd001"];
        compare(panel.selectedIsTrend, true);
        compare(panel.selectedSupportsClickAction, false);
    }

    // 抽出した関数が同一ファイル内の入力欄 id を解決できる
    //（幾何欄は Main.qml 時代と同じく syncGeometryFields() で選択 Item に追従する）。
    function test_03_sync_geometry_fields() {
        canvas.selectedWidgetIds = ["btn001"];
        panel.syncGeometryFields();
        compare(findByObjectName(panel, "inspectorXField").text, "100");
        compare(findByObjectName(panel, "inspectorYField").text, "50");
        compare(findByObjectName(panel, "inspectorWidthField").text, "120");
        compare(findByObjectName(panel, "inspectorHeightField").text, "40");

        // 未選択では空欄へ戻る。
        canvas.selectedWidgetIds = [];
        panel.syncGeometryFields();
        compare(findByObjectName(panel, "inspectorXField").text, "");
    }

    // ↑/↓ キー相当の増減も選択 Item へ書き戻る（clamp は validator の範囲）。
    function test_04_nudge_geometry_writes_back() {
        canvas.selectedWidgetIds = ["btn001"];
        panel.syncGeometryFields();
        const field = findByObjectName(panel, "inspectorXField");
        panel.nudgeGeometry(field, "x", 10);
        compare(field.text, "110");
        compare(canvas.selectedItem.x, 110);
    }

    // 系列編集（EditorDialogs の系列色ダイアログが書き戻す先）が選択 Item を更新する。
    function test_05_series_edit() {
        canvas.selectedWidgetIds = ["trd001"];
        compare(panel.currentSeries().length, 0);
        panel.addSeries();
        compare(canvas.selectedItem.widgetSeries.length, 1);
        panel.updateSeries(0, "color", "#ff0000");
        compare(canvas.selectedItem.widgetSeries[0].color, "#ff0000");
        panel.removeSeries(0);
        compare(canvas.selectedItem.widgetSeries.length, 0);
    }

    // Main.qml のショートカットガードが参照するフォーカス集約プロパティ。
    function test_06_focus_flags_default_false() {
        compare(panel.widgetEditFieldFocused, false);
        compare(panel.inspectorFieldFocused, false);
        // 変数パネルの動的入力欄カウントも OR されている（Delete ガード用）。
        panel.variableFieldFocusCount = 1;
        compare(panel.inspectorFieldFocused, true);
        panel.variableFieldFocusCount = 0;
        compare(panel.inspectorFieldFocused, false);
    }
}
