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
