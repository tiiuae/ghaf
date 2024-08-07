/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <GhafAudioControl/Volume.hpp>

#include <pulse/volume.h>

namespace ghaf::AudioControl::Backend::PulseAudio
{

[[nodiscard]] pa_volume_t ToPulseAudioVolume(Volume volume) noexcept;
[[nodiscard]] Volume FromPulseAudioVolume(pa_volume_t pulseVolume) noexcept(false);

} // namespace ghaf::AudioControl::Backend::PulseAudio
