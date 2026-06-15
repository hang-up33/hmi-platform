import QtQuick
import QtTest
import HmiWidgets

// Task 50: HmiNumericField（数値入力 Widget）のプロパティ反映・既定フォールバック・
// editable 切替・選択中継 clicked・commitValue()/valueCommitted の検証。
// HmiButton / HmiLabel（tst_hmi_button.qml / tst_hmi_label.qml）と同方式。
//
// 観点：
//   - デフォルトプロパティ（text="0", editable=true, width=120, height=40）
//   - resolved* 既定（背景=#ffffff / 文字色=#1d3557 / fontSize=14 / 枠=#9aa5b1・幅 1 /
//     角丸 4 / hAlign=右 / vAlign=中央 / opacity=1.0）が HmiNumericField 1 箇所に集約
//     されている（入力欄らしい既定。Button の塗り・Label の透明とは違う差分を固定）
//   - editable を切替えると内部 TextField の readOnly と選択用 MouseArea の enabled が反転
//   - editable:false（Editor）で選択用 MouseArea のクリックが clicked シグナルを発火する
//   - commitValue() で valueCommitted(text) が emit される（write 経路は delegate 側＝Task 51）
//
// 重要：TestCase に visible: true を明示する（tst_hmi_button.qml と同じ理由＝
//   MouseArea / TextField がクリック・フォーカスを受けるため）。
TestCase {
    id: testCase
    name: "HmiNumericField"
    when: windowShown
    visible: true
    width: 200
    height: 100

    HmiNumericField {
        id: field
        x: 0
        y: 0
    }

    SignalSpy {
        id: clickedSpy
        target: field
        signalName: "clicked"
    }

    SignalSpy {
        id: committedSpy
        target: field
        signalName: "valueCommitted"
    }

    // フォーカスを field から奪って「編集確定（blur）」を模すための受け皿。
    TextInput {
        id: focusSink
        objectName: "focusSink"
        x: 0
        y: 60
        width: 50
        height: 20
    }

    function init() {
        // テスト間の独立性確保（CodeRabbit PR #105）：まず前テストのフォーカスを確実に剥がす。
        // `focus = false` より確実に active focus を移すため testCase 自身へ forceActiveFocus する
        // （これで TextField に残ったフォーカス／確定シグナルを出し切ってから下でスパイをクリアする）。
        testCase.forceActiveFocus();
        focusSink.text = "";
        // 各 test_* 実行前にプロパティをリセット
        field.text = "0";
        field.editable = true;
        field.width = 120;
        field.height = 40;
        field.backgroundColor = "";
        field.textColor = "";
        field.fontSize = 0;
        field.borderColor = "";
        field.borderWidth = -1;
        field.cornerRadius = -1;
        field.hAlign = "";
        field.vAlign = "";
        field.widgetOpacity = -1;
        field.widgetEnabled = true;
        field.isReal = false;
        // Task 54: 数値範囲も毎テストでリセット（presence は未指定 = false）。
        field.minValue = 0;
        field.maxValue = 0;
        field.hasMin = false;
        field.hasMax = false;
        // 一部テストは内部 TextField.text を直接代入して `text: root.text` 宣言バインドを
        // 切る（実機の編集を模すため）。次テストへ持ち越さないよう、毎 init で内部 TextField の
        // バインドを貼り直してから field.text を初期化する（貼り直さないと前テストの
        // 直接代入値が内部に残る）。
        const tf = findByObjectName(field, "numericTextField");
        if (tf) {
            // 実バインド（`text: root._displayText(root.text)`）と一致させる
            // （Codex PR #112 [Minor]：real は表示も固定小数へ整形する）。
            tf.text = Qt.binding(function() { return field._displayText(field.text) });
        }
        // commit の重複排除キャッシュも初期化（前テストの確定値を持ち越さない）。
        field._lastCommittedText = "";
        // スパイは最後にクリア（上のフォーカス操作由来の stray シグナルを残さない）。
        clickedSpy.clear();
        committedSpy.clear();
    }

    function test_default_properties() {
        compare(field.text, "0");
        compare(field.editable, true);
        compare(field.width, 120);
        compare(field.height, 40);
    }

    // 未指定（空 / 0 / -1）のとき resolved* が **NumericField の既定**にフォールバックする。
    // 入力欄らしい既定（白背景 / 濃文字 / 細グレー枠 / 角丸 4 / 右寄せ）を固定する。
    function test_resolved_defaults_when_unspecified() {
        compare(field.resolvedBackgroundColor, Qt.color("#ffffff"));
        compare(field.resolvedTextColor, Qt.color("#1d3557"));
        compare(field.resolvedFontSize, 14);
        compare(field.resolvedBorderColor, Qt.color("#9aa5b1"));
        compare(field.resolvedBorderWidth, 1);
        compare(field.resolvedCornerRadius, 4);
        // 数値入力の既定配置は右寄せ / 中央（Button=中央/中央・Label=左/中央 とは違う）。
        compare(field.resolvedHAlign, Text.AlignRight);
        compare(field.resolvedVAlign, Text.AlignVCenter);
        compare(field.resolvedOpacity, 1.0);
    }

    // 明示値が resolved* へ反映される（配置の文字列 → enum マップを含む）。
    function test_explicit_values_are_resolved() {
        field.backgroundColor = "#222222";
        field.textColor = "#ffffff";
        field.fontSize = 20;
        field.borderColor = "#ff0000";
        field.borderWidth = 3;
        field.cornerRadius = 8;
        field.hAlign = "left";
        field.vAlign = "top";

        compare(field.resolvedBackgroundColor, Qt.color("#222222"));
        compare(field.resolvedTextColor, Qt.color("#ffffff"));
        compare(field.resolvedFontSize, 20);
        compare(field.resolvedBorderColor, Qt.color("#ff0000"));
        compare(field.resolvedBorderWidth, 3);
        compare(field.resolvedCornerRadius, 8);
        compare(field.resolvedHAlign, Text.AlignLeft);
        compare(field.resolvedVAlign, Text.AlignTop);
    }

    // text を変更すると内部の TextField にも反映される。
    function test_text_property_is_reflected() {
        field.text = "42";
        compare(field.text, "42");
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null);
        compare(tf.text, "42");
    }

    // editable を切替えると内部 TextField の readOnly と選択用 MouseArea の enabled が反転する。
    //   editable:true（Simulator）→ TextField 入力可（readOnly:false）・選択 MouseArea 無効
    //   editable:false（Editor）  → TextField 読取専用（readOnly:true）・選択 MouseArea 有効
    function test_editable_toggles_readonly_and_select_area() {
        const tf = findByObjectName(field, "numericTextField");
        const ma = findByObjectName(field, "numericSelectArea");
        verify(tf !== null, "内部 TextField が見つからない");
        verify(ma !== null, "選択用 MouseArea が見つからない");

        // 既定 editable:true（Simulator）
        compare(tf.readOnly, false);
        compare(ma.enabled, false);

        // editable:false（Editor）に切替
        field.editable = false;
        compare(tf.readOnly, true);
        compare(ma.enabled, true);
    }

    // editable:false（Editor）のとき選択用 MouseArea のクリックで clicked が発火する
    //（Button / Label と一様の選択中継）。
    function test_click_emits_clicked_signal_when_not_editable() {
        field.editable = false;
        compare(clickedSpy.count, 0);
        mouseClick(field, field.width / 2, field.height / 2);
        compare(clickedSpy.count, 1);
    }

    // commitValue() は現在の TextField テキストを確定し valueCommitted(text) を emit する
    //（delegate がこれを受けて変数へ write する＝Task 51。Task 50 では口だけ用意）。
    function test_commit_value_emits_value_committed() {
        field.text = "7";
        compare(committedSpy.count, 0);
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "7");
    }

    // Task 51（Codex PR #105 P2）：編集中（フォーカス取得）は外部 text 更新を抑止し、
    // フォーカス喪失（確定）で変数の確定値へ再同期する。フォーカス取得時に `text: root.text`
    // 宣言バインドを外すため、編集中に root.text（変数追従）が変わっても内部 TextField は
    // 上書きされない。blur すると Qt.binding を貼り直して root.text へ復帰する。
    function test_edit_focus_suppresses_external_sync_then_resyncs_on_blur() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.text = "10";
        compare(tf.text, "10");

        // フォーカス取得＝編集中：宣言バインドが外れる。
        tf.forceActiveFocus();
        verify(tf.activeFocus, "TextField がフォーカスを取得できない");
        // 外部から root.text（変数追従の表示値）が変わっても入力中は上書きしない。
        field.text = "99";
        compare(tf.text, "10");

        // フォーカス喪失＝確定：root.text の現在値（"99"）へ再同期（バインド貼り直し）。
        focusSink.forceActiveFocus();
        verify(!tf.activeFocus, "TextField のフォーカスが外れない");
        compare(tf.text, "99");
        // 以降も変数追従が復活する（バインドが効く）。
        field.text = "123";
        compare(tf.text, "123");
    }

    // Task 51（CodeRabbit PR #105）：同一値の二重確定（Enter→blur で onEditingFinished が
    // 二度発火する等）は valueCommitted を一度だけにする（重複 setValue / 余分なシグナル抑止）。
    // フォーカス取得で重複排除キャッシュがクリアされ、別セッションでは同値でも再確定できる。
    function test_duplicate_commit_same_value_is_suppressed() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        tf.forceActiveFocus();   // 編集セッション開始（_lastCommittedText クリア）
        tf.text = "42";
        committedSpy.clear();
        field.commitValue();     // 1 回目：emit
        field.commitValue();     // 2 回目：同値 → スキップ
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "42");

        // 別の編集セッション（再フォーカス）では同じ値でも改めて確定できる。
        focusSink.forceActiveFocus();
        tf.forceActiveFocus();
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
    }

    // Task 51（Codex PR #105）：IntValidator は既定 locale で桁区切り・locale 固有数字を
    // 受理するため、確定値を IntValidator と同じ Qt.locale() で数値化し ASCII 整数へ正規化して
    // emit する（消費側 parseInt が "1,234" を 1、locale 数字を NaN→0 と誤読するのを防ぐ）。
    // 桁区切り入りの locale 文字列が ASCII 整数 "1234" に正規化されることを検証。
    function test_commit_normalizes_locale_number() {
        const sep = Qt.locale().groupSeparator;
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        // 桁区切り入りの文字列を内部 TextField に直接入れて確定する。
        tf.text = "1" + sep + "234";
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        // ASCII 整数 "1234" に正規化されている（parseInt("1234") = 1234 と整合）。
        compare(committedSpy.signalArguments[0][0], "1234");
        compare(parseInt(committedSpy.signalArguments[0][0], 10), 1234);
    }

    // Task 51（Codex PR #105 P1）：フォーカス喪失（Tab / 別所クリック）で再バインドより**先に**
    // 入力値を確定する。再バインドが先に走ると確定前に表示が旧 root.text へ戻り、古い値を
    // 書き戻して入力が失われる。ここでは内部 TextField に typed 値を入れて blur し、
    // valueCommitted が typed 値（旧 root.text ではない）で発火することを検証する。
    function test_blur_commits_typed_value_before_rebind() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.text = "10";  // root.text = "10"
        compare(tf.text, "10");

        tf.forceActiveFocus();
        verify(tf.activeFocus, "TextField がフォーカスを取得できない");
        committedSpy.clear();
        // ユーザー入力を模す：内部 TextField に直接 "42"（root.text は "10" のまま＝
        // 書き戻しは delegate の責務で、standalone では root.text は動かない）。
        tf.text = "42";
        compare(field.text, "10");

        // blur：commitValue が typed "42" で**ちょうど 1 回**発火する（確定は editingFinished に
        // 集約済み。再バインドで "10" へ戻る前に確定）。
        focusSink.forceActiveFocus();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "42");
    }

    // Task 53: isReal で validator が切替わる。false（既定）= IntValidator、true = DoubleValidator。
    function test_is_real_switches_validator() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");

        // 既定（int）は IntValidator。
        compare(field.isReal, false);
        verify(tf.validator instanceof IntValidator, "int 変数では IntValidator のはず");

        // real に切替えると DoubleValidator。
        field.isReal = true;
        verify(tf.validator instanceof DoubleValidator, "real 変数では DoubleValidator のはず");
    }

    // Task 53: isReal:true（real）では commitValue が小数を保ったまま正規化する
    //（int の Math.trunc と違い丸めない）。"36.5" → "36.5"。
    // Codex PR #112 [P2]：real は表示・validator・commit をすべて **C locale（ASCII 小数点）** に
    // 揃える。よって入力は locale 依存の `decimalPoint` ではなく **ASCII の "." 固定**で確定する
    //（変数ストア由来の表示値が常に ASCII なのと整合）。
    function test_real_commit_preserves_decimal() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = true;
        tf.forceActiveFocus();           // 編集セッション開始（_lastCommittedText クリア）
        tf.text = "36.5";                // ASCII 小数点（C locale）で入力
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        // ASCII の小数文字列に正規化される（Number("36.5") = 36.5 と整合）。
        compare(committedSpy.signalArguments[0][0], "36.5");
        compare(Number(committedSpy.signalArguments[0][0]), 36.5);
    }

    // Codex PR #112 [P2]：変数ストア由来の **ASCII 表示値**（"100.25"）を、編集せず focus → blur
    // しただけで確定しても値が壊れない（C locale 統一なので小数点カンマ環境でも 10025 等へ
    // 化けない）。real の commit が C locale で再パースされることを locale 非依存に固定する。
    function test_real_commit_roundtrips_ascii_display_value() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = true;
        tf.forceActiveFocus();
        tf.text = "100.25";              // 変数の表示値（ASCII）をそのまま確定
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "100.25");
        compare(Number(committedSpy.signalArguments[0][0]), 100.25);
    }

    // Codex PR #112 [P2]：real の確定値を指数表記にしない。`0.0000001` は素の String() だと
    // "1e-7" になり StandardNotation の DoubleValidator と矛盾するため、固定小数 "0.0000001" へ
    // 整形する。値自体は round-trip する（Number("0.0000001") === 1e-7）。
    function test_real_commit_avoids_exponential_notation() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = true;
        tf.forceActiveFocus();
        tf.text = "0.0000001";           // 素の String(Number(...)) は "1e-7" になる値
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        // 指数表記でなく固定小数で確定される（validator の StandardNotation と整合）。
        compare(committedSpy.signalArguments[0][0], "0.0000001");
        verify(committedSpy.signalArguments[0][0].indexOf("e") === -1, "指数表記になってはいけない");
        compare(Number(committedSpy.signalArguments[0][0]), 1e-7);
    }

    // Codex PR #112 [Minor]：real の **表示値**も固定小数へ整形する。delegate が bound 値を
    // String(v) で流すと "1e-7" のような指数表記が入りうるが、表示テキストは "0.0000001" へ
    // 整形され validator（StandardNotation）と整合する。int / 空はそのまま。
    function test_real_display_value_avoids_exponential_notation() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = true;
        // delegate が String(1e-7) を流す状況を模す（root.text = "1e-7"）。
        field.text = "1e-7";
        compare(tf.text, "0.0000001");
        verify(tf.text.indexOf("e") === -1, "表示が指数表記になってはいけない");
        // 通常の固定小数値はそのまま表示される。
        field.text = "36.5";
        compare(tf.text, "36.5");
    }

    // Codex PR #112 [Minor]：int（isReal:false）の表示は整形せず素通し。空も 0 化しない。
    function test_int_display_value_passthrough() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        field.text = "42";
        compare(tf.text, "42");
        field.text = "";
        compare(tf.text, "");
    }

    // Task 53: isReal:false（int）では従来どおり小数入力が整数へ丸められる（Math.trunc）。
    function test_int_commit_truncates_decimal() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        tf.forceActiveFocus();
        const dp = Qt.locale().decimalPoint;
        tf.text = "36" + dp + "5";       // 小数を入れても int は丸める
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "36");
    }

    // Task 54: int で範囲外入力が確定時に境界へ clamp される（拒否でなく丸める）。
    // hasMin / hasMax のときだけ片側ずつ clamp し、範囲内はそのまま。
    function test_int_commit_clamps_to_min() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        field.minValue = 10;
        field.hasMin = true;
        tf.forceActiveFocus();
        tf.text = "3";                    // 下限 10 を下回る
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "10");  // 下限へ clamp
    }

    // Task 54: int 変数に小数境界（min=2.5）を設定した場合、確定 clamp も validator
    // （bottom=ceil(2.5)=3）と揃えて整数実効境界へ丸める。生の 2.5 へ clamp 後に整数化して
    // min 未満の 2 へ落ちる不整合を防ぐ（確定値は 3）。
    function test_int_commit_clamps_to_ceil_of_fractional_min() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        field.minValue = 2.5;
        field.hasMin = true;
        tf.forceActiveFocus();
        tf.text = "2";                    // 下限 2.5（実効 int 下限 ceil=3）を下回る
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "3");  // ceil(2.5)=3 へ clamp（2 でない）
    }

    function test_int_commit_clamps_to_max() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        field.maxValue = 100;
        field.hasMax = true;
        tf.forceActiveFocus();
        tf.text = "250";                  // 上限 100 を上回る
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "100"); // 上限へ clamp
    }

    // Task 54（CodeRabbit PR #113）：境界逆転（min > max）でも破綻しない。実効境界を swap して
    // 正規化するので、min=100 / max=10 は実効 [10, 100] として clamp される（max 側へ押し込まない）。
    function test_inverted_bounds_are_normalized() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        field.minValue = 100;
        field.maxValue = 10;     // 逆転（min > max）
        field.hasMin = true;
        field.hasMax = true;
        tf.forceActiveFocus();
        tf.text = "50";          // 正規化後の実効 [10,100] の範囲内なのでそのまま
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "50");
    }

    // Task 54: 範囲内の値はそのまま（clamp されない）。
    function test_commit_within_range_unchanged() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        field.minValue = 0;
        field.maxValue = 100;
        field.hasMin = true;
        field.hasMax = true;
        tf.forceActiveFocus();
        tf.text = "42";                   // 範囲内
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "42");
    }

    // Task 54: real でも clamp する。確定値は固定小数表記（指数なし）で境界へ丸まる。
    function test_real_commit_clamps_to_bounds() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = true;
        field.minValue = 0.5;
        field.maxValue = 36.5;
        field.hasMin = true;
        field.hasMax = true;

        // 上限超過 → 36.5 へ clamp。
        tf.forceActiveFocus();
        tf.text = "99.9";
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "36.5");
        compare(Number(committedSpy.signalArguments[0][0]), 36.5);
    }

    // Task 54: 負の下限も clamp に効く（presence フラグ方式なので負値が正当）。
    function test_negative_min_clamp() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        field.minValue = -50;
        field.hasMin = true;
        tf.forceActiveFocus();
        tf.text = "-100";                 // 下限 -50 を下回る
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "-50"); // 負の下限へ clamp
    }

    // Task 54: presence フラグが false（未指定）のときは clamp されない（全域許容）。
    function test_no_clamp_when_unspecified() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        // hasMin / hasMax は false（未指定）。minValue/maxValue は 0 だが効かない。
        tf.forceActiveFocus();
        tf.text = "9999";
        committedSpy.clear();
        field.commitValue();
        compare(committedSpy.count, 1);
        compare(committedSpy.signalArguments[0][0], "9999"); // clamp されない
    }

    // Task 54: validator の bottom/top が presence に応じて設定される
    //（hasMin/hasMax のとき境界、未指定のとき型全域）。
    function test_validator_bounds_reflect_range() {
        const tf = findByObjectName(field, "numericTextField");
        verify(tf !== null, "内部 TextField が見つからない");
        field.isReal = false;
        field.minValue = 5;
        field.maxValue = 50;
        field.hasMin = true;
        field.hasMax = true;
        compare(tf.validator.bottom, 5);
        compare(tf.validator.top, 50);
    }

    // QQuickItem ツリーから指定された objectName の子を再帰的に探す
    //（tst_canvas.qml / tst_simulator_canvas.qml と同じ流儀）。
    function findByObjectName(node, name) {
        if (!node)
            return null;
        if (node.objectName === name)
            return node;
        const kids = node.children;
        if (kids) {
            for (let i = 0; i < kids.length; ++i) {
                const found = findByObjectName(kids[i], name);
                if (found)
                    return found;
            }
        }
        return null;
    }
}
