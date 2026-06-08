import QtQuick
import QtTest

// Task 14: Canvas の検証。
//
// 観点：
//   - canvasWidth / canvasHeight のデフォルト（800 / 600）
//   - 初期 widgetModel から EditableWidget が 1 個生成される
//   - widgetModel を別の配列に差し替えると children が再生成される
//   - 空配列にすると children が 0 件になる
//
// 配置：
//   Canvas.qml は内部で `import HmiWidgets` する。テスト実行体に
//   hmi_widgetsplugin がリンクされていれば解決される（Task 13 で確立）。
//   Canvas を Qt.createComponent + createObject で stage の子として生成し、
//   widgetItems プロパティ（widgetLayer.children alias）を通じて配下を観察する。
//
// 注意：widgetItems には Repeater 自身も含まれる（QQuickRepeater）。
//   widgetId プロパティの有無で EditableWidget だけを数える。
TestCase {
    id: testCase
    name: "Canvas"
    when: windowShown
    visible: true
    width: 900
    height: 700

    property var canvas: null

    Item {
        id: stage
        anchors.fill: parent
    }

    Component.onCompleted: {
        const comp = Qt.createComponent(Qt.resolvedUrl("../qml/Canvas.qml"));
        if (comp.status !== Component.Ready) {
            console.error("Canvas の読込に失敗:", comp.errorString());
            return;
        }
        canvas = comp.createObject(stage);
    }

    function init() {
        verify(canvas !== null, "Canvas が未ロード");
        // 各テストの前に既定状態へ戻す（test 関数は alphabetical 実行のため
        // 前の test が変更した状態が次に漏れないように）
        canvas.canvasWidth = 800;
        canvas.canvasHeight = 600;
        canvas.selectedWidgetId = "";
        canvas.snapEnabled = false;  // Task 35: テスト間でスナップ状態を漏らさない
        canvas.gridSize = 8;
        canvas.widgetModel = [
            { id: "btn001", type: "Button", x: 100, y: 50, width: 120, height: 40,
              text: "Start", tag: "PLC.START" }
        ];
        // Repeater の delegate 生成は非同期/段階的なので、初期 model の
        // 反映完了を待ってから各 test_* に渡す。
        tryVerify(function() { return editableChildren().length === 1; }, 1000,
                  "init: 初期 widgetModel が Repeater に反映されない");
    }

    // widgetItems から EditableWidget だけを抽出する（Repeater 自身を除く）
    function editableChildren() {
        const items = canvas.widgetItems;
        const result = [];
        for (let i = 0; i < items.length; ++i) {
            if (items[i].widgetId !== undefined)
                result.push(items[i]);
        }
        return result;
    }

    function test_default_canvas_size() {
        compare(canvas.canvasWidth, 800);
        compare(canvas.canvasHeight, 600);
        compare(canvas.width, 800);
        compare(canvas.height, 600);
    }

    function test_initial_model_creates_one_editable_widget() {
        // init() で初期 model 反映完了を待っているが、本テストは件数を
        // 直接検証するため tryVerify をここでも明示する。
        tryVerify(function() { return editableChildren().length === 1; }, 1000);
        const widgets = editableChildren();
        compare(widgets.length, 1);

        const w = widgets[0];
        compare(w.widgetId, "btn001");
        compare(w.widgetType, "Button");
        compare(w.widgetText, "Start");
        compare(w.widgetTag, "PLC.START");
        compare(w.x, 100);
        compare(w.y, 50);
        compare(w.width, 120);
        compare(w.height, 40);
    }

    function test_replace_model_recreates_widgets() {
        canvas.widgetModel = [
            { id: "a", type: "Button", x:   0, y: 0, width: 80, height: 30, text: "A", tag: "" },
            { id: "b", type: "Button", x: 100, y: 0, width: 80, height: 30, text: "B", tag: "" },
            { id: "c", type: "Button", x: 200, y: 0, width: 80, height: 30, text: "C", tag: "" }
        ];

        // Repeater の delegate 生成/破棄は段階的に進むため、件数が安定する
        // まで tryVerify で待つ。即時 length 比較は CI 負荷次第で flaky になる
        // （Codex P2 指摘より）。
        tryVerify(function() { return editableChildren().length === 3; }, 1000,
                  "widgetModel 差替後 3 件にならない");
        const widgets = editableChildren();

        const ids = widgets.map(function(w) { return w.widgetId; });
        verify(ids.indexOf("a") !== -1, "a が無い: " + ids);
        verify(ids.indexOf("b") !== -1, "b が無い: " + ids);
        verify(ids.indexOf("c") !== -1, "c が無い: " + ids);
    }

    function test_empty_model_creates_no_widgets() {
        canvas.widgetModel = [];

        // 空配列への差替も Repeater の破棄完了を tryVerify で待つ。
        tryVerify(function() { return editableChildren().length === 0; }, 1000,
                  "widgetModel 空配列差替後 0 件にならない");
    }

    function test_canvas_size_can_be_overridden() {
        canvas.canvasWidth = 640;
        canvas.canvasHeight = 480;

        compare(canvas.width, 640);
        compare(canvas.height, 480);
    }

    // Task 25: 選択状態は selectedWidgetId（Canvas が所有）に集約され、
    // 既定は未選択（空文字）。
    function test_selected_widget_id_defaults_empty() {
        compare(canvas.selectedWidgetId, "");
    }

    // Task 25: selectedWidgetId を設定すると一致する delegate だけが
    // selected になる（delegate 側 `selected: widgetId === selectedWidgetId`
    // バインドの結線確認）。
    function test_selecting_id_marks_matching_delegate() {
        canvas.widgetModel = [
            { id: "a", type: "Button", x:   0, y: 0, width: 80, height: 30, text: "A", tag: "" },
            { id: "b", type: "Button", x: 100, y: 0, width: 80, height: 30, text: "B", tag: "" }
        ];
        tryVerify(function() { return editableChildren().length === 2; }, 1000,
                  "2 件モデルが反映されない");

        canvas.selectedWidgetId = "b";
        tryVerify(function() {
            const ws = editableChildren();
            if (ws.length !== 2) return false;
            for (let i = 0; i < ws.length; ++i) {
                if (ws[i].selected !== (ws[i].widgetId === "b")) return false;
            }
            return true;
        }, 1000, "選択状態が selectedWidgetId に追従しない");
    }

    // Task 25: 選択解除（空文字）で全 delegate の selected が false に戻る。
    function test_clearing_selection_unmarks_all() {
        canvas.selectedWidgetId = "btn001";
        tryVerify(function() {
            const ws = editableChildren();
            return ws.length === 1 && ws[0].selected === true;
        }, 1000, "btn001 が選択状態にならない");

        canvas.selectedWidgetId = "";
        tryVerify(function() {
            const ws = editableChildren();
            return ws.length === 1 && ws[0].selected === false;
        }, 1000, "選択解除後も selected が残る");
    }

    // Task 26: selectedItem は選択 id の live な EditableWidget を指す
    // （Main.qml のインスペクタはこれを編集対象にする）。未選択は null。
    function test_selected_item_resolves_to_live_item() {
        compare(canvas.selectedItem, null);

        canvas.selectedWidgetId = "btn001";
        tryVerify(function() {
            return canvas.selectedItem !== null
                && canvas.selectedItem.widgetId === "btn001";
        }, 1000, "selectedItem が btn001 の live Item を指さない");

        canvas.selectedWidgetId = "";
        tryVerify(function() { return canvas.selectedItem === null; }, 1000,
                  "選択解除後も selectedItem が残る");
    }

    // Task 26: addWidget() で widgetModel 再代入 → Repeater 再生成が起きても、
    // selectedItem は破棄済みの古い Item を掴み続けず、同一 id の **新しい live
    // Item** に解決し直される（Codex PR #52 P2 指摘の回帰固定）。再解決された
    // Item へ書けば反映されること（= 破棄済み参照でないこと）まで検証する。
    function test_selected_item_reresolves_after_add() {
        canvas.selectedWidgetId = "btn001";
        tryVerify(function() {
            return canvas.selectedItem !== null
                && canvas.selectedItem.widgetId === "btn001";
        }, 1000, "前提：btn001 が選択 Item にならない");

        // 追加でモデル再代入 → Repeater が delegate を作り直す
        canvas.addWidget();

        // 再生成後も btn001 の live Item（現存 children の中）に解決し直される
        tryVerify(function() {
            const sel = canvas.selectedItem;
            return sel !== null
                && sel.widgetId === "btn001"
                && editableChildren().indexOf(sel) !== -1;
        }, 1000, "再生成後に selectedItem が live な btn001 を指さない");

        // 解決し直された Item へ書けば反映される（破棄済み参照なら反映されない）
        canvas.selectedItem.widgetText = "Edited";
        compare(canvas.selectedItem.widgetText, "Edited");
    }

    // Task 29: 選択中 live Item のスタイルメタ（背景色 / 文字色 / 文字サイズ）を
    // 直接更新できる（インスペクタの onTextEdited / onValueModified が書き戻す先）。
    // var 配列を据え置きつつ live Item を真実とする設計の確認。
    function test_style_props_are_writable_on_live_item() {
        canvas.selectedWidgetId = "btn001";
        tryVerify(function() {
            return canvas.selectedItem !== null
                && canvas.selectedItem.widgetId === "btn001";
        }, 1000, "btn001 が選択 Item にならない");

        canvas.selectedItem.widgetBackgroundColor = "#ff0000";
        canvas.selectedItem.widgetTextColor = "#000000";
        canvas.selectedItem.widgetFontSize = 22;

        compare(canvas.selectedItem.widgetBackgroundColor, "#ff0000");
        compare(canvas.selectedItem.widgetTextColor, "#000000");
        compare(canvas.selectedItem.widgetFontSize, 22);

        // snapshotModel（保存経路）にもスタイルが乗ること（C++ ブリッジへ渡る値）。
        const snap = canvas.snapshotModel();
        let entry = null;
        for (let i = 0; i < snap.length; ++i) {
            if (snap[i].id === "btn001") { entry = snap[i]; break; }
        }
        verify(entry !== null, "snapshotModel に btn001 が無い");
        compare(entry.backgroundColor, "#ff0000");
        compare(entry.textColor, "#000000");
        compare(entry.fontSize, 22);
    }

    // Task 31: 選択中 live Item のボーダー＋角丸メタ（色 / 太さ / 角丸）を直接更新でき、
    // snapshotModel（保存経路）にも乗ること。**borderWidth=0（ボーダーなし）** が
    // スナップショットで 0 のまま保たれること（未指定 -1 と混同して落とさない）も固定する。
    function test_border_props_are_writable_on_live_item() {
        canvas.selectedWidgetId = "btn001";
        tryVerify(function() {
            return canvas.selectedItem !== null
                && canvas.selectedItem.widgetId === "btn001";
        }, 1000, "btn001 が選択 Item にならない");

        canvas.selectedItem.widgetBorderColor = "#112233";
        canvas.selectedItem.widgetBorderWidth = 0;   // 0 = ボーダーなし（正当値）
        canvas.selectedItem.widgetRadius = 12;

        compare(canvas.selectedItem.widgetBorderColor, "#112233");
        compare(canvas.selectedItem.widgetBorderWidth, 0);
        compare(canvas.selectedItem.widgetRadius, 12);

        const snap = canvas.snapshotModel();
        let entry = null;
        for (let i = 0; i < snap.length; ++i) {
            if (snap[i].id === "btn001") { entry = snap[i]; break; }
        }
        verify(entry !== null, "snapshotModel に btn001 が無い");
        compare(entry.borderColor, "#112233");
        compare(entry.borderWidth, 0);  // 0 が落ちずに保存経路へ乗る
        compare(entry.radius, 12);
    }

    // Task 33: 選択中 live Item のフォント詳細メタ（太字 / 斜体 / フォント）を直接更新でき、
    // snapshotModel（保存経路）にも乗ること。bool は false 自体が「指定なし」と一致するため
    // 片側（bold=true / italic=false）でも正しくスナップショットされることを固定する。
    function test_font_props_are_writable_on_live_item() {
        canvas.selectedWidgetId = "btn001";
        tryVerify(function() {
            return canvas.selectedItem !== null
                && canvas.selectedItem.widgetId === "btn001";
        }, 1000, "btn001 が選択 Item にならない");

        canvas.selectedItem.widgetFontBold = true;
        canvas.selectedItem.widgetFontItalic = false;
        canvas.selectedItem.widgetFontFamily = "Courier New";

        compare(canvas.selectedItem.widgetFontBold, true);
        compare(canvas.selectedItem.widgetFontItalic, false);
        compare(canvas.selectedItem.widgetFontFamily, "Courier New");

        const snap = canvas.snapshotModel();
        let entry = null;
        for (let i = 0; i < snap.length; ++i) {
            if (snap[i].id === "btn001") { entry = snap[i]; break; }
        }
        verify(entry !== null, "snapshotModel に btn001 が無い");
        compare(entry.fontBold, true);
        compare(entry.fontItalic, false);
        compare(entry.fontFamily, "Courier New");
    }

    // Task 34: 選択中 live Item の配置 + 不透明度メタ（widgetHAlign / widgetVAlign /
    // widgetOpacity）を直接更新でき、snapshotModel（保存経路）にも乗ること。opacity は
    // **live Item では widgetOpacity** だが、snapshot の JSON キーは **opacity** にマップ
    // されることを固定する（組込み Item.opacity 衝突回避のリネームが保存で正しく戻る）。
    // 0.0（完全透明）も正当値としてスナップショットされることを確認する。
    function test_align_opacity_props_are_writable_on_live_item() {
        canvas.selectedWidgetId = "btn001";
        tryVerify(function() {
            return canvas.selectedItem !== null
                && canvas.selectedItem.widgetId === "btn001";
        }, 1000, "btn001 が選択 Item にならない");

        canvas.selectedItem.widgetHAlign = "left";
        canvas.selectedItem.widgetVAlign = "top";
        canvas.selectedItem.widgetOpacity = 0.0;

        compare(canvas.selectedItem.widgetHAlign, "left");
        compare(canvas.selectedItem.widgetVAlign, "top");
        compare(canvas.selectedItem.widgetOpacity, 0.0);

        const snap = canvas.snapshotModel();
        let entry = null;
        for (let i = 0; i < snap.length; ++i) {
            if (snap[i].id === "btn001") { entry = snap[i]; break; }
        }
        verify(entry !== null, "snapshotModel に btn001 が無い");
        compare(entry.hAlign, "left");
        compare(entry.vAlign, "top");
        // live の widgetOpacity が JSON キー opacity にマップされて乗る。
        compare(entry.opacity, 0.0);
    }

    // Task 35: グリッドスナップの既定値（OFF / 8px）と、Canvas → delegate への伝播、
    // および吸着ロジック（snappedValue）を回帰固定する。実際の吸着は移動 / リサイズの
    // 確定ハンドラで起きる（マウス操作が必要）が、その中核は純関数 snappedValue なので
    // ここで直接呼んで検証する（OFF なら素通し、ON なら gridSize へ丸め）。
    function test_grid_snap_defaults_and_logic() {
        // 既定は OFF / 8px。
        compare(canvas.snapEnabled, false);
        compare(canvas.gridSize, 8);

        canvas.snapEnabled = true;
        canvas.gridSize = 8;

        const items = editableChildren();
        compare(items.length, 1);
        const item = items[0];
        // Canvas の設定が delegate へ伝播している。
        compare(item.snapEnabled, true);
        compare(item.gridSize, 8);

        // ON：最寄りの格子（8 の倍数）へ丸める。13→16、20→24（2.5 は四捨五入で 3）、4→8。
        compare(item.snappedValue(13), 16);
        compare(item.snappedValue(20), 24);
        compare(item.snappedValue(4), 8);
        compare(item.snappedValue(16), 16);  // 既に格子上なら不変

        // OFF：素通し。
        canvas.snapEnabled = false;
        compare(item.snapEnabled, false);
        compare(item.snappedValue(13), 13);
    }

    // Task 29: deleteWidget(id) は該当 id を除いて widgetModel を再代入し、
    // 選択中だった場合は選択を解除する（インスペクタ削除ボタン / Delete キーの
    // 呼び先）。他 widget は残ることも確認する（構造変更スナップショットの対称性）。
    function test_delete_widget_removes_only_target() {
        canvas.widgetModel = [
            { id: "a", type: "Button", x:   0, y: 0, width: 80, height: 30, text: "A", tag: "" },
            { id: "b", type: "Button", x: 100, y: 0, width: 80, height: 30, text: "B", tag: "" },
            { id: "c", type: "Button", x: 200, y: 0, width: 80, height: 30, text: "C", tag: "" }
        ];
        tryVerify(function() { return editableChildren().length === 3; }, 1000,
                  "3 件モデルが反映されない");

        canvas.selectedWidgetId = "b";
        canvas.deleteWidget("b");

        // b だけ消えて a / c は残る
        tryVerify(function() {
            const ids = editableChildren().map(function(w) { return w.widgetId; });
            return ids.length === 2
                && ids.indexOf("a") !== -1
                && ids.indexOf("c") !== -1
                && ids.indexOf("b") === -1;
        }, 1000, "deleteWidget が対象だけを消さない");

        // 選択中だった b を消したので選択は解除される
        compare(canvas.selectedWidgetId, "");
        compare(canvas.selectedItem, null);
    }

    // Task 29: 引数省略の deleteWidget() は現在の選択 id を対象にする
    //（インスペクタ削除ボタンは選択 id を明示渡しするが、フォールバック仕様を固定）。
    function test_delete_widget_uses_selection_when_no_arg() {
        canvas.selectedWidgetId = "btn001";
        tryVerify(function() { return canvas.selectedItem !== null; }, 1000,
                  "btn001 が選択されない");

        canvas.deleteWidget();

        tryVerify(function() { return editableChildren().length === 0; }, 1000,
                  "引数省略 deleteWidget が選択 Widget を消さない");
        compare(canvas.selectedWidgetId, "");
    }

    // Task 30: 削除（構造変更）が「他 widget の未保存スタイル編集」を巻き戻さない
    // ことを固定する。Task 29 の delete テストは残存 id 集合の正しさを見るが、
    // 本テストは snapshotModel が live Item のスタイル値（背景色 / 文字色 /
    // 文字サイズ）を取り込んでから再代入する保証（Phase 4 設計指針「live Item を
    // 真実・構造変更時のみスナップショット」）をスタイルフィールドで検証する。
    function test_delete_preserves_other_widgets_style_edits() {
        canvas.widgetModel = [
            { id: "keep", type: "Button", x:   0, y: 0, width: 80, height: 30, text: "Keep", tag: "" },
            { id: "gone", type: "Button", x: 100, y: 0, width: 80, height: 30, text: "Gone", tag: "" }
        ];
        tryVerify(function() { return editableChildren().length === 2; }, 1000,
                  "2 件モデルが反映されない");

        // keep のスタイルを未保存編集（インスペクタの書き戻し相当：live Item を直接更新）
        canvas.selectedWidgetId = "keep";
        tryVerify(function() {
            return canvas.selectedItem !== null && canvas.selectedItem.widgetId === "keep";
        }, 1000, "keep が選択 Item にならない");
        canvas.selectedItem.widgetBackgroundColor = "#123456";
        canvas.selectedItem.widgetTextColor = "#abcdef";
        canvas.selectedItem.widgetFontSize = 27;

        // gone を削除（構造変更 → Repeater 再生成）。選択中は keep なので維持される。
        canvas.deleteWidget("gone");

        // keep だけ残り、スタイル編集が再生成後の live Item に保たれている
        tryVerify(function() {
            const ch = editableChildren();
            return ch.length === 1 && ch[0].widgetId === "keep";
        }, 1000, "削除後に keep が残らない");

        const keep = editableChildren()[0];
        compare(keep.widgetBackgroundColor, "#123456");
        compare(keep.widgetTextColor, "#abcdef");
        compare(keep.widgetFontSize, 27);

        // 保存経路（snapshotModel）にも未保存スタイル編集が乗っている
        const snap = canvas.snapshotModel();
        compare(snap.length, 1);
        compare(snap[0].id, "keep");
        compare(snap[0].backgroundColor, "#123456");
        compare(snap[0].textColor, "#abcdef");
        compare(snap[0].fontSize, 27);
    }
}
