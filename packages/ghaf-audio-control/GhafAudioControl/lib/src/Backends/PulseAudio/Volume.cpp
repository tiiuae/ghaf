/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/Backends/PulseAudio/Volume.hpp>

#include <cmath>

namespace ghaf::AudioControl::Backend::PulseAudio
{

pa_volume_t ToPulseAudioVolume(Volume volume) noexcept
{
    const double coeff = volume.getPercents() / static_cast<double>(Volume::Max);
    return PA_VOLUME_NORM * coeff;
}

Volume FromPulseAudioVolume(pa_volume_t pulseVolume) noexcept(false)
{
    return Volume::fromPercents(std::round((pulseVolume * Volume::Max) / (double)PA_VOLUME_NORM));
}

} // namespace ghaf::AudioControl::Backend::PulseAudio
