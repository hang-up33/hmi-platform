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
