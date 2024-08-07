/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/utils/Logger.hpp>

#include <iostream>

namespace ghaf::AudioControl
{

void Logger::log(std::string_view message)
{
    std::cerr << message << '\n';
}

} // namespace ghaf::AudioControl
