import QtQuick

// Task M-B（Phase 10）: 共有 Meter Widget（車のスピードメーター風＝円弧（アーク）＋針）。
// Phase 5（Label）/ Phase 6（NumericField）/ Phase 8（Trend）で確立した横展開テンプレ
// （resolved\* フォールバック方式 + 選択中継 clicked + delegate 型分岐）に乗せた新 Widget 種別。
// 設計の正本は Docs/archive/phase10-meter-plan.md「HmiMeter.qml（§Task M-B）」。
//
// **新 Qt 依存ゼロが本フェーズの最重要制約**：描画は QML 標準の `Canvas` 自描画
// （`import QtQuick` のみ。QtCharts / QtQuick.Controls など新規モジュールを import しない）。
// これにより i.MX8MP rootfs にそのまま載る（Trend で実証済み。Phase 7 で QtSerialBus が
// kit/rootfs 未同梱だった轍を踏まない）。ファイル名 `HmiMeter` は QtQuick 標準型と非衝突
// （中で `Canvas{}` 型を使うのは可。CLAUDE.md「QtQuick 標準型と同名の QML ファイルを作らない」規約）。
//
// HmiButton / HmiLabel / HmiNumericField / HmiTrend と持つ／持たないの差：
//   - 持つ：value（値源）/ meterMin+hasMeterMin / meterMax+hasMeterMax / arcColor / needleColor /
//           tickCount / unit / live、背景・枠スタイル（resolved\*）、値→角度マッピング
//           （needleAngle）、Canvas 自描画（弧/目盛り/針/中央数値）、選択中継 clicked。
//   - 持たない：text / フォント / checkable / checked / クリックアクション（表示専用＝
//           binding の「読み」のみ。書きはしない）。
//
// 値源の役割分担（plan §各アプリの役割）：
//   - Simulator/Runtime（live:true）：delegate が boundValue("value") を value へバインドし、
//     変数の現在値変化で針が追従する。Runtime は本ソース共有で自動継承。
//   - Editor（live:false）：ライブ値が無い設計面なので中間値（(min+max)/2）をプレビュー表示。
Rectangle {
    id: root

    // 値源（数値）。delegate が boundValue("value") を流す（live:true）。Editor プレビュー
    // （live:false）では使わない（中間値プレビューを別途 previewValue で描く）。
    property real value: 0

    // スケール範囲（presence フラグ方式。負値が正当なのでセンチネル不可。WidgetData の
    // hasMeterMin/hasMeterMax 由来）。未指定（has*=false）は既定 0 / 100 へ解決する。
    property real meterMin: 0
    property real meterMax: 0
    property bool hasMeterMin: false
    property bool hasMeterMax: false

    // 弧の色。空 = 未指定＝既定弧色（#4cc9f0）へ解決（backgroundColor 同型）。
    property string arcColor: ""
    // 針の色。空 = 未指定＝既定針色（#ff595e）へ解決。
    property string needleColor: ""

    // 目盛り本数。`0`（/負値）= 未指定＝既定 10 へ解決（Trend の pointCount と同じ `0` センチネル）。
    property int tickCount: 0

    // 中央数値の単位（例 "km/h"）。空 = 単位表示なし（Trend の lineColor 同型）。
    property string unit: ""

    // ライブ実行か（Simulator/Runtime=true 実値追従 / Editor=false 中間値プレビュー）。
    property bool live: false

    // スタイル入力。色は "#RRGGBB"（空 = 未指定）。HmiTrend の resolved\* と同じ命名・既定で
    // 流用（borderWidth / cornerRadius は `-1` センチネル）。
    property string backgroundColor: ""
    property string borderColor: ""
    property int borderWidth: -1
    property int cornerRadius: -1

    // 不透明度（`Item.opacity` 衝突回避で widgetOpacity。`-1` 未指定）。
    property real widgetOpacity: -1
    // `Item.enabled` 衝突回避で widgetEnabled。false で淡色表示（他 Widget と同型）。
    property bool widgetEnabled: true

    // 未指定（空 / 0 / -1）のときの既定外観。プロジェクト全体でここだけが Meter の既定値を
    // 持つ（Button / Label / NumericField / Trend と同じ集約パターン）。**スピードメーター
    // らしい濃紺背景 + 水色の弧 + 赤い針**が他 Widget との既定差分（plan 記載値）。
    readonly property real resolvedMeterMin: hasMeterMin ? meterMin : 0
    readonly property real resolvedMeterMax: hasMeterMax ? meterMax : 100
    readonly property color resolvedArcColor: arcColor !== "" ? arcColor : "#4cc9f0"
    readonly property color resolvedNeedleColor: needleColor !== "" ? needleColor : "#ff595e"
    readonly property int resolvedTickCount: tickCount > 0 ? tickCount : 10
    readonly property color resolvedBackgroundColor: backgroundColor !== "" ? backgroundColor : "#0b1d2a"

    readonly property color resolvedBorderColor: borderColor !== "" ? borderColor : "#9aa5b1"
    readonly property int resolvedBorderWidth: borderWidth >= 0 ? borderWidth : 1
    readonly property int resolvedCornerRadius: cornerRadius >= 0 ? cornerRadius : 4

    // 未指定（`< 0`）のとき不透明度 1.0（完全不透明）にフォールバック。
    readonly property real resolvedOpacity: widgetOpacity >= 0 ? widgetOpacity : 1.0

    // 弧の角度域（スピードメーター既定）。Canvas 座標（y 下向き・角度は +x 軸から時計回り）で、
    // 針は startAngle（下左）→ endAngle（下右）を上側を通って 270° 掃引する（底面 90° が開く）。
    //   135° = 下左（min） / 270° = 真上 / 405°(=45°) = 下右（max）。
    // 見た目依存の既定値。乖離したら同コミットで plan を更新する（plan リスク 2）。
    readonly property real startAngle: 135
    readonly property real spanAngle: 270
    readonly property real endAngle: startAngle + spanAngle

    // 値→表示値：resolved 範囲で clamp する。max<=min（不正範囲）は退避して下限へ張り付かせる
    // （0 除算回避＝plan リスク 3）。Editor プレビュー（live:false）は中間値を表示する。
    readonly property real _effectiveValue: root.live ? root.value : root.previewValue
    readonly property real displayValue: {
        var lo = root.resolvedMeterMin;
        var hi = root.resolvedMeterMax;
        if (hi <= lo) {
            return lo;
        }
        // 非数値（NaN / ±Inf）は下限へ落とす。binding {property:"value"} が文字列変数
        // （例 "ON"）や非数値の静的 value を指すと SimulatorCanvas から Number(...) が NaN で
        // 渡り、そのまま clamp すると displayValue / needleAngle が NaN になって中央表示・針が
        // 壊れる（Codex PR #153 [P2]）。有限数でなければ下限へ退避してから clamp する。
        var v = root._effectiveValue;
        if (!isFinite(v)) {
            return lo;
        }
        return Math.max(lo, Math.min(hi, v));
    }

    // Editor プレビュー用の中間値（(min+max)/2）。live:false のとき displayValue が参照する。
    readonly property real previewValue: (root.resolvedMeterMin + root.resolvedMeterMax) / 2

    // テスト用公開：針角度[deg]。value を弧の角度域へ線形マッピング + clamp した結果。
    // min→startAngle / 中点→startAngle+span/2 / max→endAngle。Canvas はピクセル不可視なので
    // unit / E2E はこの公開プロパティで「値→針追従」を観測する（plan §テスト方針）。
    readonly property real needleAngle: {
        var lo = root.resolvedMeterMin;
        var hi = root.resolvedMeterMax;
        if (hi <= lo) {
            return root.startAngle;
        }
        var frac = (root.displayValue - lo) / (hi - lo);
        return root.startAngle + frac * root.spanAngle;
    }

    // 選択中継用 clicked（Editor の選択に使う。modifiers は複数選択の加除用）。
    // HmiButton / HmiLabel / HmiNumericField / HmiTrend の clicked(int modifiers) と同形。
    // Simulator は接続しない＝表示専用。
    signal clicked(int modifiers)

    width: 200
    height: 200
    // 不透明度は組込み `opacity` へ resolvedOpacity（未指定→1.0）を割り当てる。
    // disabled（widgetEnabled=false）のとき淡色（0.4 倍）にする（他 Widget と同型）。
    opacity: root.resolvedOpacity * (root.widgetEnabled ? 1.0 : 0.4)
    // 背景・枠は root（Rectangle）に持たせる（HmiTrend と同じく描画の地）。
    color: root.resolvedBackgroundColor
    radius: root.resolvedCornerRadius
    border.color: root.resolvedBorderColor
    border.width: root.resolvedBorderWidth

    // 描画に影響する値の変化で再描画する。
    onDisplayValueChanged: canvas.requestPaint()
    onNeedleAngleChanged: canvas.requestPaint()

    // 弧・目盛り・針・中央数値を自描画する Canvas。root から margins:4 内側。
    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: 4

        // 描画に影響する resolved 値の変化でも再描画する（弧色・針色・目盛り数・範囲・サイズ）。
        Connections {
            target: root
            function onResolvedArcColorChanged() { canvas.requestPaint() }
            function onResolvedNeedleColorChanged() { canvas.requestPaint() }
            function onResolvedTickCountChanged() { canvas.requestPaint() }
            function onResolvedMeterMinChanged() { canvas.requestPaint() }
            function onResolvedMeterMaxChanged() { canvas.requestPaint() }
            function onUnitChanged() { canvas.requestPaint() }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width;
            var h = height;
            if (w <= 0 || h <= 0) {
                return;
            }
            // メーター中心・半径。中心は水平中央、垂直はやや下寄り（下側 90° が開くため
            // 弧が上半分に寄る＝中心を少し下げると弧が枠に収まりやすい）。
            var cx = w / 2;
            var cy = h * 0.58;
            var r = Math.min(w, h) * 0.42;
            if (r <= 0) {
                return;
            }
            var d2r = Math.PI / 180;
            var startRad = root.startAngle * d2r;
            var endRad = root.endAngle * d2r;

            // ① スケール弧（resolvedArcColor）。startAngle→endAngle を時計回り（y 下向き
            // Canvas では anticlockwise=false が時計回り）に描く。
            ctx.lineWidth = Math.max(2, r * 0.12);
            ctx.strokeStyle = root.resolvedArcColor;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.arc(cx, cy, r, startRad, endRad, false);
            ctx.stroke();

            // ② 目盛り（resolvedTickCount 本）。弧を等分し各点に短い放射線を引く。
            var ticks = root.resolvedTickCount;
            if (ticks > 0) {
                ctx.lineWidth = 1;
                ctx.strokeStyle = "#9aa5b1";
                var tickOuter = r + ctx.lineWidth;
                var tickInner = r - Math.max(4, r * 0.14);
                for (var t = 0; t <= ticks; ++t) {
                    var a = (root.startAngle + (t / ticks) * root.spanAngle) * d2r;
                    var ca = Math.cos(a);
                    var sa = Math.sin(a);
                    ctx.beginPath();
                    ctx.moveTo(cx + ca * tickInner, cy + sa * tickInner);
                    ctx.lineTo(cx + ca * tickOuter, cy + sa * tickOuter);
                    ctx.stroke();
                }
            }

            // ③ 針（resolvedNeedleColor、needleAngle 方向）。中心から弧の内側まで伸ばす。
            var na = root.needleAngle * d2r;
            var needleLen = r - Math.max(4, r * 0.14);
            ctx.lineWidth = Math.max(2, r * 0.05);
            ctx.strokeStyle = root.resolvedNeedleColor;
            ctx.lineCap = "round";
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(cx + Math.cos(na) * needleLen, cy + Math.sin(na) * needleLen);
            ctx.stroke();
            // 針の軸（中心のハブ）。
            ctx.fillStyle = root.resolvedNeedleColor;
            ctx.beginPath();
            ctx.arc(cx, cy, Math.max(3, r * 0.08), 0, Math.PI * 2, false);
            ctx.fill();

            // ④ 中央数値（displayValue + unit）。弧の下側の開き部分に置く。実機 image に
            // 和文フォントが無いので単位は ASCII 前提（plan リスク 5。数値は言語非依存）。
            var label = String(Math.round(root.displayValue * 100) / 100);
            if (root.unit !== "") {
                label += " " + root.unit;
            }
            ctx.fillStyle = "#e6edf3";
            ctx.font = Math.max(10, r * 0.22) + "px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(label, cx, cy + r * 0.5);
        }
    }

    // 選択用 MouseArea。Canvas の上に重ねて clicked を中継する（Editor の選択に使う）。
    // HmiTrend と同型（NumericField のような入力欲取り合いが無いので enabled 出し分け不要）。
    MouseArea {
        id: selectArea
        objectName: "meterSelectArea"
        anchors.fill: parent
        onClicked: function(mouse) { root.clicked(mouse.modifiers) }
    }
}
