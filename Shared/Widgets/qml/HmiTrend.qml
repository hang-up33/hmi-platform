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
//   - 持つ：value（サンプル源）/ pointCount / yMin+hasYMin / yMax+hasYMax / lineColor /
//           sampleMs / live、背景・枠スタイル（resolved\*）、リングバッファ + Canvas 描画、
//           選択中継 clicked。
//   - 持たない：text / フォント / checkable / checked / クリックアクション（表示専用＝
//           binding の「読み」のみ。書きはしない）。
//
// サンプル取り込みの役割分担（plan §Task B）：
//   - Simulator/Runtime（live:true）：delegate が boundValue("value") を value へバインドし、
//     値変化（方式 A）または周期 Timer（方式 B, sampleMs>0）でリングバッファへ push。
//   - Editor（live:false）：ライブデータが無い設計面なので Component.onCompleted で
//     ダミー波形を 1 度だけ埋めて描画（サンプリング・Timer は動かさない）。
Rectangle {
    id: root

    // サンプル源（数値）。delegate が boundValue("value") を流す（live:true）。
    // Editor プレビュー（live:false）では使わない（ダミー波形を別途埋める）。
    property real value: 0

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

    // リングバッファ（直近 resolvedPointCount 点）。push 順に値を保持し、満杯で先頭を捨てる。
    property var _buffer: []

    // テスト用公開プロパティ（read-only）。Canvas のピクセルは E2E / unit から不可視なので、
    // これらの公開 API を観測して「サンプル取り込み」を検証する（plan §Task D）。
    //   sampleCount : 取り込んだ実サンプルの総数（push 回数）。Editor プレビューの
    //                 ダミー波形は数えない（実サンプルの観測を濁さないため）。
    //   lastValue   : 直近 push した値。
    //   bufferSize  : 現在のバッファ長（満杯時は resolvedPointCount に一致）。
    property int sampleCount: 0
    property real lastValue: 0
    readonly property int bufferSize: _buffer.length

    // リングバッファへ 1 点 push する。数値でない値は無視する。満杯（resolvedPointCount
    // 超過）なら先頭を捨てて横スクロールを実現する。push 後に再描画を要求する。
    function _push(v) {
        var n = Number(v);
        if (isNaN(n)) {
            return;
        }
        // 再代入でバインディング（bufferSize）へ通知するため毎回コピーする。高頻度
        // サンプリング（例 sampleMs=50＝20Hz）では将来の最適化候補（リングインデックス化等。
        // 実機 Canvas 性能 VNC 確認 TODO と合わせて評価）。MVP は素朴な slice で十分。
        var buf = root._buffer.slice();
        buf.push(n);
        while (buf.length > root.resolvedPointCount) {
            buf.shift();
        }
        root._buffer = buf;
        root.lastValue = n;
        root.sampleCount += 1;
        canvas.requestPaint();
    }

    // テスト用統計（sampleCount / lastValue）のリセット。テストが直接代入する代わりに
    // この関数経由でまとめてリセットできる（外部 API を明確にする）。
    function resetStats() {
        root.sampleCount = 0;
        root.lastValue = 0;
    }

    // pointCount を実行時に大→小へ変えたとき、次の _push を待たずバッファを即トリムする
    // （resolvedPointCount 超過分の最古を捨てて再描画。縮小が描画へ即反映される）。
    onResolvedPointCountChanged: {
        if (root._buffer.length > root.resolvedPointCount) {
            var buf = root._buffer.slice();
            while (buf.length > root.resolvedPointCount) {
                buf.shift();
            }
            root._buffer = buf;
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

    // 方式 A（既定）：value 変化のたび 1 点取り込む（live のときだけ）。
    // **方式 B（周期 Timer, sampleMs>0）が有効なときは方式 A を抑止する**（同一変化で
    // 2 点取り込む二重サンプルを避け、等間隔サンプリングを保つ）。
    onValueChanged: {
        if (root.live && root.sampleMs <= 0) {
            root._push(root.value);
        }
    }

    // 方式 B（sampleMs>0）：固定間隔で現在 value を取り込む。
    Timer {
        running: root.live && root.sampleMs > 0
        interval: root.sampleMs > 0 ? root.sampleMs : 1000
        repeat: true
        onTriggered: root._push(root.value)
    }

    // 折れ線描画。X はバッファ index を幅へ等間隔マップ、Y は effective Y 範囲を高さへ
    // マップ（QML Canvas は Y 下向きなので上下反転に注意＝高い値が上）。
    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 2

        // 描画に影響する resolved 値の変化でも再描画する（線色・点数・Y 範囲・サイズ）。
        Connections {
            target: root
            function onResolvedLineColorChanged() { canvas.requestPaint() }
            function onResolvedPointCountChanged() { canvas.requestPaint() }
            function onHasYMinChanged() { canvas.requestPaint() }
            function onHasYMaxChanged() { canvas.requestPaint() }
            function onYMinChanged() { canvas.requestPaint() }
            function onYMaxChanged() { canvas.requestPaint() }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width;
            var h = height;
            var buf = root._buffer;
            var n = buf.length;
            if (n < 2 || w <= 0 || h <= 0) {
                return;  // 1 点以下 / サイズ無しは線を引けない
            }

            // 実効 Y 範囲：presence 指定があればそれ、無ければバッファの min/max 自動スケール。
            var lo, hi;
            if (root.hasYMin && root.hasYMax) {
                lo = root.yMin;
                hi = root.yMax;
            } else {
                var dataMin = buf[0];
                var dataMax = buf[0];
                for (var k = 1; k < n; ++k) {
                    if (buf[k] < dataMin) dataMin = buf[k];
                    if (buf[k] > dataMax) dataMax = buf[k];
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

            var stepX = w / (n - 1);
            ctx.lineWidth = 2;
            ctx.strokeStyle = root.resolvedLineColor;
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

    // Editor プレビュー（live:false）：ダミー波形を 1 度だけ埋めて描画する。サンプリング
    // （onValueChanged push）・Timer は live:false では動かないので、ここでバッファを直接
    // 埋める。**sampleCount は増やさない**（実サンプルの観測を濁さないため。プレビューは
    // 実際の取り込みではない）。
    Component.onCompleted: {
        if (!root.live) {
            var buf = [];
            var count = root.resolvedPointCount;
            for (var i = 0; i < count; ++i) {
                // 0..1 を行き来するサイン波（見た目のプレビュー用）。
                buf.push(Math.sin(i / count * Math.PI * 4) * 0.5 + 0.5);
            }
            root._buffer = buf;
            canvas.requestPaint();
        }
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
