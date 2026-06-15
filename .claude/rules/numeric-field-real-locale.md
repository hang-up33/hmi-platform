---
name: NumericField real 型の locale / 精度の罠
description: HmiNumericField を real（浮動小数）対応する際の locale 統一・指数表記回避・JSON 数値精度・C++ 範囲外キャストの注意。Phase 6-B Task 53 で確立。
paths:
  - "Shared/Widgets/qml/HmiNumericField.qml"
  - "Shared/Widgets/qml/VariableStore.qml"
  - "Shared/Schema/src/VariableData.cpp"
  - "Simulator/qml/SimulatorCanvas.qml"
  - "Shared/Widgets/tests/tst_hmi_numeric_field.qml"
  - "Simulator/tests/tst_simulator_canvas.qml"
metadata:
  type: reference
---

# NumericField を real（浮動小数）対応する時の罠（Phase 6-B Task 53 で確立）

int では素通せた箇所が real では破綻する。Task 53（PR #112）で Codex / CodeRabbit から計 6 件の指摘を受けた。
**核心は「real の表示値は変数ストアの JS 数値（`coerce("real")=Number(raw)`）由来で、常に ASCII 小数点（C locale）」**という前提に、validator・commit・表示・テスト入力を **すべて C locale（ASCII の `.`）へ揃える**こと。int は従来どおり system `Qt.locale()`（IntValidator の locale 桁区切り受理契約を維持。整数は桁区切りが無ければどの locale でも誤読しない）。

## 守ること（real path）

1. **validator は C locale 固定**：`DoubleValidator { locale: "C"; notation: DoubleValidator.StandardNotation }`。
   system locale 既定だと、ASCII の表示値 `"36.5"` が小数点カンマ環境で自身の validator に Invalid 扱いされる。
2. **commit のパースも C locale**：`Number.fromLocaleString(Qt.locale("C"), field.text)`（int は `Qt.locale()`）。
   system locale で再パースすると、編集せず focus/blur しただけの `"36.5"` が桁区切り誤読され 365 / 0 を書き戻す。
3. **確定値・表示値は固定小数表記へ**：`String(n)` は `1e-7` / `1e+21` の指数表記を生み、StandardNotation validator と矛盾する。
   文字列操作で指数を展開する `_toFixedNotation`（`toFixed` は >= 1e21 で指数を返すので不可）を **commit と表示テキスト両方**に適用する。
4. **JSON 数値 `initial` は精度を保つ**（`VariableData::jsonValueToString`）：`QString::number(d)` 既定は有効 6 桁で `0.123456789` が丸まる。
   **round-trip する最短桁探索**（`QString::number(d,'g',prec)` を prec 1→16 で試し元値に戻る最小桁、fallback 17）でクリーンかつ無損失に。
5. **整数表現化は UB を避ける**：`static_cast<long long>(d)` は `1e100` 等で範囲外＝UB。
   `std::isfinite(d) && std::modf(d,&i)==0.0 && min<=d && d<max`（上限は 2^63 へ丸まる `LLONG_MAX` を厳密未満で弾く）で守ってからキャスト。
6. **テスト入力も C locale 直値**：real のテストは `Qt.locale().decimalPoint` 由来でなく **ASCII `"36.5"` 固定**。
   さもないと小数点カンマ環境で test が locale 依存に失敗する。`tst_hmi_numeric_field.qml` の init 再バインドも実バインド（`_displayText` 経由）と一致させる。

## Why

real 表示は C locale ASCII 固定なのに、Phase 6 の int 実装をそのまま流用すると validator/commit/表示が system locale のままで不整合になる。
6 件の指摘はすべて「ASCII 表示と locale パースの不整合」「文字列正規化の精度/表記」に帰着する。Task 54（min/max）や後続入力 Widget（Gauge / Toggle）の real 対応でも同じ統一を踏襲する。
