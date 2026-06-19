import QtQuick

// Task T-B（Phase 8）: 共有 Trend Widget（ライブ折れ線グラフ）。Phase 5（Label）/
// Phase 6（NumericField）で確立した横展開テンプレ（resolved\* フォールバック方式 +
// 選択中継 clicked + delegate 型分岐）に乗せた新 Widget 種別。設計の正本は
// Docs/phase8-trend-plan.md「HmiTrend.qml（§Task B）」。
//
// **新 Qt 依存ゼロが本フェーズの最重要制約**：描画は QML 標準の `Canvas` 自描画
// （`import QtQuick` のみ。QtCharts / QtQuick.Controls など新規モジュールを import しない）。
// これにより i.MX8MP rootfs にそのまま載る（Phase 7 で QtSerialBus が kit/rootfs 未同梱
// だった轍を踏まない）。ファイル名 `HmiTrend` は QtQuick 標準型と非衝突（中で `Canvas{}`
// 型を使うのは可。CLAUDE.md「QtQuick 標準型と同名の QML ファイルを作らない」規約）。
//
// HmiButton / HmiLabel / HmiNumericField と違い以下を持つ／持たない：
//   - 持つ：value（単系列サンプル源）/ series（複数系列モデル）/ seriesValues（各系列現在値）/
//           pointCount / yMin+hasYMin / yMax+hasYMax / lineColor / sampleMs / live、
//           背景・枠スタイル（resolved\*）、系列ごとのリングバッファ + Canvas 自描画（N 本）、
//           選択中継 clicked。
//   - 持たない：text / フォント / checkable / checked / クリックアクション（表示専用＝
//           binding の「読み」のみ。書きはしない）。
//
// Task 8B-B（Phase 8-B）: 単系列を N 系列へ一般化。series 非空時は各系列の現在値を
// seriesValues から取り込み色分けして重ね描く。series 空は従来の value/lineColor の
// 暗黙 1 系列として温存（後方互換）。軸/凡例描画は 8B-C で追加（本タスクでは折れ線のみ）。
//
// サンプル取り込みの役割分担（plan §Task B）：
//   - Simulator/Runtime（live:true）：delegate が boundValue("value") を value へバインドし、
//     値変化（方式 A）または周期 Timer（方式 B, sampleMs>0）でリングバッファへ push。
//   - Editor（live:false）：ライブデータが無い設計面なので Component.onCompleted で
//     ダミー波形を 1 度だけ埋めて描画（サンプリング・Timer は動かさない）。
Rectangle {
    id: root

    // サンプル源（数値・単系列後方互換）。delegate が boundValue("value") を流す（live:true）。
    // Editor プレビュー（live:false）では使わない（ダミー波形を別途埋める）。
    // **series が空のとき**だけ「暗黙の系列 0」のサンプル源として使う（Phase 8 互換）。
    property real value: 0

    // Task 8B-B: 複数系列モデル。`[{variable, color, label}, ...]`（delegate が流す）。
    // 空のとき従来の単系列パス（value / resolvedLineColor）へフォールバックする（後方互換）。
    property var series: []
    // 各系列の現在値（series[i] に対応）。delegate が VariableStore から供給する。
    // series 空時は使わない（value を見る）。
    property var seriesValues: []

    // 系列色の既定パレット（series[i].color が空のとき _palette[i % n] を使う）。
    // プロジェクト全体でここだけが系列既定色を持つ（resolvedLineColor と同じ集約パターン）。
    readonly property var _palette: ["#4cc9f0", "#f72585", "#4361ee", "#f9c74f", "#90be6d", "#f3722c"]

    // 実効系列数（series 非空なら series.length、空なら暗黙 1 系列）。
    readonly property int effectiveSeriesCount: (root.series && root.series.length > 0) ? root.series.length : 1
    // テスト公開：実効系列数（= effectiveSeriesCount）。
    readonly property int seriesCount: root.effectiveSeriesCount

    // 直近 N 点。`0`（/負値）= 未指定＝既定 60 へ解決（plan の `0` センチネル）。
    property int pointCount: 0

    // Y 軸範囲（presence フラグ方式。負値が正当なのでセンチネル不可。WidgetData の
    // hasYMin/hasYMax 由来）。未指定（has*=false）はバッファの min/max 自動スケール。
    property real yMin: 0
    property real yMax: 0
    property bool hasYMin: false
    property bool hasYMax: false

    // 折れ線の色。空 = 未指定＝既定線色（#4cc9f0）へ解決（backgroundColor 同型）。
    property string lineColor: ""

    // 周期サンプリング間隔[ms]。`0`（/負値）= 未指定＝変更時サンプルのみ（方式 A）。
    // `>0` で Timer 駆動（方式 B）。
    property int sampleMs: 0

    // ライブ実行か（Simulator/Runtime=true サンプリング / Editor=false プレビュー）。
    property bool live: false

    // スタイル入力。色は "#RRGGBB"（空 = 未指定）。HmiNumericField の resolved\* と
    // 同じ命名・既定で流用（borderWidth / cornerRadius は `-1` センチネル）。
    property string backgroundColor: ""
    property string borderColor: ""
    property int borderWidth: -1
    property int cornerRadius: -1

    // 不透明度（`Item.opacity` 衝突回避で widgetOpacity。`-1` 未指定）。
    property real widgetOpacity: -1
    // `Item.enabled` 衝突回避で widgetEnabled。false で淡色表示（他 Widget と同型）。
    property bool widgetEnabled: true

    // 未指定（空 / 0 / -1）のときの既定外観。プロジェクト全体でここだけが Trend の
    // 既定値を持つ（Button / Label / NumericField と同じ集約パターン）。
    // **グラフらしい濃紺背景 + 水色の線**が他 Widget との既定差分（plan 記載値）。
    readonly property int resolvedPointCount: pointCount > 0 ? pointCount : 60
    readonly property color resolvedLineColor: lineColor !== "" ? lineColor : "#4cc9f0"
    readonly property color resolvedBackgroundColor: backgroundColor !== "" ? backgroundColor : "#0b1d2a"

    readonly property color resolvedBorderColor: borderColor !== "" ? borderColor : "#9aa5b1"
    readonly property int resolvedBorderWidth: borderWidth >= 0 ? borderWidth : 1
    readonly property int resolvedCornerRadius: cornerRadius >= 0 ? cornerRadius : 4

    // 未指定（`< 0`）のとき不透明度 1.0（完全不透明）にフォールバック。
    readonly property real resolvedOpacity: widgetOpacity >= 0 ? widgetOpacity : 1.0

    // 選択中継用 clicked（Editor の選択に使う。modifiers は複数選択の加除用）。
    // HmiButton / HmiLabel / HmiNumericField の clicked(int modifiers) と同形。
    // Simulator は接続しない＝表示専用。
    signal clicked(int modifiers)

    // リングバッファ（系列ごとの配列の配列＝[[系列0の点...], [系列1の点...], ...]）。
    // Task 8B-B で単一 _buffer から多系列 _buffers へ一般化。各系列が独立に push 順で値を
    // 保持し、満杯（resolvedPointCount）で先頭を捨てる。
    property var _buffers: [[]]

    // 単系列後方互換：系列 0 のバッファを従来の _buffer 名でも公開（既存 unit / E2E が
    // 直接代入してリセットするため writable な別名で残す）。read は系列 0、write は系列 0 へ反映。
    property var _buffer: []
    on_BufferChanged: {
        // テスト等が _buffer = [] のように直接代入したら系列 0 のバッファへ同期する。
        // _buffers 経由の内部更新では _syncingBuffer ガードで再入を防ぐ。
        if (root._syncingBuffer) {
            return;
        }
        root._syncingBuffer = true;
        var bufs = root._buffers ? root._buffers.slice() : [];
        if (bufs.length === 0) {
            bufs = [[]];
        }
        bufs[0] = (root._buffer ? root._buffer.slice() : []);
        root._buffers = bufs;
        root._syncingBuffer = false;
        canvas.requestPaint();
    }
    property bool _syncingBuffer: false

    // テスト用公開プロパティ（read-only）。Canvas のピクセルは E2E / unit から不可視なので、
    // これらの公開 API を観測して「サンプル取り込み」を検証する（plan §Task D）。
    //   sampleCounts[i] : 系列 i に取り込んだ実サンプルの総数（push 回数）。
    //   lastValues[i]   : 系列 i の直近 push した値。
    // Editor プレビューのダミー波形は数えない（実サンプルの観測を濁さないため）。
    property var sampleCounts: [0]
    property var lastValues: [0]

    // 系列 0 互換の公開プロパティ（既存 unit / E2E を壊さない）。
    readonly property int sampleCount: (root.sampleCounts && root.sampleCounts.length > 0) ? root.sampleCounts[0] : 0
    readonly property real lastValue: (root.lastValues && root.lastValues.length > 0) ? root.lastValues[0] : 0
    readonly property int bufferSize: (root._buffers && root._buffers.length > 0 && root._buffers[0]) ? root._buffers[0].length : 0

    // テスト公開：系列 i のサンプル統計 / バッファ長。
    function sampleCountAt(i) {
        return (root.sampleCounts && i >= 0 && i < root.sampleCounts.length) ? root.sampleCounts[i] : 0;
    }
    function lastValueAt(i) {
        return (root.lastValues && i >= 0 && i < root.lastValues.length) ? root.lastValues[i] : 0;
    }
    function bufferSizeAt(i) {
        return (root._buffers && i >= 0 && i < root._buffers.length && root._buffers[i]) ? root._buffers[i].length : 0;
    }

    // sampleCounts / lastValues / _buffers を effectiveSeriesCount に合わせて拡張する内部ヘルパー。
    // 系列数が増減したとき配列長を揃え、不足分は 0 / 空で埋める。
    function _ensureSeriesArrays() {
        var n = root.effectiveSeriesCount;
        var bufs = root._buffers ? root._buffers.slice() : [];
        var counts = root.sampleCounts ? root.sampleCounts.slice() : [];
        var lasts = root.lastValues ? root.lastValues.slice() : [];
        while (bufs.length < n) bufs.push([]);
        while (counts.length < n) counts.push(0);
        while (lasts.length < n) lasts.push(0);
        // 余剰は切り詰める（系列が減った場合）。
        if (bufs.length > n) bufs = bufs.slice(0, n);
        if (counts.length > n) counts = counts.slice(0, n);
        if (lasts.length > n) lasts = lasts.slice(0, n);
        root._syncingBuffer = true;
        root._buffers = bufs;
        root.sampleCounts = counts;
        root.lastValues = lasts;
        root._syncingBuffer = false;
    }

    // 系列 i のリングバッファへ 1 点 push する。数値でない値は無視する。満杯
    // （resolvedPointCount 超過）なら先頭を捨てて横スクロールを実現する。push 後に再描画。
    function _pushAt(i, v) {
        var n = Number(v);
        if (isNaN(n)) {
            return;
        }
        if (i < 0 || i >= root.effectiveSeriesCount) {
            return;
        }
        // 再代入でバインディング（bufferSize）へ通知するため毎回コピーする。高頻度
        // サンプリングでは将来の最適化候補（リングインデックス化等）。MVP は素朴な slice。
        var bufs = root._buffers ? root._buffers.slice() : [];
        while (bufs.length <= i) bufs.push([]);
        var buf = bufs[i] ? bufs[i].slice() : [];
        buf.push(n);
        while (buf.length > root.resolvedPointCount) {
            buf.shift();
        }
        bufs[i] = buf;
        root._syncingBuffer = true;
        root._buffers = bufs;
        root._syncingBuffer = false;

        var lasts = root.lastValues ? root.lastValues.slice() : [];
        while (lasts.length <= i) lasts.push(0);
        lasts[i] = n;
        root.lastValues = lasts;

        var counts = root.sampleCounts ? root.sampleCounts.slice() : [];
        while (counts.length <= i) counts.push(0);
        counts[i] += 1;
        root.sampleCounts = counts;

        canvas.requestPaint();
    }

    // 単系列後方互換：系列 0 へ push する（既存 unit / E2E が _push を直接呼ぶ）。
    function _push(v) {
        root._pushAt(0, v);
    }

    // 全系列の現在値を 1 点ずつ push する（方式 B Timer / seriesValues 変化トリガで使う）。
    function _pushAllSeries() {
        var n = root.effectiveSeriesCount;
        if (root.series && root.series.length > 0) {
            for (var i = 0; i < n; ++i) {
                var sv = (root.seriesValues && i < root.seriesValues.length) ? root.seriesValues[i] : undefined;
                if (sv !== undefined) {
                    root._pushAt(i, sv);
                }
            }
        } else {
            // 暗黙 1 系列（series 空）は従来の value を系列 0 へ。
            root._pushAt(0, root.value);
        }
    }

    // テスト用統計（sampleCounts / lastValues）のリセット。テストが直接代入する代わりに
    // この関数経由でまとめてリセットできる（外部 API を明確にする）。
    function resetStats() {
        var n = root.effectiveSeriesCount;
        var counts = [];
        var lasts = [];
        for (var i = 0; i < n; ++i) {
            counts.push(0);
            lasts.push(0);
        }
        root.sampleCounts = counts;
        root.lastValues = lasts;
    }

    // 系列数が変わったらバッファ・統計配列を揃える。
    onEffectiveSeriesCountChanged: {
        root._ensureSeriesArrays();
        canvas.requestPaint();
    }

    // pointCount を実行時に大→小へ変えたとき、次の push を待たず全系列バッファを即トリムする
    // （resolvedPointCount 超過分の最古を捨てて再描画。縮小が描画へ即反映される）。
    onResolvedPointCountChanged: {
        var bufs = root._buffers ? root._buffers.slice() : [];
        var changed = false;
        for (var i = 0; i < bufs.length; ++i) {
            if (bufs[i] && bufs[i].length > root.resolvedPointCount) {
                var buf = bufs[i].slice();
                while (buf.length > root.resolvedPointCount) {
                    buf.shift();
                }
                bufs[i] = buf;
                changed = true;
            }
        }
        if (changed) {
            root._syncingBuffer = true;
            root._buffers = bufs;
            root._syncingBuffer = false;
            canvas.requestPaint();
        }
    }

    width: 240
    height: 120
    // 不透明度は組込み `opacity` へ resolvedOpacity（未指定→1.0）を割り当てる。
    // disabled（widgetEnabled=false）のとき淡色（0.4 倍）にする（他 Widget と同型）。
    opacity: root.resolvedOpacity * (root.widgetEnabled ? 1.0 : 0.4)
    // 背景・枠は root（Rectangle）に持たせる（HmiLabel と同じく描画の地）。
    color: root.resolvedBackgroundColor
    radius: root.resolvedCornerRadius
    border.color: root.resolvedBorderColor
    border.width: root.resolvedBorderWidth

    // 方式 A（既定）：値変化のたび 1 点取り込む（live のときだけ）。
    // **方式 B（周期 Timer, sampleMs>0）が有効なときは方式 A を抑止する**（同一変化で
    // 2 点取り込む二重サンプルを避け、等間隔サンプリングを保つ）。
    //   - 多系列（series 非空）：seriesValues 変化で全系列を 1 点ずつ取り込む。
    //   - 単系列（series 空・後方互換）：value 変化で系列 0 を取り込む。
    onValueChanged: {
        if (root.live && root.sampleMs <= 0
                && !(root.series && root.series.length > 0)) {
            root._pushAt(0, root.value);
        }
    }
    onSeriesValuesChanged: {
        if (root.live && root.sampleMs <= 0
                && root.series && root.series.length > 0) {
            root._pushAllSeries();
        }
    }

    // 方式 B（sampleMs>0）：固定間隔で全系列の現在値を 1 点ずつ取り込む。
    Timer {
        running: root.live && root.sampleMs > 0
        interval: root.sampleMs > 0 ? root.sampleMs : 1000
        repeat: true
        onTriggered: root._pushAllSeries()
    }

    // 折れ線描画。X はバッファ index を幅へ等間隔マップ、Y は effective Y 範囲を高さへ
    // マップ（QML Canvas は Y 下向きなので上下反転に注意＝高い値が上）。
    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 2

        // 描画に影響する resolved 値の変化でも再描画する（線色・点数・Y 範囲・サイズ・系列）。
        Connections {
            target: root
            function onResolvedLineColorChanged() { canvas.requestPaint() }
            function onResolvedPointCountChanged() { canvas.requestPaint() }
            function onHasYMinChanged() { canvas.requestPaint() }
            function onHasYMaxChanged() { canvas.requestPaint() }
            function onYMinChanged() { canvas.requestPaint() }
            function onYMaxChanged() { canvas.requestPaint() }
            function onSeriesChanged() { canvas.requestPaint() }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        // 系列 i の線色を解決する（series[i].color 空 → 既定パレット。系列 0 の単系列互換は
        // resolvedLineColor を優先する＝Phase 8 の単系列線色指定を尊重）。
        function _seriesColor(i) {
            if (root.series && root.series.length > 0) {
                var c = root.series[i] ? root.series[i].color : "";
                if (c !== undefined && c !== null && c !== "") {
                    return c;
                }
                return root._palette[i % root._palette.length];
            }
            // 暗黙 1 系列（後方互換）は従来の resolvedLineColor。
            return root.resolvedLineColor;
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width;
            var h = height;
            if (w <= 0 || h <= 0) {
                return;
            }
            var bufs = root._buffers ? root._buffers : [];
            var seriesN = root.effectiveSeriesCount;

            // 実効 Y 範囲：presence 指定があればそれ、無ければ全系列横断の min/max 自動スケール。
            var lo, hi;
            if (root.hasYMin && root.hasYMax) {
                lo = root.yMin;
                hi = root.yMax;
            } else {
                var dataMin = NaN;
                var dataMax = NaN;
                for (var s = 0; s < seriesN; ++s) {
                    var b = (s < bufs.length && bufs[s]) ? bufs[s] : [];
                    for (var k = 0; k < b.length; ++k) {
                        if (isNaN(dataMin) || b[k] < dataMin) dataMin = b[k];
                        if (isNaN(dataMax) || b[k] > dataMax) dataMax = b[k];
                    }
                }
                if (isNaN(dataMin)) {
                    return;  // 全系列が空＝描画不可
                }
                lo = root.hasYMin ? root.yMin : dataMin;
                hi = root.hasYMax ? root.yMax : dataMax;
            }
            // min > max（逆転指定）は入れ替えて正規化する。
            if (lo > hi) {
                var t = lo; lo = hi; hi = t;
            }
            // 全点同値 / 範囲ゼロのゼロ除算ガード：中央に水平線を引く。
            var span = hi - lo;
            if (span <= 0) {
                span = 1;
                lo = lo - 0.5;
            }

            // 系列ごとに N 本の折れ線を描く（系列色で色分け）。
            ctx.lineWidth = 2;
            for (var si = 0; si < seriesN; ++si) {
                var buf = (si < bufs.length && bufs[si]) ? bufs[si] : [];
                var n = buf.length;
                if (n < 2) {
                    continue;  // 1 点以下は線を引けない（系列ごとに判定）
                }
                var stepX = w / (n - 1);
                ctx.strokeStyle = canvas._seriesColor(si);
                ctx.beginPath();
                for (var i = 0; i < n; ++i) {
                    var x = i * stepX;
                    // Y 上下反転（高い値が上 = 小さい y ピクセル）。
                    var y = h - ((buf[i] - lo) / span) * h;
                    if (i === 0) {
                        ctx.moveTo(x, y);
                    } else {
                        ctx.lineTo(x, y);
                    }
                }
                ctx.stroke();
            }
        }
    }

    // Editor プレビュー（live:false）：ダミー波形を 1 度だけ埋めて描画する。サンプリング
    // （onValueChanged push）・Timer は live:false では動かないので、ここでバッファを直接
    // 埋める。**sampleCount は増やさない**（実サンプルの観測を濁さないため。プレビューは
    // 実際の取り込みではない）。
    Component.onCompleted: {
        if (!root.live) {
            root._fillPreview();
        }
    }
    // series の追加 / 削除でもプレビュー波形を埋め直す（Editor で系列を増減したとき
    // ダミー波形が系列数に追従するように）。
    onSeriesChanged: {
        if (!root.live) {
            root._fillPreview();
        }
    }

    // Editor プレビュー（live:false）：系列数ぶんダミー波形を色違いで埋める。サンプリング
    // （push トリガ）・Timer は live:false では動かないので、ここでバッファを直接埋める。
    // **sampleCounts は増やさない**（実サンプルの観測を濁さない。プレビューは取り込みではない）。
    function _fillPreview() {
        var count = root.resolvedPointCount;
        // ダミー波形は **設定中の Y 範囲いっぱい** に張る（固定 Y 軸が設定された Widget で
        // 0..1 の波が下端へ潰れて「真っ黒な箱＋底辺の線」に見えるのを防ぐ）。両端指定が
        // あれば [yMin, yMax]、無ければ [0, 1]（自動スケールがそのまま全高へ広げる）。
        var effLo = root.hasYMin ? root.yMin : 0;
        var effHi = root.hasYMax ? root.yMax : 1;
        if (effHi <= effLo) {
            effLo = 0;
            effHi = 1;
        }
        var seriesN = root.effectiveSeriesCount;
        var bufs = [];
        for (var s = 0; s < seriesN; ++s) {
            var buf = [];
            // 系列ごとに位相をずらしたサイン波（重ね描きで複数系列が見分けられるように）。
            var phase = s * 0.7;
            for (var i = 0; i < count; ++i) {
                var t = Math.sin(i / count * Math.PI * 4 + phase) * 0.5 + 0.5;
                buf.push(effLo + t * (effHi - effLo));
            }
            bufs.push(buf);
        }
        root._syncingBuffer = true;
        root._buffers = bufs;
        root._syncingBuffer = false;
        canvas.requestPaint();
    }

    // 選択用 MouseArea。Canvas の上に重ねて clicked を中継する（Editor の選択に使う）。
    // HmiLabel と同型（NumericField のような入力欲取り合いが無いので enabled 出し分けは不要）。
    MouseArea {
        id: selectArea
        objectName: "trendSelectArea"
        anchors.fill: parent
        onClicked: function(mouse) { root.clicked(mouse.modifiers) }
    }
}
