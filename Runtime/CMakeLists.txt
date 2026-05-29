# Task 22: hmi_runtime バイナリは Simulator のソースを共有して生成する。
#
# CMake glue のみ：.cpp / .qml / .h は Simulator/ にのみ存在し、
# ここでは Simulator 側で定義した共通 function
# `hmi_add_simulator_like_executable` を呼ぶだけ。
#
# Yocto SDK でクロスビルドする時も `cmake --build <dir> --target hmi_runtime`
# で同じターゲットを build する想定。詳細は Docs/phase3b-runtime-plan.md。
hmi_add_simulator_like_executable(hmi_runtime)
