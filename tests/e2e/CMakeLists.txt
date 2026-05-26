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
