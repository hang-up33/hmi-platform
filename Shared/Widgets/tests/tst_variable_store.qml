import QtQuick
import QtTest
import HmiWidgets

// Task 39: ランタイム変数ストア（VariableStore singleton）の単体検証。
// 実行 / 描画への接続は T41 だが、ここで初期化 / get / set / toggle / 型変換 /
// クリアの基本動作を固定する。
TestCase {
    name: "VariableStore"

    // 各テスト前にストアを空へ戻す（singleton は状態がテスト間で共有されるため）。
    function init() {
        VariableStore.clear();
        compare(Object.keys(VariableStore.values).length, 0);
    }

    // 定義配列から初期値（文字列表現）を type に応じて coerce して初期化する。
    function test_init_from_definitions_coerces_types() {
        VariableStore.initFrom([
            { name: "running", type: "bool",   initial: "true" },
            { name: "count",   type: "int",    initial: "5" },
            { name: "label",   type: "string", initial: "hello" }
        ]);
        compare(VariableStore.get("running"), true);
        compare(VariableStore.get("count"), 5);
        compare(VariableStore.get("label"), "hello");
        verify(VariableStore.has("running"));
        verify(!VariableStore.has("missing"));
    }

    // setValue で現在値を更新できる（values 再代入で通知）。
    function test_set_value_updates() {
        VariableStore.initFrom([{ name: "count", type: "int", initial: "0" }]);
        compare(VariableStore.get("count"), 0);
        VariableStore.setValue("count", 42);
        compare(VariableStore.get("count"), 42);
    }

    // Codex PR #78 [P2]: setValue は **新しいオブジェクト**を values に再代入する
    // （同一参照の破壊的変更だと QML の var バインディングが追従しない）。参照が
    // 変わることを固定し、T41 の追従 UI が再評価されることを担保する。
    function test_set_value_reassigns_new_object() {
        VariableStore.initFrom([{ name: "count", type: "int", initial: "0" }]);
        const before = VariableStore.values;
        VariableStore.setValue("count", 7);
        verify(VariableStore.values !== before, "values が新しいオブジェクトに差し替わっていない");
        compare(VariableStore.get("count"), 7);
    }

    // toggle は bool を反転する（setVariable/toggleVariable アクションの土台）。
    function test_toggle_flips_bool() {
        VariableStore.initFrom([{ name: "running", type: "bool", initial: "false" }]);
        compare(VariableStore.get("running"), false);
        VariableStore.toggle("running");
        compare(VariableStore.get("running"), true);
        VariableStore.toggle("running");
        compare(VariableStore.get("running"), false);
    }

    // coerce: bool は "true"/"1"/1/true を真、それ以外を偽。int は数値化、不正は 0。
    function test_coerce_rules() {
        compare(VariableStore.coerce("bool", "true"), true);
        compare(VariableStore.coerce("bool", "1"), true);
        compare(VariableStore.coerce("bool", "false"), false);
        compare(VariableStore.coerce("bool", ""), false);
        compare(VariableStore.coerce("int", "7"), 7);
        compare(VariableStore.coerce("int", "abc"), 0);
        compare(VariableStore.coerce("string", "x"), "x");
        // Task 53: real は小数を保つ。不正・空は 0.0。
        compare(VariableStore.coerce("real", "36.5"), 36.5);
        compare(VariableStore.coerce("real", "abc"), 0.0);
        // Codex PR #112 [P2]: 非有限値（Infinity / 1e309）は 0.0 に落とす（isFinite で弾く）。
        compare(VariableStore.coerce("real", "1e309"), 0.0);
        compare(VariableStore.coerce("real", "Infinity"), 0.0);
    }
}
