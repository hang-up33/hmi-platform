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
        # HmiWidgets QML モジュールの STATIC plugin。テスト QML 側で
        # "import HmiWidgets" を解決するために必須。Editor / Simulator と
        # 同じ運用（CLAUDE.md「共有 QML モジュールは STATIC でビルドし、利用側
        # アプリで plugin ターゲットをリンクする」）。
        hmi_widgetsplugin
)

# headless 環境（CI コンテナ等で DISPLAY が無い）でも実行できるよう
# -platform offscreen を明示する。macOS / Windows のローカル開発でも
# 正常に動作する（Qt の offscreen プラットフォームは Qt Quick をサポート）。
add_test(NAME tst_hmi_widgets_qml COMMAND tst_hmi_widgets_qml -platform offscreen)
