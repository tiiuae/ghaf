# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.5)

project(GhafAudioControl LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "-Wall -Wextra -fPIE")
set(EXECUTABLE_OUTPUT_PATH build/)
set(CMAKE_INSTALL_PREFIX ${CMAKE_BINARY_DIR}/install/)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

#set(CMAKE_CXX_FLAGS_DEBUG -fsanitize=address)
# set(CMAKE_CXX_FLAGS_DEBUG -fsanitize=undefined)
#set(CMAKE_CXX_FLAGS_DEBUG -fsanitize=thread)

#add_definitions(-DLIBCXX_HARDENING_MODE=debug)
#add_compile_options(-fsanitize=address -fsanitize-recover=all)
#add_link_options(-fsanitize=address -fsanitize-recover=all)

add_subdirectory(app)
add_subdirectory(lib)

