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
