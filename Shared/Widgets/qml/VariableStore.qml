pragma Singleton
import QtQuick

// Task 39: 実行時の変数（タグ）ストア。**widget 非依存の横断サブシステム**で、
// 変数名→現在値 を実行中だけ保持する。Schema の VariableData（定義）とは別物で、
// ここは「実行時の現在値」だけを持つ。
//
// 本タスク（T39）では型と保存（round-trip）が主目的のため、このストアは **まだ描画 /
// 実行に接続しない**（Editor は使わない）。Simulator / Runtime でアクション実行と
// バインディング追従に接続するのは T41。ここでは初期化 / get / set / toggle の
// 単体動作のみを用意し、ユニットテストで固定する。
//
// 共有 QML モジュール（HmiWidgets）の singleton なので、Editor / Simulator / Runtime の
// どこからでも `import HmiWidgets` で `VariableStore` として参照できる。
QtObject {
    id: store

    // 変数名→現在値 のマップ。再代入で変更通知する（in-place 変更は通知されないため）。
    property var values: ({})

    // 定義配列（[{name,type,initial}, ...]）から初期値で初期化する。
    // initial は文字列表現（Schema 仕様）なので type に応じて coerce する。
    function initFrom(definitions) {
        const next = {}
        if (definitions) {
            for (let i = 0; i < definitions.length; ++i) {
                const d = definitions[i]
                if (d && d.name) {
                    next[d.name] = coerce(d.type, d.initial)
                }
            }
        }
        values = next
    }

    // 文字列表現の初期値 / 値を type に応じて実値へ変換する。
    function coerce(type, raw) {
        if (type === "bool") {
            return raw === true || raw === "true" || raw === "1" || raw === 1
        }
        if (type === "int") {
            const n = parseInt(raw, 10)
            return isNaN(n) ? 0 : n
        }
        // Task 53: real（浮動小数）。Number は全体妥当性を見る（parseFloat は途中まで読む）。
        // **有限値のみ**を返す（Codex PR #112 [P2]）：`isFinite` は NaN / ±Infinity を弾くので、
        // `"1e309"`→Infinity や `"Infinity"` のような非有限入力（NumericField の表示・書き戻しを
        // 壊す）も 0.0 に落とす。不正 / 空も 0.0。toggle は bool 専用なので real では呼ばれない。
        if (type === "real") {
            const n = Number(raw)
            return isFinite(n) ? n : 0.0
        }
        // string（既定）
        return (raw === undefined || raw === null) ? "" : String(raw)
    }

    function has(name) {
        return values[name] !== undefined
    }

    function get(name) {
        return values[name]
    }

    // 現在値を設定する。**新しいオブジェクトを作って再代入**する：QML の `var` は参照先
    // 内部を変えても依存バインディングへ通知されず、プロパティ自体を別オブジェクトにする
    // 必要がある（Codex PR #78 [P2]）。`const next = values` で同一参照を破壊的に変えると
    // T41 で `VariableStore.values[...]` を追従する UI が再評価されない。
    function setValue(name, val) {
        const next = Object.assign({}, values)
        next[name] = val
        values = next
    }

    // bool 変数を反転する（未定義 / 非 bool は false 起点で反転）。
    function toggle(name) {
        setValue(name, !values[name])
    }

    // すべての現在値を破棄する。
    function clear() {
        values = ({})
    }
}
