import QtQuick
import QtTest
import HmiWidgets

// Task M-B（Phase 10）: HmiMeter（スピードメーター風 Widget）の公開プロパティ検証。
// **Canvas のピクセルは見ず公開プロパティのみ assert**（Canvas は E2E / unit から不可視）。
// HmiButton / HmiLabel / HmiNumericField / HmiTrend の単体テストと同方式。
//
// 観点：
//   - resolved* 既定（meterMin=0 / meterMax=100 / 弧色=#4cc9f0 / 針色=#ff595e /
//     目盛り=10 / 背景=#0b1d2a）が HmiMeter 1 箇所に集約
//   - 値→針角度マッピング（min→startAngle / 中点→startAngle+span/2 / max→endAngle）
//   - clamp（範囲外で displayValue が端に張り付き、needleAngle も端角へ）
//   - max<=min（不正範囲）で 0 除算せず下限へ退避
//   - displayValue が value に追従する（live:true）
//   - live:false（Editor プレビュー）は中間値（(min+max)/2）を表示する
//   - clicked シグナルがクリックで発火する（選択中継用）
//
// 重要：clicked テストのため TestCase に visible: true を明示する（tst_hmi_trend と同じ理由）。
TestCase {
    id: testCase
    name: "HmiMeter"
    when: windowShown
    visible: true
    width: 320
    height: 260

    // ライブ実行インスタンス（value 変化で針が追従する）。
    HmiMeter {
        id: meter
        x: 0
        y: 0
        width: 200
        height: 200
        live: true
    }

    // live:false（Editor プレビュー）検証用。meter と重ならない位置に置く
    // （重ねると上に乗った方がクリックを奪い clicked テストが落ちる）。
    HmiMeter {
        id: previewMeter
        x: 210
        y: 0
        width: 100
        height: 100
        live: false
    }

    SignalSpy {
        id: clickedSpy
        target: meter
        signalName: "clicked"
    }

    function init() {
        // 各 test_* 実行前にプロパティをリセットする。
        meter.live = true;
        meter.value = 0;
        meter.meterMin = 0;
        meter.meterMax = 0;
        meter.hasMeterMin = false;
        meter.hasMeterMax = false;
        meter.arcColor = "";
        meter.needleColor = "";
        meter.tickCount = 0;
        meter.unit = "";
        meter.backgroundColor = "";
        meter.borderColor = "";
        meter.borderWidth = -1;
        meter.cornerRadius = -1;
        meter.widgetOpacity = -1;
        meter.widgetEnabled = true;
        clickedSpy.clear();
    }

    function test_default_properties() {
        compare(meter.width, 200);
        compare(meter.height, 200);
    }

    // 未指定（0 / 空 / -1 / presence false）のとき resolved* が **Meter の既定**へフォールバック。
    function test_resolved_defaults_when_unspecified() {
        compare(meter.resolvedMeterMin, 0);
        compare(meter.resolvedMeterMax, 100);
        compare(meter.resolvedArcColor, Qt.color("#4cc9f0"));
        compare(meter.resolvedNeedleColor, Qt.color("#ff595e"));
        compare(meter.resolvedTickCount, 10);
        compare(meter.resolvedBackgroundColor, Qt.color("#0b1d2a"));
        compare(meter.resolvedBorderColor, Qt.color("#9aa5b1"));
        compare(meter.resolvedBorderWidth, 1);
        compare(meter.resolvedCornerRadius, 4);
        compare(meter.resolvedOpacity, 1.0);
    }

    // 明示値（presence フラグ / 色 / 目盛り）が resolved* へ反映される。
    function test_explicit_values_are_resolved() {
        meter.meterMin = -20;
        meter.hasMeterMin = true;
        meter.meterMax = 180;
        meter.hasMeterMax = true;
        meter.arcColor = "#00ff00";
        meter.needleColor = "#0000ff";
        meter.tickCount = 6;

        compare(meter.resolvedMeterMin, -20);
        compare(meter.resolvedMeterMax, 180);
        compare(meter.resolvedArcColor, Qt.color("#00ff00"));
        compare(meter.resolvedNeedleColor, Qt.color("#0000ff"));
        compare(meter.resolvedTickCount, 6);
    }

    // 値→針角度：min→startAngle / 中点→startAngle+span/2 / max→endAngle。
    function test_needle_angle_maps_value_to_arc() {
        meter.meterMin = 0;
        meter.hasMeterMin = true;
        meter.meterMax = 100;
        meter.hasMeterMax = true;

        meter.value = 0;
        compare(meter.displayValue, 0);
        fuzzyCompare(meter.needleAngle, meter.startAngle, 0.001);

        meter.value = 50;
        compare(meter.displayValue, 50);
        fuzzyCompare(meter.needleAngle, meter.startAngle + meter.spanAngle / 2, 0.001);

        meter.value = 100;
        compare(meter.displayValue, 100);
        fuzzyCompare(meter.needleAngle, meter.endAngle, 0.001);
    }

    // 負値スケール（例 −20..40）でも中点で真ん中を指す（presence フラグ方式の要）。
    function test_needle_angle_with_negative_range() {
        meter.meterMin = -20;
        meter.hasMeterMin = true;
        meter.meterMax = 40;
        meter.hasMeterMax = true;

        meter.value = 10;  // 中点（(-20+40)/2）
        compare(meter.displayValue, 10);
        fuzzyCompare(meter.needleAngle, meter.startAngle + meter.spanAngle / 2, 0.001);
    }

    // clamp：範囲外の value は displayValue が端へ張り付き、needleAngle も端角になる。
    function test_value_out_of_range_clamps() {
        meter.meterMin = 0;
        meter.hasMeterMin = true;
        meter.meterMax = 100;
        meter.hasMeterMax = true;

        meter.value = -50;
        compare(meter.displayValue, 0);
        fuzzyCompare(meter.needleAngle, meter.startAngle, 0.001);

        meter.value = 999;
        compare(meter.displayValue, 100);
        fuzzyCompare(meter.needleAngle, meter.endAngle, 0.001);
    }

    // max<=min（不正範囲）は 0 除算せず下限へ退避する（NaN を出さない）。
    function test_invalid_range_falls_back_to_min() {
        meter.meterMin = 50;
        meter.hasMeterMin = true;
        meter.meterMax = 50;  // max == min
        meter.hasMeterMax = true;
        meter.value = 75;

        compare(meter.displayValue, 50);
        fuzzyCompare(meter.needleAngle, meter.startAngle, 0.001);
        verify(!isNaN(meter.needleAngle), "needleAngle が NaN");
    }

    // 非数値（NaN）の value は下限へ退避する（文字列変数バインド等で Number(...)→NaN の防御。
    // Codex PR #153 [P2]）。displayValue / needleAngle が NaN にならないこと。
    function test_non_numeric_value_falls_back_to_min() {
        meter.meterMin = 10;
        meter.hasMeterMin = true;
        meter.meterMax = 100;
        meter.hasMeterMax = true;

        meter.value = NaN;
        compare(meter.displayValue, 10);
        verify(!isNaN(meter.displayValue), "displayValue が NaN");
        fuzzyCompare(meter.needleAngle, meter.startAngle, 0.001);
        verify(!isNaN(meter.needleAngle), "needleAngle が NaN");
    }

    // displayValue / needleAngle が value 変化に追従する（live:true）。
    function test_display_value_tracks_value() {
        meter.meterMin = 0;
        meter.hasMeterMin = true;
        meter.meterMax = 200;
        meter.hasMeterMax = true;

        meter.value = 40;
        compare(meter.displayValue, 40);
        meter.value = 160;
        compare(meter.displayValue, 160);
    }

    // live:false（Editor プレビュー）は value でなく中間値（(min+max)/2）を表示する。
    function test_preview_shows_midpoint_when_not_live() {
        previewMeter.meterMin = 0;
        previewMeter.hasMeterMin = true;
        previewMeter.meterMax = 80;
        previewMeter.hasMeterMax = true;
        previewMeter.value = 10;  // live:false なので無視される

        compare(previewMeter.displayValue, 40);  // (0+80)/2
        fuzzyCompare(previewMeter.needleAngle,
                     previewMeter.startAngle + previewMeter.spanAngle / 2, 0.001);
    }

    // clicked シグナルがクリックで発火する（Editor の選択中継用）。
    function test_clicked_signal_fires() {
        compare(clickedSpy.count, 0);
        mouseClick(meter, meter.width / 2, meter.height / 2);
        compare(clickedSpy.count, 1);
    }
}
