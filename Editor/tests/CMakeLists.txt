add_executable(tst_project_io
    tst_project_io.cpp
    ../src/ProjectIo.cpp
    ../src/ProjectIo.h
)

target_include_directories(tst_project_io PRIVATE ../src)

target_link_libraries(tst_project_io
    PRIVATE
        Qt6::Test
        Qt6::Core
        hmi_schema
)

add_test(NAME tst_project_io COMMAND tst_project_io)

# Task 14: Editor QML テスト（Qt Quick Test）。
# Canvas / EditableWidget を Loader 経由でロードしてドラッグ動作と
# widgetModel 反映を検証する。HmiWidgets を本体 Canvas.qml が import するため
# hmi_widgetsplugin をリンクする（Task 13 で確立した運用と同じ）。
add_executable(tst_hmi_editor_qml main.cpp)

target_compile_definitions(tst_hmi_editor_qml
    PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(tst_hmi_editor_qml
    PRIVATE
        Qt6::QuickTest
        Qt6::Qml
        Qt6::Quick
        hmi_widgetsplugin
)

# CI / headless 環境でも実行できるよう -platform offscreen を明示する
# （Task 12 で確立した運用）。
add_test(NAME tst_hmi_editor_qml COMMAND tst_hmi_editor_qml -platform offscreen)
