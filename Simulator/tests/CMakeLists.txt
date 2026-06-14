add_executable(tst_project_loader
    tst_project_loader.cpp
    ../src/ProjectLoader.cpp
    ../src/ProjectLoader.h
)

target_include_directories(tst_project_loader PRIVATE ../src)

target_link_libraries(tst_project_loader
    PRIVATE
        Qt6::Test
        Qt6::Core
        hmi_schema
)

add_test(NAME tst_project_loader COMMAND tst_project_loader)

# Task 41: Simulator QML テスト（Qt Quick Test）。
# SimulatorCanvas を Loader 経由でロードし、アクション実行（setVariable /
# toggleVariable）と binding 追従（visible / text）を検証する。SimulatorCanvas は
# 本体 QML が HmiWidgets を import するため hmi_widgetsplugin をリンクする
# （Editor 側 tst_hmi_editor_qml と同じ運用）。
# 変数デバッグパネルのテスト（tst_simulator_var_panel.qml）は本体 Main.qml を生成し、
# Main.qml が `import HmiSimulator` するため hmi_simulator_qmlplugin もリンクする。
add_executable(tst_hmi_simulator_qml main.cpp)

target_compile_definitions(tst_hmi_simulator_qml
    PRIVATE
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)

target_link_libraries(tst_hmi_simulator_qml
    PRIVATE
        Qt6::QuickTest
        Qt6::Qml
        Qt6::Quick
        hmi_widgetsplugin
        hmi_simulator_qmlplugin
)

# CI / headless 環境でも実行できるよう -platform offscreen を明示する。
add_test(NAME tst_hmi_simulator_qml COMMAND tst_hmi_simulator_qml -platform offscreen)
