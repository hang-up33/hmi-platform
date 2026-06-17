add_executable(tst_smoke tst_smoke.cpp)

target_link_libraries(tst_smoke
    PRIVATE
        Qt6::Test
)

add_test(NAME tst_smoke COMMAND tst_smoke)

add_executable(tst_widget_data tst_widget_data.cpp)
target_link_libraries(tst_widget_data
    PRIVATE
        Qt6::Test
        hmi_schema
)
add_test(NAME tst_widget_data COMMAND tst_widget_data)

add_executable(tst_screen_data tst_screen_data.cpp)
target_link_libraries(tst_screen_data
    PRIVATE
        Qt6::Test
        hmi_schema
)
add_test(NAME tst_screen_data COMMAND tst_screen_data)

add_executable(tst_project_data tst_project_data.cpp)
target_link_libraries(tst_project_data
    PRIVATE
        Qt6::Test
        hmi_schema
)
add_test(NAME tst_project_data COMMAND tst_project_data)

# Task 39: 変数 / アクション / バインディングの新スキーマ型
add_executable(tst_variable_data tst_variable_data.cpp)
target_link_libraries(tst_variable_data
    PRIVATE
        Qt6::Test
        hmi_schema
)
add_test(NAME tst_variable_data COMMAND tst_variable_data)

# Task 8B-A（Phase 8-B）: Trend 系列の子型 TrendSeriesData
add_executable(tst_trend_series_data tst_trend_series_data.cpp)
target_link_libraries(tst_trend_series_data
    PRIVATE
        Qt6::Test
        hmi_schema
)
add_test(NAME tst_trend_series_data COMMAND tst_trend_series_data)
