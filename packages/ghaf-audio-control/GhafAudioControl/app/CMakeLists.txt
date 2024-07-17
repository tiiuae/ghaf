# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.5)

project(GhafAudioControlStandalone LANGUAGES CXX)

add_executable(GhafAudioControlStandalone main.cpp)
target_link_libraries(GhafAudioControlStandalone GhafAudioControl)

include(GNUInstallDirs)
install(TARGETS ${PROJECT_NAME})
