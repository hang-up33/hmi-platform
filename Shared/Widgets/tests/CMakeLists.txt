# Qt Quick Test ハーネス。
# - add_executable は Task 9 で確立した方針（.app バンドルを避ける）。
# - QUICK_TEST_SOURCE_DIR を -D で渡すことで、ハーネスが本ディレクトリの
#   tst_*.qml を走査するようになる（Qt 公式ドキュメント推奨）。
# - Qt6::QuickTest と Qt6::Qml がリンク必須。Qt6::Quick は実行時に動的ロードされる
#   が、明示リンクしておくとプラットフォーム差の事故が減るため含める。
add_executable(tst_hmi_widgets_qml main.cpp)

target_compile_definitions(tst_hmi_widgets_qml
    PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(tst_hmi_widgets_qml
    PRIVATE
        Qt6::QuickTest
        Qt6::Qml
        Qt6::Quick
)

add_test(NAME tst_hmi_widgets_qml COMMAND tst_hmi_widgets_qml)
