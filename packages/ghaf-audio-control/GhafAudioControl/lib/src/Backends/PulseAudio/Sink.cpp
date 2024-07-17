/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/Backends/PulseAudio/Sink.hpp>

#include <GhafAudioControl/Backends/PulseAudio/Helpers.hpp>
#include <GhafAudioControl/Backends/PulseAudio/Volume.hpp>

#include <format>

namespace ghaf::AudioControl::Backend::PulseAudio
{

Sink::Sink(const pa_sink_info& info, pa_context& context)
    : m_device(info, context)
{
}

bool Sink::operator==(const IDevice& other) const
{
    if (const Sink* otherSink = dynamic_cast<const Sink*>(&other))
        return m_device == otherSink->m_device;

    return false;
}

void Sink::setMuted(bool mute)
{
    ExecutePulseFunc(pa_context_set_sink_mute_by_index, &m_device.getContext(), m_device.getIndex(), mute, nullptr, nullptr);
}

void Sink::setVolume(Volume volume)
{
    pa_cvolume paChannelVolume;
    std::ignore = pa_cvolume_set(&paChannelVolume, m_device.getPulseChannelVolume().channels, ToPulseAudioVolume(volume));

    ExecutePulseFunc(pa_context_set_sink_volume_by_index, &m_device.getContext(), m_device.getIndex(), &paChannelVolume, nullptr, nullptr);
}

std::string Sink::toString() const
{
    return std::format("PulseSink: [ {} ]", m_device.toString());
}

} // namespace ghaf::AudioControl::Backend::PulseAudio
