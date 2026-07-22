import QtQuick
import HmiWidgets

// HMI 編集用のキャンバス。
// 白背景 + 枠線を持つ固定サイズの編集領域を表す。
//
// Task 7 で動的化：内部に Repeater + EditableWidget を持ち、widgetModel に
// 流し込まれた配列（{id,type,x,y,width,height,text,tag}）から Widget を生成する。
// 初期値は Task 4/5/6 で利用していた btn001 1 件のみで、起動時の見た目は従来通り。
// JSON 読込時は Main.qml から widgetModel を差し替えればキャンバスが再構築される。
Item {
    id: root

    // キャンバスの論理サイズ（外部からプロパティで指定可能）
    property int canvasWidth: 800
    property int canvasHeight: 600

    // Widget 配置情報。Main.qml の Open 結果や Save 後の再代入で差し替える。
    property var widgetModel: [
        { id: "btn001", type: "Button", x: 100, y: 50, width: 120, height: 40,
          text: "Start", tag: "PLC.START" }
    ]

    // Task 35: グリッドスナップ。snapEnabled でドラッグ / リサイズの確定座標を
    // gridSize の格子へ吸着する（実装は EditableWidget 側）。グリッド線も snapEnabled
    // 時のみ描画する。**編集時の補助のみで JSON には保存しない**（Main.qml のツール
    // バーのトグルが snapEnabled を駆動する）。
    property bool snapEnabled: false
    property int gridSize: 8

    // Task 25 / 36: 選択。**選択の真実は集合 `selectedWidgetIds`（id 配列）** に集約する
    // （Task 36 で単一 id から複数選択へ拡張。Shift / Ctrl クリックで加除）。
    // 各 EditableWidget は delegate 側で `selected: selectedWidgetIds.indexOf(widgetId) >= 0`
    // をバインドし、自身が選ばれているかを受け取る。
    property var selectedWidgetIds: []

    // Task 36: 単一選択時の id（後方互換の便利値。インスペクタの単一編集 / 削除引数
    // 既定に使う）。**集合からの派生 readonly** で、ちょうど 1 個選択のときだけ非空。
    // 複数選択 / 未選択では "" になり、selectedItem も null（単一プロパティ編集は単一選択時のみ）。
    readonly property string selectedWidgetId: selectedWidgetIds.length === 1 ? selectedWidgetIds[0] : ""

    // Task 36: クリック選択。modifiers に Shift / Ctrl が立っていれば集合へ加除（トグル）、
    // 無ければ単一選択に置き換える。delegate の selectRequested から呼ばれる。
    function selectWidget(id, modifiers) {
        if (!id) {
            return
        }
        const additive = (modifiers & (Qt.ShiftModifier | Qt.ControlModifier)) !== 0
        if (additive) {
            const arr = selectedWidgetIds.slice()
            const idx = arr.indexOf(id)
            if (idx >= 0) {
                arr.splice(idx, 1)  // 既に選択中ならトグルで外す
            } else {
                arr.push(id)
            }
            selectedWidgetIds = arr
        } else {
            selectedWidgetIds = [id]
        }
    }


    // 配置されている Widget 群（Task 6 の JSON 保存で走査するため公開）
    property alias widgetItems: widgetLayer.children

    // Task 26: 選択中の live な EditableWidget を解決して公開する。
    // selectedWidgetId と widgetItems(= widgetLayer.children) の **両方** に依存
    // するバインドなので、addWidget() / 読込で widgetModel を再代入して Repeater
    // が delegate を作り直しても（childrenChanged 発火）、同一 id の **新しい live
    // Item** に解決し直される（破棄済みの古い Item を掴み続けない）。Codex PR #52
    // P2 指摘への回答：再生成後の再解決はこの reactive 依存で担保し、tst_canvas.qml
    // の test_selected_item_reresolves_after_add で回帰固定する。選択状態の所有を
    // Canvas に一元化するため、Main.qml のインスペクタはこの canvas.selectedItem を
    // 参照する。
    property var selectedItem: resolveSelectedItem(selectedWidgetId, widgetItems)

    function resolveSelectedItem(selectedId, items) {
        if (!selectedId) {
            return null
        }
        for (let i = 0; i < items.length; ++i) {
            // Repeater 自身など widgetId を持たない子は除外する。
            if (items[i] && items[i].widgetId === selectedId) {
                return items[i]
            }
        }
        return null
    }

    // Task 18: 新規 Widget 追加用の単調増加カウンタ（実用上の最大連番）。
    // 初期 widgetModel に btn001 が含まれているので 1 から始める。Main.qml の
    // Open で widgetModel が差し替わった場合に備え、`addWidget()` は採番前に
    // 必ず現在の widgetModel を走査して max ID と比較し、大きい方の次を採用する
    // （Codex Task 18 P1 指摘）。
    property int widgetIdCounter: 1

    // Task 26: 現在 live な EditableWidget 群から widgetModel 互換の配列を
    // 生成する（= 編集中の真実である live Item を配列へスナップショット）。
    // widgetModel（var 配列）は in-place 変更でバインディング通知が出ないため、
    // 構造変更（追加 / 削除）時はこの関数で **インスペクタ編集やドラッグ位置を
    // 含む現在値** を取り込んでから再代入する。これをせず古い widgetModel を
    // 直接 concat すると、Repeater 再生成で未保存の編集が古い値へ戻る
    // （Codex PR #52 P2 指摘）。Main.qml の保存経路（saveTo / onAccepted）も
    // 同じ走査をしていたため本関数に集約して共用する。
    // Task 8B-A（CodeRabbit PR #132）: JSON 値（配列 / オブジェクト）の deep copy。
    // series のような **入れ子の var** を delegate 受け取り時と snapshot 保存時にコピーして
    // 参照共有を切る（live / undo / clipboard が同一参照を共有すると、8B-D 以降の系列 in-place
    // 編集で undo 差分消失や複製間の意図しない連動が起きる）。series はスカラ文字列のみなので
    // JSON 往復で無損失。undefined は undefined のまま返す（JSON.parse 例外回避）。
    function cloneJsonValue(v) {
        return v === undefined ? undefined : JSON.parse(JSON.stringify(v))
    }

    function snapshotModel() {
        const items = widgetItems
        const result = []
        for (let i = 0; i < items.length; ++i) {
            const item = items[i]
            // Repeater 自身など widgetId を持たない子はスキップ
            if (item.widgetId === undefined) {
                continue
            }
            result.push({
                id: item.widgetId,
                type: item.widgetType,
                x: Math.round(item.x),
                y: Math.round(item.y),
                width: Math.round(item.width),
                height: Math.round(item.height),
                text: item.widgetText,
                tag: item.widgetTag,
                // Task 28: スタイル属性も live Item からスナップショットして保存に乗せる。
                backgroundColor: item.widgetBackgroundColor,
                textColor: item.widgetTextColor,
                fontSize: item.widgetFontSize,
                // Task 31: ボーダー＋角丸も live Item から取り込む（-1 = 未指定）。
                borderColor: item.widgetBorderColor,
                borderWidth: item.widgetBorderWidth,
                radius: item.widgetRadius,
                // Task 33: フォント詳細も live Item から取り込む（bool / 空文字 = 未指定）。
                fontBold: item.widgetFontBold,
                fontItalic: item.widgetFontItalic,
                fontFamily: item.widgetFontFamily,
                // Task 34: 配置 + 不透明度も live Item から取り込む（空 / -1 = 未指定）。
                // JSON キーは `opacity`、live Item 側は `widgetOpacity`（組込み衝突回避）。
                hAlign: item.widgetHAlign,
                vAlign: item.widgetVAlign,
                opacity: item.widgetOpacity,
                // Task 42: 状態別スタイルも live Item から取り込む（JSON キーは enabled /
                // checkable / checked、live Item 側は widgetEnabled 等）。Schema 側で
                // enabled は false のとき・checkable/checked は true のときだけ書き出される。
                enabled: item.widgetEnabled,
                checkable: item.widgetCheckable,
                checked: item.widgetChecked,
                // Task 54: 数値範囲 + presence も live Item から取り込む。Schema 側で
                // hasMinValue / hasMaxValue が true のときだけ minValue / maxValue が書き出される。
                minValue: item.widgetMinValue,
                maxValue: item.widgetMaxValue,
                hasMinValue: item.widgetHasMin,
                hasMaxValue: item.widgetHasMax,
                // Task T-B: Trend 固有も live Item から取り込む。このスナップショットは
                // QVariantMap 経路（C++ の WidgetData::fromVariantMap）へ渡るため、min/max と同じく
                // **明示 bool キー hasYMin/hasYMax を含める**（QML↔C++ ブリッジの presence 表現）。
                // JSON へ書き出す段（WidgetData::toJson）で C++ 側が hasYMin/hasYMax を JSON キーに
                // せず yMin/yMax キーの有無へ畳む（pointCount/sampleMs は >0、lineColor は非空のとき書く）。
                pointCount: item.widgetPointCount,
                yMin: item.widgetYMin,
                yMax: item.widgetYMax,
                hasYMin: item.widgetHasYMin,
                hasYMax: item.widgetHasYMax,
                lineColor: item.widgetLineColor,
                sampleMs: item.widgetSampleMs,
                // Task 8B-A: Trend 拡張（複数系列 + 軸/凡例）も保存スナップショットへ含める
                //（series 付き JSON を Editor で開いて保存しても失わないため。Codex PR #132 [P2]）。
                // series は QVariantList of QVariantMap として WidgetData::fromVariantMap へ渡る。
                // deep copy で live/undo/clipboard の参照共有を切る（CodeRabbit PR #132）。
                series: root.cloneJsonValue(item.widgetSeries),
                showGrid: item.widgetShowGrid,
                showLegend: item.widgetShowLegend,
                yTickCount: item.widgetYTickCount,
                // Task M-A: Meter 固有も保存スナップショットへ含める（Meter JSON を Editor で
                // 開いて保存しても範囲・色・目盛り・単位を失わないため。Codex PR #152 [P2]）。
                // min/max と同じく明示 bool キー hasMeterMin/hasMeterMax を含める（QML↔C++ ブリッジの
                // presence 表現。JSON へ書き出す段で C++ が meterMin/meterMax キーの有無へ畳む）。
                meterMin: item.widgetMeterMin,
                meterMax: item.widgetMeterMax,
                hasMeterMin: item.widgetHasMeterMin,
                hasMeterMax: item.widgetHasMeterMax,
                arcColor: item.widgetArcColor,
                needleColor: item.widgetNeedleColor,
                tickCount: item.widgetTickCount,
                unit: item.widgetUnit,
                // Task W-A: SimpleButton 固有も保存スナップショットへ含める（SimpleButton JSON を
                // Editor で開いて保存しても形状・テーマ・差し色・長押し時間を失わないため。Codex PR #163 [P2]）。
                // shape/theme/accentColor は非空のとき・holdMs は >0 のとき C++ 側で書き出される。
                shape: item.widgetShape,
                theme: item.widgetTheme,
                accentColor: item.widgetAccentColor,
                holdMs: item.widgetHoldMs,
                // Task 39: アクション / バインディングも保存スナップショットへ含める
                //（読み込んだ定義を Editor の保存で失わないため。Codex PR #78 [P1]）。
                // 注：series と違い deep copy しないのは、actions/bindings はインスペクタで
                // **配列を丸ごと置換**して編集する（in-place 変更しない）ため参照共有でも実害が
                // 無いから（CodeRabbit PR #132 で非対称性を確認）。in-place 編集を足す時は series と
                // 同じく cloneJsonValue を挟むこと。
                actions: item.widgetActions,
                bindings: item.widgetBindings
            })
        }
        return result
    }

    // Task 18: 既定サイズ/位置で Widget を 1 個追加する。Main.qml の追加
    // ボタンから呼ばれる。E2E（Spix）からは追加ボタンの mouseClick 経由で
    // 同じパスを通る。
    // Task 18 / 37: 次の btnNNN 形式 id を採番する（addWidget / ペースト / 複製で共用）。
    // 渡された snapshot 内の btnNNN 最大連番と widgetIdCounter を比較して衝突を避ける
    // （読込で外部 JSON が入った後でも安全。ペーストで連続採番する時は、push 済みの新 id も
    // snapshot に含めて渡せば次の採番が重複しない）。
    function nextWidgetId(snapshot) {
        let maxFound = widgetIdCounter
        for (let i = 0; i < snapshot.length; ++i) {
            const existingId = snapshot[i].id
            if (typeof existingId !== "string") {
                continue
            }
            const m = existingId.match(/^btn(\d+)$/)
            if (!m) {
                continue
            }
            const n = parseInt(m[1], 10)
            if (n > maxFound) {
                maxFound = n
            }
        }
        widgetIdCounter = maxFound + 1
        return "btn" + String(widgetIdCounter).padStart(3, "0")
    }

    // Task 48: 既定サイズ/位置で Widget を 1 個追加する。引数 type で種別を選ぶ
    // （省略時は後方互換で "Button"）。Phase 5 横展開でツールバーの「ボタン追加」/
    // 「ラベル追加」が同じ経路を type 違いで呼ぶ。Label は既定文字 "Label"・背景は
    // 未指定（空文字）＝HmiLabel 側で透明にフォールバックする（plan「Label の既定文字・
    // 透明背景」）。Button は従来どおり既定文字 "New"・背景未指定（#4cc9f0 へフォールバック）。
    // Task 48 / 51 / T-C / M-C / W-C: 既知の種別（"Button" / "Label" / "NumericField" /
    // "Trend" / "Meter" / "SimpleButton"）だけを採用し、未知値 / 空 / undefined は "Button" に
    // フォールバックする（ホワイトリスト正規化）。描画フォールバックと保存値が乖離して JSON の
    // 型契約が壊れるのを防ぐ（CodeRabbit PR #98 指摘）。新種別を足す時はここの許可リストに追加する
    //（Task 51 で "NumericField"、T-C で "Trend"、M-C で "Meter"、W-C で "SimpleButton" を追加）。
    // addWidget（ツールバー）/ addPresetWidget（サンプルパレット）が共用する。
    function normalizeWidgetType(type) {
        return (type === "Label" || type === "Button"
                || type === "NumericField" || type === "Trend" || type === "Meter"
                || type === "SimpleButton")
            ? type : "Button"
    }

    // Task W-C / W-D（Phase 11）: サンプルパレットのプリセットから Widget を追加する。preset は
    // `{ type, defaults }`（defaults は width/height/text や種別固有フィールドの初期値マップ）。
    // addWidget（種別だけ・既定サイズ固定）と違い、**プリセットの defaults をそのまま初期値**にする。
    // 位置は引数で決める：
    //   - `dropX`/`dropX` を渡した場合（W-D の D&D）：その **widgetLayer 基準の座標を中心** に置く
    //     （ドロップ地点にウィジェットが乗る。キャンバス内へ clamp）。
    //   - 省略した場合（W-C のクリック追加）：従来どおり **キャンバス中央** へ置く。
    // どちらも追加した Widget を選択する。構造変更なので addWidget と同じく
    // pushUndo → snapshot → 再代入の経路に乗せる。
    function addPresetWidget(preset, dropX, dropY) {
        if (!preset || !preset.type) {
            return
        }
        pushUndo()
        const snapshot = snapshotModel()
        const id = nextWidgetId(snapshot)
        const d = preset.defaults || {}
        const newWidget = { id: id, type: normalizeWidgetType(preset.type), tag: "" }
        // defaults を素通しでコピー（未知キーは WidgetData.fromVariantMap が無視するので無害）。
        for (const k in d) {
            newWidget[k] = d[k]
        }
        // サイズ既定（未指定なら 120×40）。配置計算に使う。
        const w = newWidget.width !== undefined ? newWidget.width : 120
        const h = newWidget.height !== undefined ? newWidget.height : 40
        newWidget.width = w
        newWidget.height = h
        if (dropX !== undefined && dropY !== undefined) {
            // W-D: ドロップ座標を中心にウィジェットを置き、キャンバス内へ clamp する。
            newWidget.x = Math.round(Math.max(0, Math.min(canvasWidth - w, dropX - w / 2)))
            newWidget.y = Math.round(Math.max(0, Math.min(canvasHeight - h, dropY - h / 2)))
        } else {
            // W-C: キャンバス中央。
            newWidget.x = Math.round((canvasWidth - w) / 2)
            newWidget.y = Math.round((canvasHeight - h) / 2)
        }
        snapshot.push(newWidget)
        widgetModel = snapshot
        // 追加した Widget を選択（インスペクタで即編集でき、手触りが分かりやすい）。
        selectedWidgetIds = [id]
    }

    function addWidget(type) {
        // Task 26: 古い widgetModel を直接 concat せず、現在の live Item 群を
        // スナップショットしてから追加する。これによりインスペクタでの未保存
        // 編集（text/tag）やドラッグ後の位置が、追加に伴う Repeater 再生成で
        // 巻き戻らない（Codex PR #52 指摘）。
        pushUndo()  // Task 38: 追加の直前状態を undo へ
        const snapshot = snapshotModel()
        const id = nextWidgetId(snapshot)
        const widgetType = normalizeWidgetType(type)
        // Task T-C: Trend はグラフらしく大きめの既定サイズ（240×120 = HmiTrend の既定実寸）。
        // Task M-C: Meter はスピードメーターらしく正方形の既定サイズ（200×200 = HmiMeter の既定実寸）。
        // 他種別は従来どおり 120×40。
        const isTrend = widgetType === "Trend"
        const isMeter = widgetType === "Meter"
        const newWidget = {
            id: id,
            type: widgetType,
            x: 50, y: 200,
            width: isTrend ? 240 : isMeter ? 200 : 120,
            height: isTrend ? 120 : isMeter ? 200 : 40,
            // Label は既定文字 "Label"・透明背景（背景は未指定のままで HmiLabel が
            // transparent にフォールバック）。NumericField は数値慣習で初期値 "0"。
            // Trend / Meter は文字を持たないので "" 固定。Button は従来どおり "New"。
            text: widgetType === "Label" ? "Label"
                : widgetType === "NumericField" ? "0"
                : (isTrend || isMeter) ? "" : "New", tag: ""
        }
        snapshot.push(newWidget)
        // 新しい配列を代入することで Repeater に確実にモデル変更を通知する。
        widgetModel = snapshot
    }

    // Task 37: コピー / ペースト / 複製。選択 Widget を内部クリップボード（WidgetData
    // 相当の配列スナップショット）へコピーし、ペーストで新 id を採番してオフセット配置する。
    property var clipboard: []
    // ペースト位置のオフセット（px）。
    readonly property int pasteOffset: 20

    // Task 37: 選択中 Widget を内部クリップボードへコピー（live 値をスナップショット）。
    function copySelected() {
        const snap = snapshotModel()
        clipboard = snap.filter(function(w) {
            return selectedWidgetIds.indexOf(w.id) >= 0
        })
    }

    // Task 37: 与えられた WidgetData 相当配列を、新 id + オフセットで複製配置する共通経路
    // （ペースト / 複製が共用）。構造変更なので snapshot→追加→再代入し、追加した新 id を選択する。
    function pasteEntries(entries) {
        if (!entries || entries.length === 0) {
            return
        }
        pushUndo()  // Task 38: ペースト / 複製の直前状態を undo へ
        const snapshot = snapshotModel()
        const newIds = []
        const maxX = Math.max(0, width)
        const maxY = Math.max(0, height)
        for (let i = 0; i < entries.length; ++i) {
            const src = entries[i]
            const copy = {}
            for (const key in src) {
                copy[key] = src[key]
            }
            // Task 8B-A（CodeRabbit PR #132）: 上のシャローコピーでは入れ子の series 配列が
            // クリップボード元エントリと同一参照のままになる。deep copy で切り、ペースト後の
            // 系列 in-place 編集（8B-D 以降）が元エントリへ波及しないようにする。actions/bindings は
            // 現状インスペクタで配列丸ごと置換のみ＝参照共有でも実害が無いため既存パターン据え置き。
            if (copy.series !== undefined && copy.series !== null) {
                copy.series = cloneJsonValue(copy.series)
            }
            // push 済みの新 id も含む snapshot を渡すので連続採番でも重複しない。
            copy.id = nextWidgetId(snapshot)
            const w = (src.width !== undefined ? src.width : 120)
            const h = (src.height !== undefined ? src.height : 40)
            copy.x = Math.max(0, Math.min(maxX - w, (src.x !== undefined ? src.x : 0) + pasteOffset))
            copy.y = Math.max(0, Math.min(maxY - h, (src.y !== undefined ? src.y : 0) + pasteOffset))
            snapshot.push(copy)
            newIds.push(copy.id)
        }
        widgetModel = snapshot
        // ペースト後は新規 Widget を選択状態にする（onWidgetModelChanged の prune より後に代入）。
        selectedWidgetIds = newIds
    }

    // Task 37: クリップボードからペースト。
    function pasteClipboard() {
        pasteEntries(clipboard)
    }

    // Task 40（Codex PR #80 [P2]）：変数名を変更したとき、既存 Widget の
    // actions[].target / bindings[].variable の旧名参照を新名へ置換する（変数は名前で
    // 解決されるため、旧名のままだと T41 の実行 / 追従が参照切れになる）。構造変更と同じく
    // live Item をスナップショット → 置換 → 再代入する。変更があった時だけ再代入する。
    function renameVariableReferences(oldName, newName) {
        if (!oldName || oldName === newName) {
            return
        }
        const snap = snapshotModel()
        let changed = false
        for (let i = 0; i < snap.length; ++i) {
            const w = snap[i]
            if (w.actions) {
                for (let a = 0; a < w.actions.length; ++a) {
                    if (w.actions[a].target === oldName) {
                        w.actions[a].target = newName
                        changed = true
                    }
                }
            }
            if (w.bindings) {
                for (let b = 0; b < w.bindings.length; ++b) {
                    if (w.bindings[b].variable === oldName) {
                        w.bindings[b].variable = newName
                        changed = true
                    }
                }
            }
            // Task 8B-A（Codex PR #132）: Trend の系列もサンプル源変数を参照する
            //（series[].variable）ため、リネームに追従する。漏らすと series 付き Trend を含む
            // プロジェクトで変数を改名したとき系列だけ旧名のまま保存され dangling 参照になる。
            if (w.series) {
                for (let s = 0; s < w.series.length; ++s) {
                    if (w.series[s].variable === oldName) {
                        w.series[s].variable = newName
                        changed = true
                    }
                }
            }
        }
        if (changed) {
            widgetModel = snap
        }
    }

    // Task 40（Codex PR #80 [P2]）：変数定義を削除する時は、その変数を参照している
    // 既存 Widget の actions（target === name）/ bindings（variable === name）も取り除く。
    // 残すと JSON に未定義変数への dangling 参照が残り、T41 の実行で参照切れになる。
    // renameVariableReferences と同じく live Item をスナップショット → 置換 → 再代入する。
    // undo には載せない（変数削除自体が Canvas undo 外なので、参照クリーンアップも同じ境界）。
    function removeVariableReferences(name) {
        if (!name) {
            return
        }
        const snap = snapshotModel()
        let changed = false
        for (let i = 0; i < snap.length; ++i) {
            const w = snap[i]
            if (w.actions) {
                const keptA = w.actions.filter(function(a) { return a.target !== name })
                if (keptA.length !== w.actions.length) {
                    w.actions = keptA
                    changed = true
                }
            }
            if (w.bindings) {
                const keptB = w.bindings.filter(function(b) { return b.variable !== name })
                if (keptB.length !== w.bindings.length) {
                    w.bindings = keptB
                    changed = true
                }
            }
            // Task 8B-A（Codex PR #132）: Trend の系列も削除変数を参照する（series[].variable）
            // ため、その変数を指す系列を取り除く（actions/bindings と同じ流儀。残すと dangling 参照）。
            if (w.series) {
                const keptS = w.series.filter(function(s) { return s.variable !== name })
                if (keptS.length !== w.series.length) {
                    w.series = keptS
                    changed = true
                }
            }
        }
        if (changed) {
            widgetModel = snap
        }
    }

    // Task 37: 選択中 Widget を即複製（クリップボードを汚さず現在の選択から直接ペースト）。
    function duplicateSelected() {
        const snap = snapshotModel()
        const sel = snap.filter(function(w) {
            return selectedWidgetIds.indexOf(w.id) >= 0
        })
        pasteEntries(sel)
    }

    // Task 38: undo / redo（状態スナップショット方式・QML 完結）。1 操作 = 1 スナップショット
    // を undoStack / redoStack（snapshotModel() の配列）で積む。構造変更（追加/削除/ペースト/
    // 整列/分布）は **操作前に pushUndo()** で前状態を積む。連続操作（ドラッグ/リサイズ/
    // インスペクタ編集）は beginEdit()（開始時に前状態を保留）→ commitEdit()（確定時、状態が
    // 変わっていれば積む）で「中間フレームを積まず確定時のみ 1 件」にする。
    property var undoStack: []
    property var redoStack: []
    property var _pendingUndo: null
    property bool _editing: false

    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0

    // 構造変更の直前に現在状態を undo へ積む（redo はクリア）。配列は再代入して
    // バインディング（canUndo/canRedo）に通知する（push では通知されない）。
    function pushUndo() {
        undoStack = undoStack.concat([snapshotModel()])
        redoStack = []
    }

    // 連続編集の開始：前状態を保留（多重 begin はガード）。
    function beginEdit() {
        if (_editing) {
            return
        }
        _pendingUndo = snapshotModel()
        _editing = true
    }

    // 連続編集の確定：状態が実際に変わっていれば保留前状態を undo へ積む（no-op は捨てる）。
    function commitEdit() {
        if (!_editing) {
            return
        }
        _editing = false
        const before = _pendingUndo
        _pendingUndo = null
        if (before === null) {
            return
        }
        if (JSON.stringify(snapshotModel()) !== JSON.stringify(before)) {
            undoStack = undoStack.concat([before])
            redoStack = []
        }
    }

    function cancelEdit() {
        _editing = false
        _pendingUndo = null
    }

    function undo() {
        if (undoStack.length === 0) {
            return
        }
        const prev = undoStack[undoStack.length - 1]
        undoStack = undoStack.slice(0, undoStack.length - 1)
        redoStack = redoStack.concat([snapshotModel()])
        selectedWidgetIds = []  // 復元で消える Item の stale 選択を避ける
        // Task 46 で発覚：同数の配列を再代入しても Repeater が既存 delegate を再利用
        // することがあり、インスペクタの命令的書き込みでバインディングが切れた
        // プロパティ（色等）に復元値が届かない（live Item が新値のまま残る）。
        // 一度空配列を挟んで delegate を確実に全破棄 → 復元状態から再生成する。
        widgetModel = []
        widgetModel = prev
    }

    function redo() {
        if (redoStack.length === 0) {
            return
        }
        const next = redoStack[redoStack.length - 1]
        redoStack = redoStack.slice(0, redoStack.length - 1)
        undoStack = undoStack.concat([snapshotModel()])
        selectedWidgetIds = []
        // undo() と同じ理由で delegate を確実に全破棄してから復元する。
        widgetModel = []
        widgetModel = next
    }

    // プロジェクト読込時など、履歴を破棄する。
    function clearHistory() {
        undoStack = []
        redoStack = []
        cancelEdit()
    }

    // Task 29: 選択中（または指定 id）の Widget を削除する。addWidget() と対称で、
    // 構造変更（削除）なので live Item 群をスナップショット → 該当 id を除いた配列を
    // 再代入して Repeater をリトリガする（var 配列据え置き＝Phase 4 設計指針）。
    // これにより未保存の他 widget の編集（text/座標/スタイル）が巻き戻らない。
    // 引数省略時は現在の選択 id を対象にする。Task 36 で複数削除 deleteWidgets() に委譲。
    function deleteWidget(targetId) {
        const id = (targetId !== undefined && targetId !== "")
            ? targetId : selectedWidgetId
        if (!id) {
            return
        }
        deleteWidgets([id])
    }

    // Task 36: 複数 Widget を一括削除する（Delete キー / 削除ボタンの呼び先）。
    // deleteWidget(id) と同じく snapshot → 除外 → 再代入。削除した id を選択集合からも
    // 外す（破棄済み Item を掴まないよう先に外してから model 再代入）。
    function deleteWidgets(ids) {
        if (!ids || ids.length === 0) {
            return
        }
        pushUndo()  // Task 38: 削除の直前状態を undo へ
        const snapshot = snapshotModel()
        const next = []
        for (let i = 0; i < snapshot.length; ++i) {
            if (ids.indexOf(snapshot[i].id) < 0) {
                next.push(snapshot[i])
            }
        }
        selectedWidgetIds = selectedWidgetIds.filter(function(sid) {
            return ids.indexOf(sid) < 0
        })
        widgetModel = next
    }

    // Task 36: 現在 live な選択 Item（複数可）を配列で返す（整列 / 分布 / 一括移動が使う）。
    function selectedItemsList() {
        const items = widgetItems
        const result = []
        for (let i = 0; i < items.length; ++i) {
            const it = items[i]
            if (it && it.widgetId !== undefined && selectedWidgetIds.indexOf(it.widgetId) >= 0) {
                result.push(it)
            }
        }
        return result
    }

    // Task 36: 一括整列。選択 Item 群のバウンディングボックスを基準に左 / 水平中央 / 右 /
    // 上 / 垂直中央 / 下へ揃える（2 個以上で有効）。live Item の x/y を直接更新し、保存は
    // snapshotModel が live 値を読む（座標編集と同じ運用）。
    function alignSelected(mode) {
        const items = selectedItemsList()
        if (items.length < 2) {
            return
        }
        pushUndo()  // Task 38: 整列の直前状態を undo へ
        let minX = Infinity, maxR = -Infinity, minY = Infinity, maxB = -Infinity
        for (let i = 0; i < items.length; ++i) {
            const it = items[i]
            minX = Math.min(minX, it.x)
            maxR = Math.max(maxR, it.x + it.width)
            minY = Math.min(minY, it.y)
            maxB = Math.max(maxB, it.y + it.height)
        }
        const cx = (minX + maxR) / 2
        const cy = (minY + maxB) / 2
        for (let i = 0; i < items.length; ++i) {
            const it = items[i]
            switch (mode) {
            case "left":    it.x = minX; break
            case "hcenter": it.x = cx - it.width / 2; break
            case "right":   it.x = maxR - it.width; break
            case "top":     it.y = minY; break
            case "vcenter": it.y = cy - it.height / 2; break
            case "bottom":  it.y = maxB - it.height; break
            }
        }
    }

    // Task 36: 等間隔分布。両端の Widget は固定し、間の Widget を左端（/上端）基準で
    // 等間隔に並べる（3 個以上で有効）。
    function distributeSelected(axis) {
        const items = selectedItemsList()
        if (items.length < 3) {
            return
        }
        pushUndo()  // Task 38: 分布の直前状態を undo へ
        if (axis === "h") {
            items.sort(function(a, b) { return a.x - b.x })
            const left = items[0].x
            const right = items[items.length - 1].x
            const step = (right - left) / (items.length - 1)
            for (let i = 1; i < items.length - 1; ++i) {
                items[i].x = left + step * i
            }
        } else {
            items.sort(function(a, b) { return a.y - b.y })
            const top = items[0].y
            const bottom = items[items.length - 1].y
            const step = (bottom - top) / (items.length - 1)
            for (let i = 1; i < items.length - 1; ++i) {
                items[i].y = top + step * i
            }
        }
    }

    // Task 36: 複数選択時の一括ドラッグ移動。ドラッグ中の「リーダー」Widget の移動量
    // （drag 開始位置からの差分）を、他の選択 Widget へ同じだけ適用する。リーダー自身は
    // drag.target が動かすのでここでは触らない。EditableWidget の dragging / x / y 変化を
    // delegate の Connections が購読して beginBatchDrag / updateBatchDrag を呼ぶ。
    property string _dragLeaderId: ""
    property var _batchStart: ({})

    function beginBatchDrag(leaderId) {
        // 単一選択 or リーダーが選択外なら一括移動しない。
        if (selectedWidgetIds.length <= 1 || selectedWidgetIds.indexOf(leaderId) < 0) {
            _dragLeaderId = ""
            return
        }
        _dragLeaderId = leaderId
        const start = {}
        const items = selectedItemsList()
        for (let i = 0; i < items.length; ++i) {
            start[items[i].widgetId] = { x: items[i].x, y: items[i].y }
        }
        _batchStart = start
    }

    function updateBatchDrag(leaderId) {
        if (_dragLeaderId !== leaderId || !_batchStart[leaderId]) {
            return
        }
        const leader = resolveSelectedItem(leaderId, widgetItems)
        if (!leader) {
            return
        }
        const dx = leader.x - _batchStart[leaderId].x
        const dy = leader.y - _batchStart[leaderId].y
        const maxX = Math.max(0, width)
        const maxY = Math.max(0, height)
        for (let sid in _batchStart) {
            if (sid === leaderId) {
                continue
            }
            const it = resolveSelectedItem(sid, widgetItems)
            if (!it) {
                continue
            }
            it.x = Math.max(0, Math.min(maxX - it.width, _batchStart[sid].x + dx))
            it.y = Math.max(0, Math.min(maxY - it.height, _batchStart[sid].y + dy))
        }
    }

    // Task 36: ドラッグ確定時の最終反映。リーダーは EditableWidget 側で吸着済みなので、
    // その snapped 差分を兄弟へもう一度適用してから _dragLeaderId をクリアする。これが
    // ないと snap ON のとき兄弟だけ非グリッド位置に残る（Codex PR #75 [P2]）。
    function endBatchDrag(leaderId) {
        if (_dragLeaderId !== leaderId) {
            return
        }
        updateBatchDrag(leaderId)
        _dragLeaderId = ""
    }

    // Task 36（Codex PR #75 [P2]）：widgetModel 差し替え（プロジェクト読込など）で、
    // 新モデルに存在しない選択 id を選択集合から外す。これをしないと、読込後に直前の
    // 選択 id が残り「selectedItem は null なのに未選択案内も単一フォームも出ない空の
    // インスペクタ」や「実在しない id を含む N 個選択中」になる。モデルにある id だけへ
    // 絞り込む（件数が変わる時だけ再代入してバインディング無限ループを避ける）。
    onWidgetModelChanged: {
        if (selectedWidgetIds.length === 0) {
            return
        }
        const present = {}
        for (let i = 0; i < widgetModel.length; ++i) {
            const w = widgetModel[i]
            if (w && w.id !== undefined) {
                present[w.id] = true
            }
        }
        const filtered = selectedWidgetIds.filter(function(id) { return present[id] === true })
        if (filtered.length !== selectedWidgetIds.length) {
            selectedWidgetIds = filtered
        }
    }

    implicitWidth: canvasWidth
    implicitHeight: canvasHeight
    width: canvasWidth
    height: canvasHeight

    Rectangle {
        id: background
        anchors.fill: parent
        color: "white"
        border.color: "#888888"
        border.width: 1

        // Task 25: 背景クリックで選択解除。widgetLayer より前に宣言することで
        // 後続の widgetLayer（Widget 群）が上に重なり、Widget 上のクリックは
        // 各 HmiButton の MouseArea が消費する。空きキャンバスへのクリックだけが
        // ここまで落ちてきて選択を解除する。
        MouseArea {
            id: backgroundClickArea
            anchors.fill: parent
            onClicked: root.selectedWidgetIds = []
        }

        // Task 35: グリッド線。snapEnabled 時のみ描画する。MouseArea を持たないので
        // クリックは下の backgroundClickArea / 上の widgetLayer がそのまま処理する
        //（グリッドは見た目だけの補助レイヤ）。widgetLayer より前に宣言し Widget の背面に置く。
        Item {
            id: gridLayer
            objectName: "gridLayer"
            anchors.fill: parent
            visible: root.snapEnabled
            // 縦線（x = 0, grid, 2*grid, ...）
            Repeater {
                model: root.snapEnabled ? Math.floor(root.width / root.gridSize) + 1 : 0
                delegate: Rectangle {
                    required property int index
                    x: index * root.gridSize
                    y: 0
                    width: 1
                    height: gridLayer.height
                    color: "#e0e0e0"
                }
            }
            // 横線（y = 0, grid, 2*grid, ...）
            Repeater {
                model: root.snapEnabled ? Math.floor(root.height / root.gridSize) + 1 : 0
                delegate: Rectangle {
                    required property int index
                    x: 0
                    y: index * root.gridSize
                    width: gridLayer.width
                    height: 1
                    color: "#e0e0e0"
                }
            }
        }

        Item {
            id: widgetLayer
            anchors.fill: parent

            Repeater {
                model: root.widgetModel
                delegate: EditableWidget {
                    id: wrapper
                    required property var modelData
                    widgetId: modelData.id !== undefined ? modelData.id : ""
                    widgetType: modelData.type !== undefined ? modelData.type : "Button"
                    // Task 35: グリッドスナップ設定を Canvas から各 Widget へ流す
                    //（吸着は EditableWidget の移動 / リサイズ確定ハンドラで行う）。
                    snapEnabled: root.snapEnabled
                    gridSize: root.gridSize
                    widgetText: modelData.text !== undefined ? modelData.text : ""
                    widgetTag: modelData.tag !== undefined ? modelData.tag : ""
                    // Task 28: スタイル属性を modelData → wrapper メタへ流す（未指定は空 / 0）。
                    widgetBackgroundColor: modelData.backgroundColor !== undefined ? modelData.backgroundColor : ""
                    widgetTextColor: modelData.textColor !== undefined ? modelData.textColor : ""
                    widgetFontSize: modelData.fontSize !== undefined ? modelData.fontSize : 0
                    // Task 31: ボーダー＋角丸も流す（未指定は空 / -1。0 は正当値なので -1 を既定にする）。
                    widgetBorderColor: modelData.borderColor !== undefined ? modelData.borderColor : ""
                    widgetBorderWidth: modelData.borderWidth !== undefined ? modelData.borderWidth : -1
                    widgetRadius: modelData.radius !== undefined ? modelData.radius : -1
                    // Task 33: フォント詳細を流す（未指定は false / 空文字）。
                    widgetFontBold: modelData.fontBold !== undefined ? modelData.fontBold : false
                    widgetFontItalic: modelData.fontItalic !== undefined ? modelData.fontItalic : false
                    widgetFontFamily: modelData.fontFamily !== undefined ? modelData.fontFamily : ""
                    // Task 34: 配置 + 不透明度を流す（未指定は空 / -1）。JSON キー opacity →
                    // メタは widgetOpacity（組込み Item.opacity 衝突回避でリネーム）。
                    widgetHAlign: modelData.hAlign !== undefined ? modelData.hAlign : ""
                    widgetVAlign: modelData.vAlign !== undefined ? modelData.vAlign : ""
                    widgetOpacity: modelData.opacity !== undefined ? modelData.opacity : -1
                    // Task 42: 状態別スタイルを流す（未指定は enabled=true / checkable=false /
                    // checked=false）。JSON キー enabled → メタ widgetEnabled（組込み衝突回避）。
                    widgetEnabled: modelData.enabled !== undefined ? modelData.enabled : true
                    widgetCheckable: modelData.checkable !== undefined ? modelData.checkable : false
                    widgetChecked: modelData.checked !== undefined ? modelData.checked : false
                    // Task 54: 数値範囲 + presence を流す（presence は未指定時 false）。
                    widgetMinValue: modelData.minValue !== undefined ? modelData.minValue : 0
                    widgetMaxValue: modelData.maxValue !== undefined ? modelData.maxValue : 0
                    widgetHasMin: modelData.hasMinValue !== undefined ? modelData.hasMinValue : false
                    widgetHasMax: modelData.hasMaxValue !== undefined ? modelData.hasMaxValue : false
                    // Task T-B: Trend 固有フィールドを流す（未指定は 0 / 空 / presence false）。
                    widgetPointCount: modelData.pointCount !== undefined ? modelData.pointCount : 0
                    widgetYMin: modelData.yMin !== undefined ? modelData.yMin : 0
                    widgetYMax: modelData.yMax !== undefined ? modelData.yMax : 0
                    widgetHasYMin: modelData.hasYMin !== undefined ? modelData.hasYMin : false
                    widgetHasYMax: modelData.hasYMax !== undefined ? modelData.hasYMax : false
                    widgetLineColor: modelData.lineColor !== undefined ? modelData.lineColor : ""
                    widgetSampleMs: modelData.sampleMs !== undefined ? modelData.sampleMs : 0
                    // Task 8B-A: Trend 拡張（複数系列 + 軸/凡例）を素通し保持（描画 / 編集 UI は
                    // 8B-B〜8B-D だが、series 付き JSON を開いて保存しても失わないため）。
                    widgetSeries: root.cloneJsonValue(modelData.series !== undefined && modelData.series !== null ? modelData.series : [])
                    widgetShowGrid: modelData.showGrid !== undefined ? modelData.showGrid : false
                    widgetShowLegend: modelData.showLegend !== undefined ? modelData.showLegend : false
                    widgetYTickCount: modelData.yTickCount !== undefined ? modelData.yTickCount : 0
                    // Task M-A: Meter 固有フィールドを素通し保持（描画 / 追加 UI / インスペクタは
                    // M-B〜M-C だが、Meter JSON を開いて保存しても失わないため。Codex PR #152 [P2]）。
                    widgetMeterMin: modelData.meterMin !== undefined ? modelData.meterMin : 0
                    widgetMeterMax: modelData.meterMax !== undefined ? modelData.meterMax : 0
                    widgetHasMeterMin: modelData.hasMeterMin !== undefined ? modelData.hasMeterMin : false
                    widgetHasMeterMax: modelData.hasMeterMax !== undefined ? modelData.hasMeterMax : false
                    widgetArcColor: modelData.arcColor !== undefined ? modelData.arcColor : ""
                    widgetNeedleColor: modelData.needleColor !== undefined ? modelData.needleColor : ""
                    widgetTickCount: modelData.tickCount !== undefined ? modelData.tickCount : 0
                    widgetUnit: modelData.unit !== undefined ? modelData.unit : ""
                    // Task W-A: SimpleButton 固有フィールドを素通し保持（描画 / delegate / パレットは
                    // W-B〜だが、SimpleButton JSON を開いて保存しても失わないため。Codex PR #163 [P2]）。
                    widgetShape: modelData.shape !== undefined ? modelData.shape : ""
                    widgetTheme: modelData.theme !== undefined ? modelData.theme : ""
                    widgetAccentColor: modelData.accentColor !== undefined ? modelData.accentColor : ""
                    widgetHoldMs: modelData.holdMs !== undefined ? modelData.holdMs : 0
                    // Task 39: アクション / バインディングを素通し保持（保存で失わないため）。
                    widgetActions: modelData.actions !== undefined ? modelData.actions : []
                    widgetBindings: modelData.bindings !== undefined ? modelData.bindings : []
                    // Task 18: Spix から `widget_<id>` で参照できるようにする。
                    objectName: "widget_" + widgetId
                    x: modelData.x !== undefined ? modelData.x : 0
                    y: modelData.y !== undefined ? modelData.y : 0
                    width: modelData.width !== undefined ? modelData.width : 120
                    height: modelData.height !== undefined ? modelData.height : 40

                    // Task 25 / 36: 選択状態の結線。EditableWidget からは Canvas の id
                    // （root）が見えないため、可視な delegate 側で結ぶ：
                    //  - 自分が選択集合に含まれるかを受け取る
                    //  - クリック（modifiers 付き）されたら selectWidget で加除 / 置換
                    selected: root.selectedWidgetIds.indexOf(wrapper.widgetId) >= 0
                    onSelectRequested: function(requestedId, modifiers) {
                        root.selectWidget(requestedId, modifiers)
                    }

                    // Task 36: 一括ドラッグ移動の購読。リーダー（このドラッグ中 Widget）の
                    // 移動を Canvas が他の選択 Widget へ伝播する。siblings の x/y 変化は
                    // dragging=false なのでガードで無視され、フィードバックループにならない。
                    Connections {
                        target: wrapper
                        function onDraggingChanged() {
                            if (wrapper.dragging) {
                                root.beginEdit()  // Task 38: ドラッグ前状態を保留
                                root.beginBatchDrag(wrapper.widgetId)
                            }
                        }
                        function onXChanged() {
                            if (wrapper.dragging) {
                                root.updateBatchDrag(wrapper.widgetId)
                            }
                        }
                        function onYChanged() {
                            if (wrapper.dragging) {
                                root.updateBatchDrag(wrapper.widgetId)
                            }
                        }
                        // Task 36: ドラッグ確定（リーダー吸着後）に兄弟へ最終差分を反映。
                        // Task 38: 確定時に undo を 1 件積む（移動が無ければ commitEdit が no-op 判定で捨てる）。
                        function onDragFinished() {
                            root.endBatchDrag(wrapper.widgetId)
                            root.commitEdit()
                        }
                        // Task 38: リサイズの開始 / 確定を undo の操作境界にする。
                        function onResizeStarted() {
                            root.beginEdit()
                        }
                        function onResizeFinished() {
                            root.commitEdit()
                        }
                    }

                    // Task 47: 型分岐の足場（Phase 5 横展開の核）。delegate は widgetType に
                    // 応じて HmiButton / HmiLabel を描き分ける。機構は Loader + inline Component
                    // の 2 分岐で最小化する（3 種別以上になったら DelegateChooser 等へ昇格する
                    // 余地を残すが、本タスクでは hypothetical future を作り込まない）。
                    // 各 Component の中身は従来どおり外側スコープの wrapper(id) 経由でメタへ
                    // バインドし、clicked を選択要求へ中継する（HmiButton をインライン結線して
                    // いた従来パターンと同形）。Loader の loaded item は anchors.fill: parent で
                    // Loader（= container 全面）に追従する。
                    // Task 50: Phase 6 で 3 分岐目（NumericField）を追加。Label に続く
                    // 入力 Widget。Editor キャンバスは設計面なので editable:false で読取専用表示。
                    Loader {
                        anchors.fill: parent
                        sourceComponent: wrapper.widgetType === "Label" ? labelComponent
                                       : wrapper.widgetType === "NumericField" ? numericComponent
                                       : wrapper.widgetType === "Trend" ? trendComponent
                                       : wrapper.widgetType === "Meter" ? meterComponent
                                       : wrapper.widgetType === "SimpleButton" ? simpleButtonComponent
                                                                        : buttonComponent
                    }

                    Component {
                        id: buttonComponent
                        HmiButton {
                            // Task 47: E2E / unit から型分岐を観察できるよう objectName を付与
                            //（Simulator 側と同名。HmiLabel は新規 "hmiLabel"）。
                            objectName: "hmiButton"
                            anchors.fill: parent
                            // EditableWidget の content alias は内部 container を指すため、
                            // parent 経由ではなく wrapper の id 経由でメタを参照する
                            // （CLAUDE.md の "default property alias の parent 罠" 参照）。
                            text: wrapper.widgetText
                            tag: wrapper.widgetTag
                            // Task 28: スタイル属性を HmiButton（唯一の真実）へ渡す。
                            // 空 / 0 は HmiButton 側で既定外観にフォールバックされる。
                            backgroundColor: wrapper.widgetBackgroundColor
                            textColor: wrapper.widgetTextColor
                            fontSize: wrapper.widgetFontSize
                            // Task 31: ボーダー＋角丸を渡す。角丸は widgetRadius → cornerRadius に
                            // マップする（HmiButton の公開入力名は radius 衝突回避で cornerRadius）。
                            // 空 / -1 は HmiButton 側で既定外観にフォールバックされる。
                            borderColor: wrapper.widgetBorderColor
                            borderWidth: wrapper.widgetBorderWidth
                            cornerRadius: wrapper.widgetRadius
                            // Task 33: フォント詳細を HmiButton へ渡す（空 / false は既定にフォールバック）。
                            fontBold: wrapper.widgetFontBold
                            fontItalic: wrapper.widgetFontItalic
                            fontFamily: wrapper.widgetFontFamily
                            // Task 34: 配置 + 不透明度を HmiButton へ渡す。不透明度は widgetOpacity
                            // → HmiButton.widgetOpacity（両者とも組込み opacity 衝突回避でリネーム）。
                            // 空 / -1 は HmiButton 側で既定（中央寄せ・不透明度 1.0）にフォールバック。
                            hAlign: wrapper.widgetHAlign
                            vAlign: wrapper.widgetVAlign
                            widgetOpacity: wrapper.widgetOpacity
                            // Task 42: 状態別スタイルを HmiButton へ渡す。enabled → widgetEnabled
                            // （組込み衝突回避）。Editor では淡色プレビューになるだけで、選択用の
                            // clicked は MouseArea を止めないため disabled でも選択・編集できる。
                            widgetEnabled: wrapper.widgetEnabled
                            checkable: wrapper.widgetCheckable
                            checked: wrapper.widgetChecked
                            // Task 25: ドラッグ用の親 MouseArea は drag.filterChildren 下で
                            // クリックを発火しない（子が消費する）。よってクリック検出は
                            // HmiButton 側の clicked を中継して選択要求に使う。
                            // Task 36: modifiers（Shift / Ctrl）を渡して複数選択の加除を可能にする。
                            onClicked: function(modifiers) {
                                wrapper.selectRequested(wrapper.widgetId, modifiers)
                            }
                        }
                    }

                    Component {
                        id: labelComponent
                        HmiLabel {
                            // Task 47: 型分岐の観察用 objectName（HmiButton と対）。
                            objectName: "hmiLabel"
                            anchors.fill: parent
                            // Label は表示専用。HmiButton と同じく wrapper 経由でメタへバインド
                            // するが、ボーダー / 角丸 / トグル状態 / アクションは持たない
                            // （Label が使わないメタは渡さない）。
                            text: wrapper.widgetText
                            backgroundColor: wrapper.widgetBackgroundColor
                            textColor: wrapper.widgetTextColor
                            fontSize: wrapper.widgetFontSize
                            fontBold: wrapper.widgetFontBold
                            fontItalic: wrapper.widgetFontItalic
                            fontFamily: wrapper.widgetFontFamily
                            hAlign: wrapper.widgetHAlign
                            vAlign: wrapper.widgetVAlign
                            widgetOpacity: wrapper.widgetOpacity
                            widgetEnabled: wrapper.widgetEnabled
                            // Task 47: 選択中継は Button と同形。クリックで selectRequested を
                            // 発火して Canvas の選択集合へ加除する（Label も EditableWidget の
                            // 選択枠・リサイズハンドルが効く）。Label に action 実行は無い。
                            onClicked: function(modifiers) {
                                wrapper.selectRequested(wrapper.widgetId, modifiers)
                            }
                        }
                    }

                    Component {
                        id: numericComponent
                        HmiNumericField {
                            // Task 50: 型分岐の観察用 objectName（HmiButton / HmiLabel と対。
                            // E2E / unit は hmiNumericField で参照）。
                            objectName: "hmiNumericField"
                            anchors.fill: parent
                            // Editor キャンバスは設計面＝読取専用表示。selectArea（MouseArea）が
                            // 有効になり clicked を中継、TextField は入力を奪わない。
                            editable: false
                            // HmiButton と同じく wrapper 経由でメタへバインドする。NumericField は
                            // 全スタイル（背景・枠・フォント・配置・不透明度・有効）を持つ。
                            text: wrapper.widgetText
                            backgroundColor: wrapper.widgetBackgroundColor
                            textColor: wrapper.widgetTextColor
                            fontSize: wrapper.widgetFontSize
                            borderColor: wrapper.widgetBorderColor
                            borderWidth: wrapper.widgetBorderWidth
                            cornerRadius: wrapper.widgetRadius
                            fontBold: wrapper.widgetFontBold
                            fontItalic: wrapper.widgetFontItalic
                            fontFamily: wrapper.widgetFontFamily
                            hAlign: wrapper.widgetHAlign
                            vAlign: wrapper.widgetVAlign
                            widgetOpacity: wrapper.widgetOpacity
                            widgetEnabled: wrapper.widgetEnabled
                            // Task 54: 数値範囲 + presence を渡す（Editor キャンバスは editable:false で
                            // validator 非適用だが、一貫のため流す。clamp は Simulator の commit で効く）。
                            minValue: wrapper.widgetMinValue
                            maxValue: wrapper.widgetMaxValue
                            hasMin: wrapper.widgetHasMin
                            hasMax: wrapper.widgetHasMax
                            // Task 50: 選択中継は Button / Label と同形。write 結線（valueCommitted）は
                            // Task 51 で SimulatorCanvas 側に足す（Editor は読取専用なので結線しない）。
                            onClicked: function(modifiers) {
                                wrapper.selectRequested(wrapper.widgetId, modifiers)
                            }
                        }
                    }

                    Component {
                        id: trendComponent
                        HmiTrend {
                            // Task T-B: 型分岐の観察用 objectName（他 Widget と対。
                            // E2E / unit は hmiTrend で参照）。
                            objectName: "hmiTrend"
                            anchors.fill: parent
                            // Editor キャンバスは設計面＝ライブデータが無い。live:false にして
                            // ダミー波形プレビューを描く（サンプリング・Timer は動かさない）。
                            live: false
                            // pointCount / 線色 / 背景はプレビューに反映する（Y 範囲 / 周期は
                            // 流すだけで描画形状に影響＝プレビューでも一貫させる）。Trend は
                            // text / フォント / トグルを持たないので渡さない。
                            // Task 8B-B: series を流すと HmiTrend が系列数ぶんダミー波形を
                            // 色違いで描く（プレビュー）。Editor はライブ値が無いので seriesValues
                            // は流さない（live:false でサンプリングしないため）。
                            series: wrapper.widgetSeries
                            pointCount: wrapper.widgetPointCount
                            yMin: wrapper.widgetYMin
                            yMax: wrapper.widgetYMax
                            hasYMin: wrapper.widgetHasYMin
                            hasYMax: wrapper.widgetHasYMax
                            lineColor: wrapper.widgetLineColor
                            sampleMs: wrapper.widgetSampleMs
                            // Task 8B-D: 軸/凡例フラグを流す（既定 OFF＝後方互換）。
                            showGrid: wrapper.widgetShowGrid
                            showLegend: wrapper.widgetShowLegend
                            yTickCount: wrapper.widgetYTickCount
                            backgroundColor: wrapper.widgetBackgroundColor
                            borderColor: wrapper.widgetBorderColor
                            borderWidth: wrapper.widgetBorderWidth
                            cornerRadius: wrapper.widgetRadius
                            widgetOpacity: wrapper.widgetOpacity
                            widgetEnabled: wrapper.widgetEnabled
                            // Task T-B: 選択中継は他 Widget と同形。
                            onClicked: function(modifiers) {
                                wrapper.selectRequested(wrapper.widgetId, modifiers)
                            }
                        }
                    }

                    Component {
                        id: meterComponent
                        HmiMeter {
                            // Task M-B: 型分岐の観察用 objectName（他 Widget と対。
                            // E2E / unit は hmiMeter で参照）。
                            objectName: "hmiMeter"
                            anchors.fill: parent
                            // Editor キャンバスは設計面＝ライブ値が無い。live:false にして
                            // 中間値（(min+max)/2）プレビューを描く（value は流さない）。
                            live: false
                            // Meter 固有フィールドを流す（未指定は 0 / 空 / presence false）。
                            // Meter は text / フォント / トグルを持たないので渡さない。
                            meterMin: wrapper.widgetMeterMin
                            meterMax: wrapper.widgetMeterMax
                            hasMeterMin: wrapper.widgetHasMeterMin
                            hasMeterMax: wrapper.widgetHasMeterMax
                            arcColor: wrapper.widgetArcColor
                            needleColor: wrapper.widgetNeedleColor
                            tickCount: wrapper.widgetTickCount
                            unit: wrapper.widgetUnit
                            backgroundColor: wrapper.widgetBackgroundColor
                            borderColor: wrapper.widgetBorderColor
                            borderWidth: wrapper.widgetBorderWidth
                            cornerRadius: wrapper.widgetRadius
                            widgetOpacity: wrapper.widgetOpacity
                            widgetEnabled: wrapper.widgetEnabled
                            // Task M-B: 選択中継は他 Widget と同形。
                            onClicked: function(modifiers) {
                                wrapper.selectRequested(wrapper.widgetId, modifiers)
                            }
                        }
                    }

                    // Task W-B（Phase 11）: SimpleButton の 6 分岐目。Editor キャンバスは設計面なので
                    // live:false（長押しを動かさず静的プレビュー・進捗 0 固定）。形状 / テーマ / 差し色 /
                    // 長押し時間 / ON-OFF（checked）を wrapper メタから流す（未指定は空 / 0 で HmiSimpleButton
                    // 側の resolved* が既定へ解決）。選択中継は他 Widget と同形。
                    Component {
                        id: simpleButtonComponent
                        HmiSimpleButton {
                            objectName: "hmiSimpleButton"
                            anchors.fill: parent
                            live: false
                            text: wrapper.widgetText
                            shape: wrapper.widgetShape
                            theme: wrapper.widgetTheme
                            accentColor: wrapper.widgetAccentColor
                            holdMs: wrapper.widgetHoldMs
                            checked: wrapper.widgetChecked
                            // 共通状態（opacity / enabled）も他 Widget と同型で流す（Codex PR #164 [P2]）。
                            widgetOpacity: wrapper.widgetOpacity
                            widgetEnabled: wrapper.widgetEnabled
                            onClicked: function(modifiers) {
                                wrapper.selectRequested(wrapper.widgetId, modifiers)
                            }
                        }
                    }
                }
            }
        }

        // Task W-D（Phase 11）: サンプルパレットからのドラッグ&ドロップ受け口。
        // パレットのセル（SamplePalette.qml）が Drag.mimeData にプリセット JSON を
        // 載せてドラッグし、ここへドロップするとドロップ座標（widgetLayer と同じ
        // background 基準）へ addPresetWidget で追加する。
        // DropArea は MouseArea ではないので通常のクリック（選択 / 背景解除）は妨げない。
        // widgetLayer より後ろに宣言＝最前面だが、ドラッグ以外のイベントは素通りする。
        DropArea {
            id: presetDropArea
            objectName: "presetDropArea"
            anchors.fill: parent
            // パレットセルが付ける Drag.keys と一致させ、他のドラッグは受けない。
            keys: ["application/x-hmi-preset"]

            // ドラッグ中の視覚フィードバック（薄い枠のハイライト）。落とせる面だと分かる。
            Rectangle {
                anchors.fill: parent
                visible: presetDropArea.containsDrag
                color: "transparent"
                border.color: "#4c9be0"
                border.width: 2
                radius: 2
            }

            onDropped: function(drop) {
                const json = drop.getDataAsString("application/x-hmi-preset")
                if (!json) {
                    drop.accepted = false
                    return
                }
                let preset
                try {
                    preset = JSON.parse(json)
                } catch (e) {
                    drop.accepted = false
                    return
                }
                // drop.x / drop.y は DropArea（= background = widgetLayer と同座標系）基準。
                // ドロップ地点を中心にウィジェットを置く（clamp は addPresetWidget 側）。
                root.addPresetWidget(preset, drop.x, drop.y)
                drop.accept()
            }
        }
    }
}
