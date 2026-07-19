import QtQuick
import QtTest
import HmiWidgets

// Task W-B（Phase 11）: HmiSimpleButton（ベゼル無しシンプルボタン）の公開プロパティ検証。
// **Canvas のピクセルは見ず公開プロパティ / シグナルのみ assert**（Canvas は E2E / unit から不可視）。
// HmiButton / HmiLabel / HmiNumericField / HmiTrend / HmiMeter の単体テストと同方式。
//
// 観点：
//   - resolved* 既定（shape=circle / theme=light / accent=#2fa563 / holdMs=800）が HmiSimpleButton 1 箇所に集約
//   - 明示値（shape=square / theme=dark / accentColor / holdMs）が resolved* / isCircle へ反映
//   - clicked シグナルがクリックで発火する（Editor の選択中継用）
//   - live:true：長押し（press 保持）で holdProgress が進み、確定で toggled(!checked) が発火する
//   - live:false（Editor プレビュー）：press しても holdProgress は 0 のまま・toggled は出ない
//
// 重要：clicked / press-hold のため TestCase に visible: true を明示する（tst_hmi_meter と同じ理由）。
TestCase {
    id: testCase
    name: "HmiSimpleButton"
    when: windowShown
    visible: true
    width: 320
    height: 220

    // ライブ実行インスタンス（長押しで toggled が出る）。
    HmiSimpleButton {
        id: sb
        x: 0
        y: 0
        width: 180
        height: 180
        live: true
    }

    // live:false（Editor プレビュー）検証用。sb と重ならない位置に置く
    // （重ねると上に乗った方が press を奪う）。
    HmiSimpleButton {
        id: previewSb
        x: 190
        y: 0
        width: 100
        height: 100
        live: false
    }

    SignalSpy {
        id: clickedSpy
        target: sb
        signalName: "clicked"
    }

    SignalSpy {
        id: toggledSpy
        target: sb
        signalName: "toggled"
    }

    SignalSpy {
        id: previewToggledSpy
        target: previewSb
        signalName: "toggled"
    }

    function init() {
        // 各 test_* 実行前にプロパティをリセットする。
        sb.live = true;
        sb.text = "TEST";
        sb.shape = "";
        sb.theme = "";
        sb.accentColor = "";
        sb.holdMs = 0;
        sb.checked = false;
        sb.holdProgress = 0;
        sb.widgetOpacity = -1;
        sb.widgetEnabled = true;
        previewSb.widgetEnabled = true;
        clickedSpy.clear();
        toggledSpy.clear();
        previewToggledSpy.clear();
    }

    function test_default_properties() {
        compare(sb.width, 180);
        compare(sb.height, 180);
    }

    // 未指定（空 / 0）のとき resolved* が **SimpleButton の既定**へフォールバックする。
    function test_resolved_defaults_when_unspecified() {
        compare(sb.resolvedTheme, "light");
        compare(sb.isCircle, true);            // 空 shape は circle
        compare(sb.resolvedAccent, Qt.color("#2fa563"));  // light テーマの既定アクセント
        compare(sb.resolvedHoldMs, 800);
    }

    // 明示値（shape=square / theme=dark / accentColor / holdMs）が resolved* / isCircle へ反映される。
    function test_explicit_values_are_resolved() {
        sb.shape = "square";
        sb.theme = "dark";
        sb.accentColor = "#123456";
        sb.holdMs = 500;

        compare(sb.isCircle, false);
        compare(sb.resolvedTheme, "dark");
        compare(sb.resolvedAccent, Qt.color("#123456"));
        compare(sb.resolvedHoldMs, 500);
    }

    // 不正な shape / theme は既定（circle / light）へフォールバックする。
    function test_invalid_shape_theme_fall_back() {
        sb.shape = "bogus";
        sb.theme = "bogus";
        compare(sb.isCircle, true);        // "square" 以外は circle
        compare(sb.resolvedTheme, "light"); // "dark" 以外は light
    }

    // clicked シグナルがクリックで発火する（Editor の選択中継用）。
    function test_clicked_signal_fires() {
        compare(clickedSpy.count, 0);
        mouseClick(sb, sb.width / 2, sb.height / 2);
        compare(clickedSpy.count, 1);
    }

    // live:true：長押し（press 保持）で holdProgress が進み、確定で toggled(!checked) が発火する。
    // holdMs を小さくして Timer 満了を待つ。widget は自身の checked を更新しない（consumer/binding が
    // onToggled で書き戻す設計）ので、spy の引数で「次値 = !checked」を検証する。
    function test_hold_emits_toggled_when_live() {
        sb.holdMs = 60;      // 素早く満了させる
        sb.checked = false;  // 次値は true になるはず

        mousePress(sb, sb.width / 2, sb.height / 2);
        // Timer（~60fps）が holdProgress を 0→1 へ進め、満了で toggled を emit する。
        tryCompare(toggledSpy, "count", 1, 3000);
        compare(toggledSpy.signalArguments[0][0], true);  // !checked
        // 確定後、進捗は 0 へ戻る（次の長押しに備える）。
        compare(sb.holdProgress, 0);
        mouseRelease(sb, sb.width / 2, sb.height / 2);
    }

    // live:false（Editor プレビュー）：press しても holdProgress は 0 のまま・toggled は出ない
    // （設計面で誤作動させない）。少し待っても進捗が動かないことを確認する。
    function test_preview_does_not_hold_when_not_live() {
        previewSb.holdMs = 60;
        mousePress(previewSb, previewSb.width / 2, previewSb.height / 2);
        wait(200);  // live:true なら 60ms で満了するが、live:false は進まない
        compare(previewSb.holdProgress, 0);
        compare(previewToggledSpy.count, 0);
        mouseRelease(previewSb, previewSb.width / 2, previewSb.height / 2);
    }

    // Task W-B（Codex PR #164 [P2]）: 共通状態（opacity / enabled）が他 Widget と同型で効く。
    // 未指定（widgetOpacity=-1 / widgetEnabled=true）は resolvedOpacity=1.0・不透明。
    function test_resolved_opacity_default_and_explicit() {
        compare(sb.resolvedOpacity, 1.0);         // 未指定は 1.0
        sb.widgetOpacity = 0.3;
        compare(sb.resolvedOpacity, 0.3);         // 明示値が反映
        // enabled=true なら opacity は resolvedOpacity そのまま（淡色化なし）。
        compare(sb.opacity, 0.3);
    }

    // widgetEnabled=false は淡色（opacity に 0.4 係数）になる（Task 42 の HmiButton と同型）。
    function test_disabled_dims_opacity() {
        sb.widgetOpacity = -1;      // resolvedOpacity=1.0
        sb.widgetEnabled = false;
        compare(sb.opacity, 0.4);   // 1.0 * 0.4
    }

    // widgetEnabled=false は live:true でも長押し進捗を動かさない（無効ボタンで進捗が伸びない）。
    function test_disabled_does_not_hold_even_when_live() {
        sb.live = true;
        sb.widgetEnabled = false;
        sb.holdMs = 60;
        mousePress(sb, sb.width / 2, sb.height / 2);
        wait(200);  // enabled なら 60ms で満了するが、無効なので進まない
        compare(sb.holdProgress, 0);
        compare(toggledSpy.count, 0);
        mouseRelease(sb, sb.width / 2, sb.height / 2);
    }
}
