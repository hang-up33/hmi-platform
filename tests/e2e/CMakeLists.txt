# Task 17: Phase 3-A E2E ハーネス雛形 + smoke 1 件
#
# E2E テストは Editor / Simulator のビルドプロダクトに依存する。CMake の
# `add_test` は他テストの run-after 順序しか制御しないため、ビルド依存は
# Python ランナー側に渡したバイナリパスの存在確認で担保する（CMake は
# `cmake --build && ctest` の順で実行される前提を README で明示）。
#
# Spix 無効ビルド（Windows MinGW デフォルト）では E2E テストを丸ごと
# スキップする。`HMI_ENABLE_E2E` の状態だけで判定するため、トップレベル
# CMakeLists.txt より後で評価される必要がある。

if(NOT HMI_ENABLE_E2E)
    message(STATUS "E2E tests: skipped (HMI_ENABLE_E2E=OFF)")
    return()
endif()

find_package(Python3 COMPONENTS Interpreter)
if(NOT Python3_FOUND)
    message(WARNING "E2E tests: Python3 interpreter not found, skipping")
    return()
endif()

message(STATUS "E2E tests: enabled (Python ${Python3_VERSION})")

add_test(
    NAME e2e_smoke
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_smoke.py
        --editor-binary $<TARGET_FILE:hmi_editor>
)
set_tests_properties(e2e_smoke PROPERTIES
    TIMEOUT 30
    LABELS e2e
)

# Task 18: Editor 配置 + ドラッグ E2E。smoke と同じハーネスを共有。
add_test(
    NAME e2e_place_and_drag
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_place_and_drag.py
        --editor-binary $<TARGET_FILE:hmi_editor>
)
set_tests_properties(e2e_place_and_drag PROPERTIES
    TIMEOUT 30
    LABELS e2e
)

# Task 19: 保存 → 別プロセス --open → 再現の round-trip E2E。
# Editor を 2 回起動するため TIMEOUT は smoke/place_and_drag より長めに取る。
add_test(
    NAME e2e_save_load_roundtrip
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_save_load_roundtrip.py
        --editor-binary $<TARGET_FILE:hmi_editor>
)
set_tests_properties(e2e_save_load_roundtrip PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task 20: Simulator 表示 E2E。Editor で JSON を保存し、Simulator を
# `--open <path>` で起動して描画を確認する cross-app テスト。Editor と
# Simulator の 2 プロセスを順に起動するため TIMEOUT は roundtrip と同等に取る。
add_test(
    NAME e2e_simulator_display
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_simulator_display.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_simulator_display PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task 30: スタイルの「データ経路 → Simulator 描画」cross-app E2E。
# Editor で btn001 を選択し、選択中 Widget のスタイルメタ（text/背景色/文字色＝
# インスペクタの書き戻し先と同一経路）を更新 → saveTo → 保存 JSON を直接検証 →
# Simulator を `--open` で起動し HmiButton の描画値を getStringProperty で確認する。
# ※ インスペクタ TextField UI 自体は Spix が onTextEdited を発火できないため駆動しない
#    （test_style_roundtrip.py の docstring 参照。検証スコープを直接メタ更新に限定）。
# Editor / Simulator の 2 プロセスを順に起動するため TIMEOUT は他の cross-app と同等。
add_test(
    NAME e2e_style_roundtrip
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_style_roundtrip.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_style_roundtrip PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task 43: アクション / バインディングの「動き」cross-app E2E。
# Editor で変数 / アクション / バインディング付き JSON を round-trip 保存 → JSON 直接検証 →
# Simulator を `--open` で起動し HmiButton を mouseClick → setVariable 実行 → text バインディング
# 追従（"OFF" → "ON"）を getStringProperty で観測する。これまでの静的 round-trip と異なり
# 実クリックで状態遷移を見る初の E2E。Editor / Simulator の 2 プロセスを順に起動する。
add_test(
    NAME e2e_action_roundtrip
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_action_roundtrip.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_action_roundtrip PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task 49: Label の round-trip + binding cross-app E2E。
# Editor で Label 2 件（静的 + binding）+ 変数を持つ JSON を `--open` → saveTo で round-trip →
# 保存 JSON を直接検証 → Simulator を `--open` で起動し HmiLabel（objectName "hmiLabel"）の
# text / textColor 描画と、text バインディングの変数追従（"BOUND"）を getStringProperty で確認。
# Button 用 test_style_roundtrip / test_action_roundtrip の Label 版。2 プロセス起動のため
# TIMEOUT は他の cross-app と同等。
add_test(
    NAME e2e_label_roundtrip
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_label_roundtrip.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_label_roundtrip PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task 52: NumericField の typed-write cross-app E2E。
# Editor で setpoint(int) 変数 + NumericField(value binding) + 観測用 Label(text binding) を
# `--open` → saveTo で round-trip → 保存 JSON を直接検証（type:"NumericField" / binding
# {property:"value"}）→ Simulator を `--open` で起動し、読み（NumericField/Label が setpoint=10 に
# 追従）を確認 → setStringProperty で入力テキストを設定し commitValue() を invokeMethod で叩いて
# 確定を模す（Spix は editingFinished を発火不可）→ writeBoundValue で setpoint=42 に更新され
# 観測用 Label が "42" へ追従するのを getStringProperty で観測する。読み書き両用 binding を
# E2E で見る初のテスト。2 プロセス起動のため TIMEOUT は他の cross-app と同等。
add_test(
    NAME e2e_numeric_input
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_numeric_input.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_numeric_input PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task 55: NumericField 拡張（real 型 + 数値範囲 clamp）の cross-app E2E。
# Phase 6 の e2e_numeric_input（int のみ）を補完し、Phase 6-B の 2 軸を観測する：
# Editor で real 変数 + max=100 を持つ NumericField を含む JSON を `--open` → saveTo で
# round-trip → 保存 JSON を直接検証（type:"real" 変数 / maxValue キー / value binding）→
# Simulator を `--open` で起動し、setStringProperty で入力テキストを設定 → commitValue() を
# invokeMethod で叩いて確定を模す → real は小数 "36.5" が保たれ、clamp は範囲外 "150" が
# max=100 へ丸められて変数 write → 観測用 Label が追従するのを getStringProperty で観測する。
# 2 プロセス起動のため TIMEOUT は他の cross-app と同等。
add_test(
    NAME e2e_numeric_extend
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_numeric_extend.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_numeric_extend PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task T-D (Phase 8): Trend のライブサンプリング cross-app E2E。
# Editor で sensorTemp(int) 変数 + Trend(value binding, pointCount) + 操作用 NumericField
# (同変数 value binding) を `--open` → saveTo で round-trip → 保存 JSON を直接検証
# （type:"Trend" / value binding / pointCount）→ Simulator を `--open` で起動し、操作用
# NumericField を setStringProperty + commitValue() で複数回確定して同変数を変化させ、
# Trend（objectName "hmiTrend"）の公開 sampleCount が増加し lastValue が直近の書込値へ
# 追従するのを getStringProperty で観測する。Canvas はピクセル不可視なので公開プロパティ
# のみで「変数変化 → サンプル取り込み」を見る初の E2E。2 プロセス起動のため TIMEOUT は
# 他の cross-app と同等。
add_test(
    NAME e2e_trend_live
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_trend_live.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_trend_live PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task 8B-E (Phase 8-B): Trend 複数系列の「系列ごと独立サンプリング」cross-app E2E。
# Editor で 2 系列（sensorTemp/sensorPressure）+ 凡例 ON（showGrid/showLegend/yTickCount）の
# Trend + 各変数の操作用 NumericField を `--open` → saveTo で round-trip → 保存 JSON を
# 直接検証（type:"Trend" / series 2 件 / 各 variable・color / showLegend）→ Simulator を
# `--open` で起動し、操作用 NumericField A/B を交互に setStringProperty + commitValue() で
# 確定して各系列の変数を独立に変化させ、Trend（objectName "hmiTrend"）の公開
# sampleCountAt(i) が増加し lastValueAt(i) がその系列へ書いた値へ追従する（系列を取り
# 違えない）のを invokeMethod 返り値で観測する。test_trend_live の複数系列版。
# 2 プロセス起動のため TIMEOUT は他の cross-app と同等。
add_test(
    NAME e2e_trend_multi
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_trend_multi.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_trend_multi PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task M-D (Phase 10): Meter の針追従 cross-app E2E。
# Editor で vehicleSpeed(int) 変数 + Meter(value binding, meterMin/meterMax) + 操作用
# NumericField(同変数 value binding) を `--open` → saveTo で round-trip → 保存 JSON を直接検証
# （type:"Meter" / value binding / meterMin・meterMax）→ Simulator を `--open` で起動し、操作用
# NumericField を setStringProperty + commitValue() で複数回確定して同変数を変化させ、
# Meter（objectName "hmiMeter"）の公開 displayValue が書いた値（範囲外は端へ clamp）へ、
# needleAngle が弧の角度域（実行時に読む startAngle/spanAngle から計算した期待値）へ追従する
# のを getStringProperty で観測する。Canvas はピクセル不可視なので公開プロパティのみで
# 「変数変化 → 針追従」を見る（test_trend_live の Meter 版）。2 プロセス起動のため TIMEOUT は
# 他の cross-app と同等。
add_test(
    NAME e2e_meter_live
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_meter_live.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_meter_live PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# Task W-E (Phase 11): SimpleButton の長押しトグル cross-app E2E。
# Editor で pumpRunning(bool) 変数 + SimpleButton(shape/theme/accentColor/holdMs +
# checked binding) を `--open` → saveTo で round-trip → 保存 JSON を直接検証
# （type:"SimpleButton" / 固有フィールド / checked binding）→ Simulator を `--open` で起動し、
# 公開メソッド commitHold() を invokeMethod で複数回叩いて長押し満了（確定）を模し、
# SimpleButton（objectName "hmiSimpleButton"）の公開 checked が each 回で反転する
# （onToggled → writeBoundValue → VariableStore → boundValue("checked") 再評価）のを
# getStringProperty で観測する。Spix は実 press-hold を発火できないため確定点を公開メソッド
# で模す（NumericField の commitValue() と同じ前例）。Canvas はピクセル不可視なので公開
# プロパティのみで「長押し確定 → 変数 → ON/OFF 追従」を見る。2 プロセス起動のため TIMEOUT
# は他の cross-app と同等。
add_test(
    NAME e2e_simple_button_live
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_simple_button_live.py
        --editor-binary $<TARGET_FILE:hmi_editor>
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_simple_button_live PROPERTIES
    TIMEOUT 60
    LABELS e2e
)

# MB-2: Modbus TCP 読込ポーリングの cross-app E2E。
# pymodbus ソフトスレーブ（modbus_slave.py をサブプロセス起動）の holding register を
# Simulator（ModbusController）が周期ポーリング → 変数 → text binding 追従で Label に反映
# されることを観測する。外部デバイス（Modbus）由来の値が UI へ流れる初の E2E。
# Editor は不要（fixture JSON を手書きし Simulator に --open）。pymodbus 不在 / スレーブ
# 起動失敗時は exit 77 で SKIP（SKIP_RETURN_CODE）。スレーブ起動 + ポーリング待ちのため
# TIMEOUT は他の cross-app より長めに取る。
add_test(
    NAME e2e_modbus_read
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_modbus_read.py
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_modbus_read PROPERTIES
    TIMEOUT 90
    LABELS e2e
    SKIP_RETURN_CODE 77
)

# MB-4: Modbus TCP 書込 + 接続状態の cross-app E2E。
# pymodbus ソフトスレーブ相手に、Simulator で NumericField の入力確定（commitValue を
# invokeMethod で模す）→ writeBoundValue → ModbusController.writeVariable → PLC の holding
# register が書き換わることを、別の pymodbus client で読み返して観測する。MB-2 の読み
# （PLC→HMI）に対し、逆向きの書き（HMI→PLC）を見る初の E2E。Editor は不要（fixture JSON を
# 手書きし Simulator に --open）。pymodbus 不在 / スレーブ起動失敗時は exit 77 で SKIP。
add_test(
    NAME e2e_modbus_write
    COMMAND ${Python3_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/test_modbus_write.py
        --simulator-binary $<TARGET_FILE:hmi_simulator>
)
set_tests_properties(e2e_modbus_write PROPERTIES
    TIMEOUT 90
    LABELS e2e
    SKIP_RETURN_CODE 77
)

# OP-2: OPC-UA 購読読込の cross-app E2E。
# asyncua ソフトサーバ（opcua_server.py をサブプロセス起動）の ns=2;s=Temp ノードを
# Simulator（OpcUaController）が MonitoredItem 購読 → 変数 → text binding 追従で Label に反映
# されることを観測する。外部デバイス（OPC-UA）由来の値が UI へ流れる Modbus 読込の OPC-UA 版。
# Qt OPC-UA はサーバ機能を持たず C++ ユニットでは実購読を回せないため、購読 round-trip は
# 本 E2E が担う。Editor は不要（fixture JSON を手書きし Simulator に --open）。asyncua 不在 /
# サーバ起動失敗時は exit 77 で SKIP。接続 discovery + 購読作成のため TIMEOUT は長めに取る。
# Simulator が OPC-UA 機能込みでビルドされた環境（HMI_HAS_OPCUA）でのみ登録する。OPC-UA 無しで
# ビルドされた Simulator では購読が起きず FAIL になるため、テスト自体を登録しない。
if(HMI_HAS_OPCUA)
    add_test(
        NAME e2e_opcua_read
        COMMAND ${Python3_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/test_opcua_read.py
            --simulator-binary $<TARGET_FILE:hmi_simulator>
    )
    set_tests_properties(e2e_opcua_read PROPERTIES
        TIMEOUT 120
        LABELS e2e
        SKIP_RETURN_CODE 77
    )

    # OP-4: OPC-UA 書込 + 接続状態の cross-app E2E。
    # asyncua 書込可能ソフトサーバ（opcua_server.py --writable）の ns=2;s=Setpoint ノードへ、
    # Simulator で NumericField の入力確定（commitValue を invokeMethod で模す）→
    # writeBoundValue → OpcUaController.writeVariable → サーバ側ノードが書き換わることを、別の
    # asyncua client で読み返して観測する。OP-2 の読み（サーバ→HMI）に対し逆向きの書き（HMI→
    # サーバ）を見る。Editor は不要（fixture JSON を手書きし Simulator に --open）。asyncua 不在 /
    # サーバ起動失敗時は exit 77 で SKIP。接続 discovery + 購読作成のため TIMEOUT は長めに取る。
    # Simulator が OPC-UA 機能込みでビルドされた環境（HMI_HAS_OPCUA）でのみ登録する。
    add_test(
        NAME e2e_opcua_write
        COMMAND ${Python3_EXECUTABLE}
            ${CMAKE_CURRENT_SOURCE_DIR}/test_opcua_write.py
            --simulator-binary $<TARGET_FILE:hmi_simulator>
    )
    set_tests_properties(e2e_opcua_write PROPERTIES
        TIMEOUT 120
        LABELS e2e
        SKIP_RETURN_CODE 77
    )
endif()
