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

# ショートカットが StandardKey のすべてのキーに束縛されていることを確かめる（契約 Main_Inv1）。
# Editor を起動してスクショを 1 枚撮り、その間に Qt の警告が出ないことを見る。
# 起動に失敗したときに素通りしないよう、保存できたことも確かめる。
add_test(NAME inv_Main_Inv1_shortcutsBindAllStandardKeys
         COMMAND $<TARGET_FILE:hmi_editor> --screenshot ${CMAKE_CURRENT_BINARY_DIR}/inv_Main_Inv1.png)
set_tests_properties(inv_Main_Inv1_shortcutsBindAllStandardKeys PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
    PASS_REGULAR_EXPRESSION "\\[screenshot\\]"
    FAIL_REGULAR_EXPRESSION "Only binding to one of multiple key bindings")

# offscreen では StandardKey に割り当たるキーが 1 つだけのことがあり、上の試験では警告が出ない。
# Linux の xcb では Delete に複数のキーが割り当たるので、xvfb-run があれば xcb でも同じことを確かめる。
# xcb を起動できない環境（xcb 系ライブラリが無いなど）では SKIP になる。
find_program(HMI_XVFB_RUN xvfb-run)
if(HMI_XVFB_RUN)
    add_test(NAME inv_Main_Inv1_shortcutsBindAllStandardKeys_xcb
             COMMAND ${HMI_XVFB_RUN} -a $<TARGET_FILE:hmi_editor>
                     --screenshot ${CMAKE_CURRENT_BINARY_DIR}/inv_Main_Inv1_xcb.png)
    set_tests_properties(inv_Main_Inv1_shortcutsBindAllStandardKeys_xcb PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=xcb"
        PASS_REGULAR_EXPRESSION "\\[screenshot\\]"
        # xcb 系ライブラリや xauth が無い環境では、試験できないので SKIP にする
        SKIP_REGULAR_EXPRESSION "Could not load the Qt platform plugin;no Qt platform plugin could be initialized;xauth command not found"
        FAIL_REGULAR_EXPRESSION "Only binding to one of multiple key bindings")
endif()

# V1-6: `--version` がルート CMake の project(VERSION) を出すことを確かめる
# （契約 Editor_main_main_Post1）。QGuiApplication を作るので offscreen で起動する。
add_test(NAME post_Editor_main_main_Post1_printsProjectVersion
         COMMAND $<TARGET_FILE:hmi_editor> --version)
set_tests_properties(post_Editor_main_main_Post1_printsProjectVersion PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_COMMAND_LINE_PARSER_NO_GUI_MESSAGE_BOXES=1"
    PASS_REGULAR_EXPRESSION "hmi_editor ${PROJECT_VERSION}")
