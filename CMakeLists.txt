cmake_minimum_required(VERSION 3.21)
project(hmi_platform LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_standard_project_setup(REQUIRES 6.5)

include(CTest)

# Qt6::Test / Qt6::QuickTest は BUILD_TESTING=ON のときだけ要求する。
# Yocto 等 Qt Test / QuickTest が同梱されていないクロス環境で
# BUILD_TESTING=OFF にしたとき configure が落ちないようにするため。
if(BUILD_TESTING)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test QuickTest)
endif()

add_subdirectory(Shared/Schema)
add_subdirectory(Shared/Widgets)
add_subdirectory(Editor)
add_subdirectory(Simulator)
