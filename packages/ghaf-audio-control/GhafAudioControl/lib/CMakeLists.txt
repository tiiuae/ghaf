# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.5)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTKMM REQUIRED gtkmm-3.0)

find_package(PulseAudio REQUIRED)

set(LIBRARY_NAME GhafAudioControl)

add_library(${LIBRARY_NAME})

target_sources(${LIBRARY_NAME}
PRIVATE
    src/Backends/PulseAudio/AudioControlBackend.cpp
    src/Backends/PulseAudio/GeneralDevide.cpp
    src/Backends/PulseAudio/Helpers.cpp
    src/Backends/PulseAudio/Sink.cpp
    src/Backends/PulseAudio/Source.cpp
    src/Backends/PulseAudio/Volume.cpp

    src/utils/ConnectionContainer.cpp
    src/utils/Logger.cpp

    src/AppList.cpp
    src/AppListRow.cpp
    src/AudioControl.cpp

PUBLIC
    FILE_SET public_headers
    TYPE HEADERS
    BASE_DIRS include
    FILES
        include/GhafAudioControl/Backends/PulseAudio/AudioControlBackend.hpp
        include/GhafAudioControl/Backends/PulseAudio/GeneralDevice.hpp
        include/GhafAudioControl/Backends/PulseAudio/Helpers.hpp
        include/GhafAudioControl/Backends/PulseAudio/Sink.hpp
        include/GhafAudioControl/Backends/PulseAudio/Source.hpp
        include/GhafAudioControl/Backends/PulseAudio/Volume.hpp

        include/GhafAudioControl/utils/ConnectionContainer.hpp
        include/GhafAudioControl/utils/Logger.hpp
        include/GhafAudioControl/utils/RaiiWrap.hpp
        include/GhafAudioControl/utils/ScopeExit.hpp

        include/GhafAudioControl/AppList.hpp
        include/GhafAudioControl/AppListRow.hpp
        include/GhafAudioControl/AudioControl.hpp
        include/GhafAudioControl/IAudioControlBackend.hpp

        include/GhafAudioControl/Volume.hpp
)

target_link_libraries(
    ${LIBRARY_NAME}
    PUBLIC
        ${GTKMM_LIBRARIES}
    PRIVATE
        ${PULSEAUDIO_LIBRARY}
        ${PULSEAUDIO_MAINLOOP_LIBRARY}
)

target_link_directories(
    ${LIBRARY_NAME}
    PUBLIC
        ${GTKMM_LIBRARY_DIR}
    PRIVATE
        ${PULSEAUDIO_INCLUDE_DIR}
)

target_include_directories(
    ${LIBRARY_NAME} PUBLIC
    ${GTKMM_INCLUDE_DIRS}
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
    "$<INSTALL_INTERFACE:$<INSTALL_PREFIX>/${CMAKE_INSTALL_INCLUDEDIR}>"
    PRIVATE ${PulseAudio_INCLUDE_DIRS}
)

include(GNUInstallDirs)
install(
    TARGETS       ${LIBRARY_NAME}
    LIBRARY       DESTINATION ${CMAKE_INSTALL_LIBDIR}
    ARCHIVE       DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME       DESTINATION ${CMAKE_INSTALL_BINDIR}
    FILE_SET      public_headers
)
