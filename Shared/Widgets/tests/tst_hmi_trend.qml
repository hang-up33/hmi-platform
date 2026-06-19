import QtQuick
import QtTest
import HmiWidgets

// Task T-B（Phase 8）: HmiTrend（ライブ折れ線 Widget）の公開プロパティ検証。
// **Canvas のピクセルは見ず公開プロパティのみ assert**（Canvas は E2E / unit から不可視）。
// HmiButton / HmiLabel / HmiNumericField の単体テストと同方式。
//
// 観点：
//   - resolved* 既定（pointCount=60 / 線色=#4cc9f0 / 背景=#0b1d2a）が HmiTrend 1 箇所に集約
//   - リングバッファ巻き取り（resolvedPointCount+5 push 後に bufferSize===resolvedPointCount、
//     最古が捨てられて lastValue が追従）
//   - sampleCount / lastValue が push に追従する
//   - clicked シグナルがクリックで発火する（選択中継用）
//   - live:false ではサンプリングしない（onValueChanged で push されない）
//
// 重要：clicked テストのため TestCase に visible: true を明示する（tst_hmi_label と同じ理由）。
TestCase {
    id: testCase
    name: "HmiTrend"
    when: windowShown
    visible: true
    width: 320
    height: 160

    HmiTrend {
        id: trend
        x: 0
        y: 0
        // 既定の live:false を上書きして、value 変化でサンプリングするテスト用インスタンス。
        live: true
    }

    // live:false（Editor プレビュー）の検証用に別インスタンスを置く。trend と重ならない
    // 位置にする（重ねると上に乗った方がクリックを奪い clicked テストが落ちる）。
    HmiTrend {
        id: previewTrend
        x: 0
        y: 130
        live: false
    }

    SignalSpy {
        id: clickedSpy
        target: trend
        signalName: "clicked"
    }

    function init() {
        // 各 test_* 実行前にプロパティ・バッファをリセット。
        // _buffers / sampleCounts / lastValues を初期化するため、いったん live を切ってから
        // 設定し直す（値代入で意図せず push されないように）。
        trend.live = false;
        trend.value = 0;
        trend.series = [];          // 単系列（暗黙 1 系列）へ戻す
        trend.seriesValues = [];
        trend.pointCount = 0;
        trend.lineColor = "";
        trend.backgroundColor = "";
        trend.yMin = 0;
        trend.yMax = 0;
        trend.hasYMin = false;
        trend.hasYMax = false;
        trend.sampleMs = 0;
        trend.clearBuffers();       // 全系列バッファ・統計・サンプル済みスナップショットを公開 API でクリア
        trend.live = true;
        clickedSpy.clear();
    }

    function test_default_properties() {
        compare(trend.width, 240);
        compare(trend.height, 120);
    }

    // 未指定（0 / 空 / -1）のとき resolved* が **Trend の既定**にフォールバックする。
    function test_resolved_defaults_when_unspecified() {
        compare(trend.resolvedPointCount, 60);
        // 既定線色は水色 #4cc9f0。
        compare(trend.resolvedLineColor, Qt.color("#4cc9f0"));
        // 既定背景はグラフらしい濃紺 #0b1d2a。
        compare(trend.resolvedBackgroundColor, Qt.color("#0b1d2a"));
        compare(trend.resolvedBorderColor, Qt.color("#9aa5b1"));
        compare(trend.resolvedBorderWidth, 1);
        compare(trend.resolvedCornerRadius, 4);
        compare(trend.resolvedOpacity, 1.0);
    }

    // 明示値が resolved* へ反映される。
    function test_explicit_values_are_resolved() {
        trend.pointCount = 120;
        trend.lineColor = "#ff0000";
        trend.backgroundColor = "#222222";

        compare(trend.resolvedPointCount, 120);
        compare(trend.resolvedLineColor, Qt.color("#ff0000"));
        compare(trend.resolvedBackgroundColor, Qt.color("#222222"));
    }

    // sampleCount / lastValue が push（value 変化）に追従する。
    function test_sample_count_and_last_value_track_pushes() {
        compare(trend.sampleCount, 0);
        compare(trend.bufferSize, 0);

        trend.value = 10;
        compare(trend.sampleCount, 1);
        compare(trend.lastValue, 10);
        compare(trend.bufferSize, 1);

        trend.value = 20;
        compare(trend.sampleCount, 2);
        compare(trend.lastValue, 20);
        compare(trend.bufferSize, 2);

        trend.value = 30;
        compare(trend.sampleCount, 3);
        compare(trend.lastValue, 30);
        compare(trend.bufferSize, 3);
    }

    // リングバッファ巻き取り：resolvedPointCount を超えて push しても bufferSize は頭打ち、
    // 最古が捨てられて lastValue は最新へ追従する。
    function test_ring_buffer_wraps_at_point_count() {
        trend.pointCount = 5;  // resolvedPointCount=5
        const cap = trend.resolvedPointCount;
        compare(cap, 5);

        // cap + 5 点を push（1..10）。
        const total = cap + 5;
        for (let i = 1; i <= total; ++i) {
            trend.value = i;
        }

        // 総 push 数は sampleCount で数えられる（巻き取っても総数は減らない）。
        compare(trend.sampleCount, total);
        // バッファ長は cap で頭打ち。
        compare(trend.bufferSize, cap);
        // 最新値（最後に push した total=10）に追従。
        compare(trend.lastValue, total);
    }

    // 非数値の push は無視される（バッファ・カウントが増えない）。
    function test_non_numeric_push_is_ignored() {
        trend.value = 5;
        compare(trend.sampleCount, 1);

        // 数値化できない値を直接 _push する（value 経由だと QML が number へ coerce するため）。
        trend._push("not-a-number");
        compare(trend.sampleCount, 1);
        compare(trend.bufferSize, 1);
    }

    // 選択中継用の clicked シグナルがクリックで発火する（Editor の選択に使う）。
    function test_click_emits_clicked_signal() {
        compare(clickedSpy.count, 0);

        mouseClick(trend, trend.width / 2, trend.height / 2);
        compare(clickedSpy.count, 1);

        mouseClick(trend, trend.width / 2, trend.height / 2);
        compare(clickedSpy.count, 2);
    }

    // Task 8B-B: series が空のとき seriesCount は暗黙 1 系列。
    function test_series_count_defaults_to_one_when_empty() {
        compare(trend.series.length, 0);
        compare(trend.seriesCount, 1);
        compare(trend.effectiveSeriesCount, 1);
    }

    // Task 8B-B: series を 2 本設定すると seriesCount=2、各系列が独立にサンプリングされる。
    // seriesValues を変えるたび全系列が 1 点ずつ取り込まれ、系列ごとの sampleCountAt /
    // lastValueAt / bufferSizeAt が独立に追従する。
    function test_two_series_track_independently() {
        trend.series = [
            { variable: "a", color: "#ff0000", label: "A" },
            { variable: "b", color: "#00ff00", label: "B" }
        ];
        compare(trend.seriesCount, 2);
        // 系列追加直後はバッファ空・統計 0。
        compare(trend.sampleCountAt(0), 0);
        compare(trend.sampleCountAt(1), 0);
        compare(trend.bufferSizeAt(0), 0);
        compare(trend.bufferSizeAt(1), 0);

        // 1 回目の更新：系列 0=10, 系列 1=100。
        trend.seriesValues = [10, 100];
        compare(trend.sampleCountAt(0), 1);
        compare(trend.sampleCountAt(1), 1);
        compare(trend.lastValueAt(0), 10);
        compare(trend.lastValueAt(1), 100);
        compare(trend.bufferSizeAt(0), 1);
        compare(trend.bufferSizeAt(1), 1);

        // 2 回目：系列 0=20, 系列 1=200。各系列が独立に伸びる。
        trend.seriesValues = [20, 200];
        compare(trend.sampleCountAt(0), 2);
        compare(trend.sampleCountAt(1), 2);
        compare(trend.lastValueAt(0), 20);
        compare(trend.lastValueAt(1), 200);
        compare(trend.bufferSizeAt(0), 2);
        compare(trend.bufferSizeAt(1), 2);

        // 系列 0 互換の sampleCount / lastValue / bufferSize は系列 0 を映す。
        compare(trend.sampleCount, 2);
        compare(trend.lastValue, 20);
        compare(trend.bufferSize, 2);
    }

    // Task 8B-B: 多系列でもリングバッファが系列ごとに独立して巻き取られる。
    function test_two_series_ring_buffer_wraps_independently() {
        trend.series = [
            { variable: "a", color: "", label: "" },
            { variable: "b", color: "", label: "" }
        ];
        trend.pointCount = 4;  // resolvedPointCount=4
        compare(trend.resolvedPointCount, 4);

        const total = 4 + 3;  // cap を超える 7 回更新
        for (let i = 1; i <= total; ++i) {
            trend.seriesValues = [i, i * 10];
        }

        // 総 push 数は各系列とも total。
        compare(trend.sampleCountAt(0), total);
        compare(trend.sampleCountAt(1), total);
        // バッファ長は系列ごとに cap で頭打ち。
        compare(trend.bufferSizeAt(0), 4);
        compare(trend.bufferSizeAt(1), 4);
        // 最新値に独立追従。
        compare(trend.lastValueAt(0), total);
        compare(trend.lastValueAt(1), total * 10);
    }

    // Task 8B-B: 後方互換＝series 空のときは従来どおり value 変化で系列 0 が取り込まれる。
    function test_backward_compat_single_series_value_path() {
        compare(trend.series.length, 0);
        // value 変化で系列 0 が push される（従来単系列パス）。
        trend.value = 42;
        compare(trend.sampleCountAt(0), 1);
        compare(trend.lastValueAt(0), 42);
        compare(trend.bufferSizeAt(0), 1);
        // 系列 0 互換プロパティも一致。
        compare(trend.sampleCount, 1);
        compare(trend.lastValue, 42);
    }

    // Task 8B-B: series 非空時は value 変化では取り込まない（seriesValues が源）。
    function test_value_path_inactive_when_series_present() {
        trend.series = [{ variable: "a", color: "", label: "" }];
        const before = trend.sampleCountAt(0);
        trend.value = 999;  // series 非空なので無視されるはず
        compare(trend.sampleCountAt(0), before);
    }

    // live:false（Editor プレビュー）ではサンプリングしない＝value 変化で push されない。
    // プレビュー用ダミー波形は Component.onCompleted で埋まるが、sampleCount は増えない。
    function test_preview_does_not_sample() {
        // Component.onCompleted のダミー波形でバッファは埋まっているが sampleCount は 0。
        compare(previewTrend.sampleCount, 0);
        verify(previewTrend.bufferSize > 0);

        const beforeCount = previewTrend.sampleCount;
        const beforeSize = previewTrend.bufferSize;
        // value を変えても live:false なので push されない。
        previewTrend.value = 999;
        compare(previewTrend.sampleCount, beforeCount);
        compare(previewTrend.bufferSize, beforeSize);
    }

    // Task 8B-B（Codex PR #136 [Major]）: seriesValues の参照だけが変わって内容が同じ
    // 場合は再サンプリングしない（無関係変数の更新による重複サンプル防止）。
    function test_no_resample_when_series_values_unchanged() {
        trend.series = [
            { variable: "a", color: "", label: "" },
            { variable: "b", color: "", label: "" }
        ];
        trend.seriesValues = [10, 100];
        compare(trend.sampleCountAt(0), 1);
        compare(trend.sampleCountAt(1), 1);

        // 同じ内容の新しい配列を代入（参照は変わるが値は不変）→ push されない。
        trend.seriesValues = [10, 100];
        compare(trend.sampleCountAt(0), 1);
        compare(trend.sampleCountAt(1), 1);

        // 1 系列でも値が変われば全系列を取り込む（X 軸整列のため）。
        trend.seriesValues = [10, 200];
        compare(trend.sampleCountAt(0), 2);
        compare(trend.sampleCountAt(1), 2);
        compare(trend.lastValueAt(1), 200);
    }

    // Task 8B-B: 系列数を動的に増減してもバッファ・統計配列が追従する（範囲外は安全）。
    function test_dynamic_series_count_change() {
        trend.series = [{ variable: "a", color: "", label: "" }];
        compare(trend.seriesCount, 1);
        trend.series = [
            { variable: "a", color: "", label: "" },
            { variable: "b", color: "", label: "" },
            { variable: "c", color: "", label: "" }
        ];
        compare(trend.seriesCount, 3);
        trend.seriesValues = [1, 2, 3];
        compare(trend.sampleCountAt(2), 1);
        // 1 系列へ縮小しても破綻しない。
        trend.series = [{ variable: "a", color: "", label: "" }];
        compare(trend.seriesCount, 1);
        compare(trend.bufferSizeAt(0) >= 0, true);
    }

    // Task 8B-B: 範囲外インデックスのアクセサは安全な既定値（0）を返す。
    function test_accessors_out_of_range_are_safe() {
        trend.series = [{ variable: "a", color: "", label: "" }];
        compare(trend.sampleCountAt(-1), 0);
        compare(trend.sampleCountAt(99), 0);
        compare(trend.lastValueAt(-1), 0);
        compare(trend.lastValueAt(99), 0);
        compare(trend.bufferSizeAt(-1), 0);
        compare(trend.bufferSizeAt(99), 0);
    }
}
