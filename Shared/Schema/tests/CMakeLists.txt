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
