/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/Backends/PulseAudio/GeneralDevice.hpp>

#include <GhafAudioControl/Backends/PulseAudio/Volume.hpp>

#include <format>

namespace ghaf::AudioControl::Backend::PulseAudio
{

GeneralDeviceImpl::GeneralDeviceImpl(const pa_sink_info& info, pa_context& context)
    : m_index(info.index)
    , m_cardIndex(info.card)
    , m_name(info.name)
    , m_description(info.description)
    , m_context(context)
    , m_channel_map(info.channel_map)
    , m_volume(info.volume)
    , m_isMuted(static_cast<bool>(info.mute))
{
}

GeneralDeviceImpl::GeneralDeviceImpl(const pa_source_info& info, pa_context& context)
    : m_index(info.index)
    , m_cardIndex(info.card)
    , m_name(info.name)
    , m_description(info.description)
    , m_context(context)
    , m_channel_map(info.channel_map)
    , m_volume(info.volume)
    , m_isMuted(static_cast<bool>(info.mute))
{
}

[[nodiscard]] uint32_t GeneralDeviceImpl::getCardIndex() const noexcept
{
    const std::lock_guard l{m_mutex};
    return m_cardIndex;
}

[[nodiscard]] bool GeneralDeviceImpl::isEnabled() const noexcept
{
    const std::lock_guard l{m_mutex};
    return m_isEnabled;
}

[[nodiscard]] bool GeneralDeviceImpl::isMuted() const
{
    const std::lock_guard l{m_mutex};
    return m_isMuted;
}

[[nodiscard]] Volume GeneralDeviceImpl::getVolume() const
{
    return FromPulseAudioVolume(getPulseVolume());
}

[[nodiscard]] pa_volume_t GeneralDeviceImpl::getPulseVolume() const
{
    const std::lock_guard l{m_mutex};
    return m_volume.values[0];
}

[[nodiscard]] pa_cvolume GeneralDeviceImpl::getPulseChannelVolume() const noexcept
{
    const std::lock_guard l{m_mutex};
    return m_volume;
}

[[nodiscard]] std::string GeneralDeviceImpl::getName() const
{
    const std::lock_guard l{m_mutex};
    return std::format("#{}. {}", m_index, m_description);
}

[[nodiscard]] std::string GeneralDeviceImpl::toString() const
{
    const std::lock_guard l{m_mutex};
    return std::format("index: {}, name: {}, volume: {}, isMuted: {}", m_index, m_description, m_volume.values[0], m_isMuted);
}

[[nodiscard]] std::string GeneralDeviceImpl::getDescription() const
{
    const std::lock_guard l{m_mutex};
    return m_description;
}

void GeneralDeviceImpl::update(const pa_sink_info& info)
{
    {
        const std::lock_guard l{m_mutex};

        m_cardIndex = info.card;
        m_name = info.name;
        m_description = info.description;
        m_channel_map = info.channel_map;
        m_volume = info.volume;
        m_isMuted = static_cast<bool>(info.mute);
    }

    m_onChanged();
}

void GeneralDeviceImpl::update(const pa_source_info& info)
{
    {
        const std::lock_guard l{m_mutex};

        m_cardIndex = info.card;
        m_name = info.name;
        m_description = info.description;
        m_channel_map = info.channel_map;
        m_volume = info.volume;
        m_isMuted = static_cast<bool>(info.mute);
    }

    m_onChanged();
}

void GeneralDeviceImpl::update(const pa_card_info& info)
{
    {
        const std::lock_guard l{m_mutex};

        m_isEnabled = false;

        if (m_cardIndex == info.index)
        {
            for (size_t i = 0; i < info.n_ports; ++i)
            {
                pa_card_port_info const* port = info.ports[i];

                if (m_description == port->description && port->available == PA_PORT_AVAILABLE_YES)
                {
                    m_isEnabled = true;
                    break;
                }
            }
        }
    }

    m_onChanged();
}

} // namespace ghaf::AudioControl::Backend::PulseAudio
