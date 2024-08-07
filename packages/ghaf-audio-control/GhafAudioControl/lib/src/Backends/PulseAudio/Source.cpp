/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/Backends/PulseAudio/Source.hpp>

#include <GhafAudioControl/Backends/PulseAudio/Helpers.hpp>
#include <GhafAudioControl/Backends/PulseAudio/Volume.hpp>

#include <format>

namespace ghaf::AudioControl::Backend::PulseAudio
{

Source::Source(const pa_source_info& info, pa_context& context)
    : m_device(info, context)
{
}

bool Source::operator==(const IDevice& other) const
{
    if (const auto* otherSource = dynamic_cast<const Source*>(&other))
        return m_device == otherSource->m_device;

    return false;
}

void Source::setMuted(bool mute)
{
    ExecutePulseFunc(pa_context_set_sink_mute_by_index, &m_device.getContext(), m_device.getIndex(), mute, nullptr, nullptr);
}

void Source::setVolume(Volume volume)
{
    pa_cvolume paChannelVolume;
    std::ignore = pa_cvolume_set(&paChannelVolume, m_device.getPulseChannelVolume().channels, ToPulseAudioVolume(volume));

    ExecutePulseFunc(pa_context_set_source_volume_by_index, &m_device.getContext(), m_device.getIndex(), &paChannelVolume, nullptr, nullptr);
}

std::string Source::toString() const
{
    return std::format("PulseSource: [ {} ]", m_device.toString());
}

} // namespace ghaf::AudioControl::Backend::PulseAudio
