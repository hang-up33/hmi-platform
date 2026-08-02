import QtQuick

// 共有 Simple Button Widget（issue #155「シンプル・イズ・ベスト版 HMI ボタン」の QML 移植）。
// ベゼル無し・装飾無しの最小構成＝フラット面 + やわらかい影 + 差し色ひとつ + 状態ひとつ。
// 唯一のモーションは長押し中の進捗リング（円）/ 進捗バー（四角）。確定で ON/OFF トグル。
//
// 方針（Phase 11 計画）：
// - `import QtQuick` のみ＝新 Qt モジュール依存ゼロ（QtQuick.Shapes / Controls 非依存。
//   i.MX8MP rootfs にそのまま載る。Meter / Trend と同方針）。面 + 影 + 進捗は Canvas 自描画。
// - HmiButton / HmiMeter と同じ resolved* フォールバック方式（未指定＝空文字 / 0 を既定へ解決）。
// - テーマ配色は issue の SIMPLE_THEMES（oklch / color-mix）を Qt Quick 対応の hex へ換算して保持。
// - Editor は静的プレビュー（live:false＝進捗を動かさない）、Simulator/Runtime は長押し実挙動（live:true）。
Item {
    id: root

    width: 184
    height: 184

    // ── 共通状態（他 Widget と同型。opacity/enabled を SimpleButton にも反映。Codex PR #164 [P2]）──
    // Item.opacity / Item.enabled 組込みと衝突するため公開入力は widget* 命名（規約通り）。
    // widgetOpacity は -1 センチネル（未指定＝1.0）、widgetEnabled は既定 true（false で淡色 + 長押し無効）。
    property real widgetOpacity: -1.0
    property bool widgetEnabled: true
    readonly property real resolvedOpacity: widgetOpacity >= 0 ? widgetOpacity : 1.0
    // Task 42（HmiButton）と同型：disabled は淡色で見せる。MouseArea は止めない
    //（Editor の「クリックで選択」中継を殺さないため）。長押しの実行無効化は _beginHold で行う。
    opacity: resolvedOpacity * (widgetEnabled ? 1.0 : 0.4)

    // ── 公開入力（未指定＝空 / 0 は resolved* で既定へ）────────────────
    property string text: "TEST"           // 面中央のラベル（issue の "TEST"）
    property string shape: ""              // "circle" | "square"（空＝circle）
    property string theme: ""              // "light" | "dark"（空＝light）
    property string accentColor: ""        // 差し色（空＝テーマ既定の緑）
    property int holdMs: 0                  // 長押し確定に要する時間 ms（0＝既定 800）
    property bool checked: false           // ON / OFF 状態
    property bool live: true               // true=長押し実挙動 / false=静的プレビュー

    // ── 通知 ────────────────────────────────────────────────────
    // Editor の選択中継用（表示専用でも横展開テンプレ則で必ず持つ）。
    signal clicked(int modifiers)
    // 長押し確定でトグルした時に emit（Simulator が変数書き戻しへ結線する想定）。
    signal toggled(bool value)

    // ── テーマ配色（issue SIMPLE_THEMES の oklch → hex 換算。乖離あれば調整）──
    readonly property var _themes: ({
        "light": { face: "#ffffff", faceHover: "#fbfaf7", facePress: "#f1efe9",
                   onFill: "#eef6ef", ring: "#dad7d1", text: "#3a3733", dim: "#98948e",
                   accent: "#2fa563", track: "#ebe9e5", shadow: "#28241c", shadowA: 0.10 },
        "dark":  { face: "#2b2f36", faceHover: "#31353d", facePress: "#23262c",
                   onFill: "#2c3a34", ring: "#4b4f57", text: "#e9eaec", dim: "#8b8f97",
                   accent: "#56d68a", track: "#21242a", shadow: "#000000", shadowA: 0.40 }
    })

    // ── resolved*（既定外観の単一ソース）──────────────────────────
    readonly property string resolvedTheme: theme === "dark" ? "dark" : "light"
    readonly property var pal: _themes[resolvedTheme]
    readonly property bool isCircle: shape !== "square"          // 空 / 不正値は circle
    readonly property color resolvedAccent: accentColor !== "" ? accentColor : pal.accent
    readonly property int resolvedHoldMs: holdMs > 0 ? holdMs : 800

    // ── 内部状態 ────────────────────────────────────────────────
    property bool _pressed: false
    property bool _hover: false
    // 長押し進捗（0..1）。テスト / E2E 用に公開（Canvas は不可視なので）。
    property real holdProgress: 0.0

    readonly property color faceColor: checked ? pal.onFill
                                     : _pressed ? pal.facePress
                                     : _hover ? pal.faceHover
                                     : pal.face

    onCheckedChanged: face.requestPaint()
    onHoldProgressChanged: face.requestPaint()
    onFaceColorChanged: face.requestPaint()
    onResolvedAccentChanged: face.requestPaint()
    // Codex PR #158: 形状（circle↔square）・サイズ変更でも面/進捗を描き直す
    // （ランプ/テキストは binding で追従するが Canvas は明示 requestPaint が要る）。
    onIsCircleChanged: face.requestPaint()
    onWidthChanged: face.requestPaint()
    onHeightChanged: face.requestPaint()

    // ── 長押しタイマ（live:true のときだけ進捗を進める）──────────────
    // 押下開始で 0→1 へ、満了で「次の値」を toggled(!checked) で通知（進捗は 0 へ戻す）。
    // Codex PR #158 [P2]：**checked を自己代入しない**。Simulator/Runtime は
    // `checked: boundValue("checked")` を張り `onToggled` で変数へ書き戻す設計なので、
    // ここで命令代入すると外部バインディングが切れ、以後の VariableStore/PLC 由来の
    // checked 更新に追従しなくなる（NumericField の write-back と同型＝widget は状態を
    // 持たず「次値の通知」だけ担い、状態更新は consumer/binding 経路から戻す）。
    Timer {
        id: holdTimer
        interval: 16                    // ~60fps
        repeat: true
        running: false
        property double startedAt: 0
        onTriggered: {
            const elapsed = Date.now() - startedAt
            root.holdProgress = Math.min(1.0, elapsed / root.resolvedHoldMs)
            if (root.holdProgress >= 1.0) {
                holdTimer.stop()
                root.toggled(!root.checked)
                root.holdProgress = 0.0
            }
        }
    }
    function _beginHold() {
        // live:false（Editor プレビュー）は動かさない。widgetEnabled=false（無効）も
        // 長押し進捗を動かさない（無効ボタンで進捗リング/バーが伸びる誤作動を防ぐ。Codex PR #164 [P2]）。
        if (!root.live || !root.widgetEnabled)
            return
        holdTimer.startedAt = Date.now()
        root.holdProgress = 0.0
        holdTimer.start()
    }
    function _cancelHold() {
        holdTimer.stop()
        root.holdProgress = 0.0
    }
    // Task W-E: 長押し満了（確定）を模す公開メソッド。Spix は実 press-hold を発火できない
    // ため、E2E / unit はこれを invokeMethod で叩いて「押し続けて満ちた」状態遷移だけを起こす
    // （HmiNumericField.commitValue() と同じ「確定点を公開する」前例）。ガードは実挙動と同じ：
    // live:false（Editor プレビュー）と widgetEnabled=false（無効）では何もしない。
    // Timer 満了時と同様、checked は自己代入せず「次値」を toggled で通知するだけ
    // （状態更新は consumer/binding 経路から戻る。Codex PR #158 [P2] と同型）。
    function commitHold() {
        if (!root.live || !root.widgetEnabled)
            return
        holdTimer.stop()
        root.holdProgress = 0.0
        root.toggled(!root.checked)
    }

    // ── 面 + 影 + 進捗（Canvas 自描画）────────────────────────────
    Canvas {
        id: face
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            const pad = 12                              // 影のにじみ代
            const accent = root.resolvedAccent

            // 影（Canvas 2D の shadow で「浮いている」やわらかさを出す＝ベゼルの代替）
            ctx.save()
            ctx.shadowColor = Qt.rgba(0, 0, 0, root.pal.shadowA)
            ctx.shadowBlur = root._pressed ? 6 : 16
            ctx.shadowOffsetY = root._pressed ? 1 : 6
            ctx.fillStyle = root.faceColor

            if (root.isCircle) {
                const cx = w / 2, cy = h / 2
                // Codex PR #158 [Minor]：極小サイズ（最小リサイズ付近）で半径が負に
                // なると Canvas arc() が描けず paint が壊れるため 0 でクランプする。
                const r = Math.max(0, Math.min(w, h) / 2 - pad)
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                ctx.fill()
                ctx.restore()
                // 細いリング輪郭（ベゼルではなく面の縁取り）
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                ctx.lineWidth = 1.5
                ctx.strokeStyle = root.pal.ring
                ctx.stroke()
                // 進捗リング（上 -90° から時計回り）。半径 rr が正のときだけ描く
                // （小サイズで rr が負になると arc() が壊れる。Codex PR #158）。
                const rr = r - 5
                if (root.holdProgress > 0 && rr > 0) {
                    const start = -Math.PI / 2
                    ctx.beginPath()
                    ctx.arc(cx, cy, rr, start, start + 2 * Math.PI * root.holdProgress)
                    ctx.lineWidth = 5
                    ctx.lineCap = "round"
                    ctx.strokeStyle = accent
                    ctx.stroke()
                }
            } else {
                const x = pad, y = pad
                const rw = Math.max(0, w - 2 * pad), rh = Math.max(0, h - 2 * pad)
                const rad = Math.min(22, rh / 2)
                root._roundRect(ctx, x, y, rw, rh, rad)
                ctx.fill()
                ctx.restore()
                root._roundRect(ctx, x, y, rw, rh, rad)
                ctx.lineWidth = 1.5
                ctx.strokeStyle = root.pal.ring
                ctx.stroke()
                // 進捗バー（下端・面幅に比例）
                if (root.holdProgress > 0) {
                    const bh = 5, bx = x + 14, by = y + rh - 16
                    const bw = (rw - 28) * root.holdProgress
                    root._roundRect(ctx, bx, by, Math.max(bw, bh), bh, bh / 2)
                    ctx.fillStyle = accent
                    ctx.fill()
                }
            }
        }
    }

    function _roundRect(ctx, x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.arcTo(x + w, y, x + w, y + h, r)
        ctx.arcTo(x + w, y + h, x, y + h, r)
        ctx.arcTo(x, y + h, x, y, r)
        ctx.arcTo(x, y, x + w, y, r)
        ctx.closePath()
    }

    // ── ランプ（右上・ON で差し色に発光。OFF はトラック色）──────────
    // 円は面円の右上（中心から 45° 上・右へ）、四角は右上角の内側へ置く。
    readonly property real _faceR: Math.min(root.width, root.height) / 2 - 12
    readonly property real _lampCX: root.isCircle ? (root.width / 2 + _faceR * 0.52)
                                                  : (root.width - 12 - 22)
    readonly property real _lampCY: root.isCircle ? (root.height / 2 - _faceR * 0.52)
                                                  : (12 + 22)
    Rectangle {
        id: lamp
        width: 9
        height: 9
        radius: 4.5
        x: root._lampCX - width / 2
        y: root._lampCY - height / 2
        color: root.checked ? root.resolvedAccent : root.pal.track
        border.width: 1
        border.color: root.checked ? Qt.lighter(root.resolvedAccent, 1.15) : root.pal.ring
        // ON のとき淡い発光（新モジュール依存を避けるため二重矩形で擬似ハロー）
        Rectangle {
            visible: root.checked
            anchors.centerIn: parent
            width: parent.width + 8
            height: parent.height + 8
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: root.resolvedAccent
            opacity: 0.35
        }
    }

    // ── 中央ラベル：TEST を大きな主ラベルに、ON/OFF を小さなサブに（写真の構成）──
    // グループを面の縦横中央へ寄せ、TEST（大）→ 状態（小）を縦に積む。
    // 文字サイズは面の短辺に比例（Widget リサイズでも収まりと主従バランスを保つ）。
    readonly property real _base: Math.min(root.width, root.height)
    Column {
        anchors.centerIn: parent
        spacing: root._base * 0.06
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.text
            color: root.pal.text
            font.pixelSize: Math.round(root._base * 0.13)
            font.bold: true
            font.letterSpacing: root._base * 0.026
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.checked ? "ON" : "OFF"
            color: root.checked ? root.resolvedAccent : root.pal.dim
            font.pixelSize: Math.round(root._base * 0.078)
            font.letterSpacing: root._base * 0.022
        }
    }

    // ── 操作（長押し確定 + hover / press フィードバック + Editor 選択中継）──
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root._hover = true
        onExited: { root._hover = false; root._pressed = false; root._cancelHold() }
        onPressed: function(mouse) { root._pressed = true; root._beginHold() }
        onReleased: { root._pressed = false; root._cancelHold() }
        onCanceled: { root._pressed = false; root._cancelHold() }
        onClicked: function(mouse) { root.clicked(mouse.modifiers) }
    }
}
