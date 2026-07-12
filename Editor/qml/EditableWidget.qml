import QtQuick

// Editor 専用の編集ラッパー。
// 子要素をドラッグで動かせるようにし、自身（このItem）の x / y を更新する。
// HmiButton 等の共有 Widget は描画責務だけを持ち、ドラッグ等の編集操作はこちらに集約する。
// Simulator では使わない（Simulator は読み取り専用のため）。
//
// 構造のキモは MouseArea を子要素（container）の親階層に置き、
// `drag.filterChildren: true` を立てること。これにより、
//   1) 子の MouseArea（HmiButton 内の clicked / pressed）にまずイベントが届く
//   2) しきい値を超えるマウス移動を検出した時点で親 MouseArea が drag を発動して
//      イベントを奪う
// という Qt 標準の作法で、クリックとドラッグを両立できる。
//
// QML ファイル名は QtQuick 標準型と衝突しないことを CLAUDE.md で要請されており、
// "EditableWidget" は標準型に存在しないため安全。
Item {
    id: root

    // 子要素は container に直接配置される。Main.qml では HmiButton 1 個を入れて使う。
    default property alias content: container.data

    // ドラッグ中かどうか（将来：選択ハンドルや座標表示の切替に使う想定）
    readonly property bool dragging: dragArea.drag.active

    // Task 36: ドラッグ確定（active→false）を、**リーダーの吸着を済ませた後**に通知する。
    // Canvas が一括移動の最終差分（snapped）を兄弟 Widget へ反映するのに使う
    // （Codex PR #75 [P2]：snap 後に兄弟が追従せず相対位置がズレる問題の修正）。
    signal dragFinished()

    // Task 38: リサイズの開始 / 確定を Canvas へ通知し、undo の 1 操作境界にする
    // （Canvas は id が見えないため signal で結ぶ。delegate 側で beginEdit/commitEdit に結線）。
    signal resizeStarted()
    signal resizeFinished()

    // Shared/Schema の WidgetData に書き出すためのメタ情報。
    // Task 6（JSON 保存）で参照する。子の HmiButton 等はこの値をバインディングで参照する。
    property string widgetId: ""
    property string widgetType: "Button"
    property string widgetText: ""
    property string widgetTag: ""

    // Task 28: スタイル属性のメタ。HmiButton と同じく空文字 / 0 を「未指定」とし、
    // 既定外観へのフォールバックは HmiButton 側に集約する（ここでは既定値を持たない）。
    // 子の HmiButton には delegate（Canvas.qml）で wrapper 経由に渡す。
    property string widgetBackgroundColor: ""
    property string widgetTextColor: ""
    property int widgetFontSize: 0

    // Task 31: ボーダー＋角丸のメタ。数値は **`-1` = 未指定**（0 は正当値のため
    // 未指定に使えない。Schema / HmiButton と揃える）。既定外観へのフォールバックは
    // HmiButton 側に集約し、ここでは既定値を持たない。delegate（Canvas.qml）で
    // HmiButton へ widgetRadius → cornerRadius にマップして渡す。
    property string widgetBorderColor: ""
    property int widgetBorderWidth: -1
    property int widgetRadius: -1

    // Task 33: フォント詳細のメタ。bool は既定 false（太字/斜体なし）、fontFamily は
    // 空文字 = 未指定（システム既定）。既定外観は HmiButton 側に集約し、ここでは
    // 値を素通しするだけ。delegate（Canvas.qml）で HmiButton へ渡す。
    property bool widgetFontBold: false
    property bool widgetFontItalic: false
    property string widgetFontFamily: ""

    // Task 34: 配置 + 不透明度のメタ。配置は文字列（空 = 未指定 = 中央）。
    // 不透明度は **`widgetOpacity`** に統一する（HmiButton と同じく `Item.opacity` 組込みと
    // 衝突するため。`-1` = 未指定）。delegate（Canvas.qml）で HmiButton へ渡す。
    // JSON キー / WidgetData フィールドだけ `opacity` で、保存（snapshotModel）・
    // 読込（delegate バインド）時に widgetOpacity ↔ opacity をマップする。
    property string widgetHAlign: ""
    property string widgetVAlign: ""
    property real widgetOpacity: -1

    // Task 42: 状態別スタイルのメタ。**`widgetEnabled`** に統一する（HmiButton と同じく
    // `Item.enabled` 組込みと衝突するため。既定 true）。checkable / checked は組込み衝突が
    // 無いが命名を揃えて `widget*` 接頭辞にする。delegate（Canvas.qml）で HmiButton へ渡し、
    // snapshotModel が JSON キー enabled / checkable / checked へ書き戻す。
    property bool widgetEnabled: true
    property bool widgetCheckable: false
    property bool widgetChecked: false

    // Task 54: 数値範囲（NumericField の clamp 用）のメタ。**負値が正当なのでセンチネル不可**＝
    // presence フラグ（widgetHasMin / widgetHasMax）で未指定を表す。値（double）と presence を
    // 対で持つ。delegate（Canvas.qml）で HmiNumericField の minValue/maxValue/hasMin/hasMax へ
    // 渡し、snapshotModel が JSON キー minValue/maxValue/hasMinValue/hasMaxValue へ書き戻す。
    property real widgetMinValue: 0
    property real widgetMaxValue: 0
    property bool widgetHasMin: false
    property bool widgetHasMax: false

    // Task T-B（Phase 8）: Trend（トレンドグラフ）固有のメタ。点数 N / 線色 / 周期は
    // センチネル（0 / 空文字）、Y 軸範囲は presence フラグ方式（widgetHasYMin/Max）。
    // 既定外観は HmiTrend 側に集約し、ここでは素通しするだけ。delegate（Canvas.qml）で
    // HmiTrend の pointCount/yMin/hasYMin/yMax/hasYMax/lineColor/sampleMs へ渡し、
    // snapshotModel が JSON キー pointCount/yMin/yMax/lineColor/sampleMs へ書き戻す。
    property int widgetPointCount: 0
    property real widgetYMin: 0
    property real widgetYMax: 0
    property bool widgetHasYMin: false
    property bool widgetHasYMax: false
    property string widgetLineColor: ""
    property int widgetSampleMs: 0

    // Task 8B-A（Phase 8-B）: Trend 拡張（複数系列 + 軸目盛り/凡例）のメタ。描画 / 編集 UI は
    // 後続タスク（8B-B〜8B-D）だが、**series 付き Trend JSON を Editor で開いて保存しても
    // 失わない**ため、ここで素通し保持する（delegate が modelData から流し込み、snapshotModel が
    // JSON キー series/showGrid/showLegend/yTickCount へ書き戻す。Codex PR #132 [P2]）。
    property var widgetSeries: []
    property bool widgetShowGrid: false
    property bool widgetShowLegend: false
    property int widgetYTickCount: 0

    // Task M-A（Phase 10）: Meter（スピードメーター）固有のメタ。描画 / 追加 UI / インスペクタは
    // 後続タスク（M-B〜M-C）だが、**Meter JSON を Editor で開いて保存しても範囲・色・目盛り・単位を
    // 失わない**ため、ここで素通し保持する（delegate が modelData から流し込み、snapshotModel が
    // JSON キー meterMin/meterMax/arcColor/needleColor/tickCount/unit へ書き戻す。Codex PR #152 [P2]）。
    // スケール範囲は presence フラグ方式（widgetHasMeterMin/Max）、色/単位は空センチネル、目盛り数は 0 センチネル。
    property real widgetMeterMin: 0
    property real widgetMeterMax: 0
    property bool widgetHasMeterMin: false
    property bool widgetHasMeterMax: false
    property string widgetArcColor: ""
    property string widgetNeedleColor: ""
    property int widgetTickCount: 0
    property string widgetUnit: ""

    // Task 39: アクション / バインディングのメタ。Editor は T40 まで編集 UI を持たないが、
    // **読み込んだ定義を保存で失わない**ため、ここで素通し保持する（delegate が modelData
    // から流し込み、snapshotModel が保存へ書き戻す。Codex PR #78 [P1]）。配列をそのまま持つ。
    property var widgetActions: []
    property var widgetBindings: []

    // Task 27: リサイズ時の最小サイズ。ハンドルドラッグ / 数値編集での縮小は
    // これ未満にならないよう clamp する（潰れて選択・操作不能になるのを防ぐ）。
    property real minWidth: 30
    property real minHeight: 24

    // Task 35: グリッドスナップ。値は Canvas から delegate 経由で流し込む（編集時の補助
    // のみで **JSON には保存しない**）。snapEnabled が true のとき、移動ドラッグ確定 /
    // リサイズ確定の座標・サイズを gridSize の格子へ吸着する。
    property bool snapEnabled: false
    property int gridSize: 8

    // Task 35: 値を格子へ吸着する純関数（snapEnabled が false なら素通し）。移動 / リサイズ
    // 双方の確定ハンドラから使う。tst_canvas で直接呼んで吸着ロジックを回帰固定する。
    function snappedValue(v) {
        return root.snapEnabled ? Math.round(v / root.gridSize) * root.gridSize : v
    }

    // Task 25: 選択状態。値の所有は Canvas（root.selectedWidgetId）にあり、
    // この EditableWidget は「選ばれているか」を受け取って選択枠を描画するだけ
    // （plain な bool プロパティ）。結線は delegate 側（Canvas.qml）で
    // `selected: widgetId === root.selectedWidgetId` とバインドする。
    property bool selected: false

    // Task 25: クリックされて「選択して欲しい」要求を外へ伝えるシグナル。
    // QML の id はコンポーネントファイルを跨いで参照できないため、
    // EditableWidget から Canvas を直接触らず、このシグナル経由で結線する。
    // 引数名は QML 予約語 `id` / 既存プロパティ `widgetId` との衝突を避けて
    // `requestedId` とする。
    // Task 36: modifiers（Shift / Ctrl）も渡し、Canvas 側で複数選択の加除を判断する。
    signal selectRequested(string requestedId, int modifiers)

    MouseArea {
        id: dragArea
        anchors.fill: parent
        drag.target: root
        drag.axis: Drag.XAndYAxis
        // 子（HmiButton 等）の MouseArea にイベントを先に渡しつつ、
        // ドラッグ閾値を超えたら親がイベントを奪う。これがないと
        // 子 Widget の clicked / pressed が常に発火しない。
        drag.filterChildren: true
        // 親（Canvas の widgetLayer）の外に出ないようクランプ
        drag.minimumX: 0
        drag.minimumY: 0
        drag.maximumX: root.parent ? root.parent.width - root.width : 0
        drag.maximumY: root.parent ? root.parent.height - root.height : 0
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        // Task 35: 移動ドラッグ確定時にグリッドへ吸着する。**実ドラッグが起きた時だけ**
        // 吸着するため `onReleased`（純クリックでも発火する）ではなく `drag.onActiveChanged`
        // の active→false 遷移で行う。これで「選択のためにクリックしただけ」では位置が
        // 動かない（Codex PR #74 [Major]：非グリッド値の Widget を誤クリックで書き換える問題）。
        // 丸めで親領域を超えないよう 0..(parent-size) に clamp する。
        // **吸着を先に済ませてから dragFinished() を発火**する：Task 36 の一括移動で
        // Canvas が「リーダーの最終（snapped）座標」を兄弟へ反映できるよう、順序を保証する
        // （Codex PR #75 [P2]：snap 後の差分が兄弟へ反映されずズレる問題）。
        drag.onActiveChanged: {
            if (!dragArea.drag.active) {
                if (root.snapEnabled && root.parent) {
                    const maxX = Math.max(0, root.parent.width - root.width)
                    const maxY = Math.max(0, root.parent.height - root.height)
                    root.x = Math.max(0, Math.min(maxX, root.snappedValue(root.x)))
                    root.y = Math.max(0, Math.min(maxY, root.snappedValue(root.y)))
                }
                root.dragFinished()
            }
        }

        Item {
            id: container
            anchors.fill: parent
        }
    }

    // Task 25: 選択枠。selected 時のみ表示する。
    // dragArea より後に宣言して最前面へ重ね、内容（HmiButton）の上に枠を描く。
    // MouseArea を持たないためマウスイベントは透過し、ドラッグ/クリックを妨げない。
    // 負マージンで Widget をわずかに囲み、ボタン自身の境界線と重ならないようにする。
    Rectangle {
        id: selectionFrame
        anchors.fill: parent
        anchors.margins: -2
        visible: root.selected
        color: "transparent"
        radius: 4
        border.color: "#ff5d8f"
        border.width: 2
    }

    // Task 27: 右下リサイズハンドル。selected 時のみ表示。
    // 専用 MouseArea で root.width / height を直接更新する（x/y を drag.target で
    // 動かす移動ドラッグと同じく、binding を切って live 値を持つ運用。保存は
    // snapshotModel が live 値を読む）。
    //   - preventStealing: true ：親 dragArea（drag.filterChildren）にこの press を
    //     奪われると Widget 移動になってしまうため明示的に握り続ける。ハンドルは
    //     dragArea の子ではないので本来は奪われないが、安全側で固定する。
    //   - 座標は mapToItem(root.parent, ...) で widgetLayer 基準に変換して扱う。
    //     ハンドルは resize に伴って動くため、ハンドル相対座標だと値が暴れる。
    //     親基準にすれば press 時点との差分が安定して pointer 移動量になる。
    Rectangle {
        id: resizeHandle
        objectName: "resizeHandle"
        visible: root.selected
        width: 14
        height: 14
        radius: 3
        color: "#ff5d8f"
        border.color: "white"
        border.width: 1
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -7
        anchors.bottomMargin: -7

        MouseArea {
            id: resizeArea
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.SizeFDiagCursor

            property real pressSceneX: 0
            property real pressSceneY: 0
            property real pressW: 0
            property real pressH: 0
            // Task 35: 実際にリサイズ移動が起きたか。単なるハンドルのクリックで
            // サイズが書き換わらないよう、吸着は移動があった release に限定する。
            property bool resized: false

            onPressed: function(mouse) {
                const p = mapToItem(root.parent, mouse.x, mouse.y)
                pressSceneX = p.x
                pressSceneY = p.y
                pressW = root.width
                pressH = root.height
                resized = false
                root.resizeStarted()  // Task 38: undo 前状態の保留開始
            }
            onPositionChanged: function(mouse) {
                if (!pressed) {
                    return
                }
                resized = true
                const p = mapToItem(root.parent, mouse.x, mouse.y)
                root.width = Math.max(root.minWidth, pressW + (p.x - pressSceneX))
                root.height = Math.max(root.minHeight, pressH + (p.y - pressSceneY))
            }
            // Task 35: リサイズ確定時にサイズをグリッドへ吸着する（最小サイズは死守）。
            // **実リサイズが起きた時だけ**吸着する（純クリックでは resized=false のまま
            // で、非グリッド値の Widget をクリックしてもサイズが書き換わらない。
            // Codex PR #74 [Major]）。
            onReleased: {
                if (root.snapEnabled && resized) {
                    root.width = Math.max(root.minWidth, root.snappedValue(root.width))
                    root.height = Math.max(root.minHeight, root.snappedValue(root.height))
                }
                resized = false
                root.resizeFinished()  // Task 38: undo 確定（変化なければ捨てられる）
            }
        }
    }
}
