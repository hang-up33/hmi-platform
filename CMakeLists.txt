cmake_minimum_required(VERSION 3.21)
project(hmi_platform LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_standard_project_setup(REQUIRES 6.5)

add_subdirectory(Shared/Schema)
add_subdirectory(Shared/Widgets)
add_subdirectory(Editor)
add_subdirectory(Simulator)
