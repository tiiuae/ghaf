/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <GhafAudioControl/Backends/PulseAudio/GeneralDevice.hpp>
#include <GhafAudioControl/IAudioControlBackend.hpp>

#include <pulse/context.h>
#include <pulse/introspect.h>

namespace ghaf::AudioControl::Backend::PulseAudio
{

class Source final : public IAudioControlBackend::ISource
{
public:
    Source(const pa_source_info& info, pa_context& context);

    bool operator==(const IDevice& other) const override;

    std::string getName() const override
    {
        return m_device.getName();
    }

    bool isEnabled() const override
    {
        return m_device.isEnabled();
    }

    bool isMuted() const override
    {
        return m_device.isMuted();
    }

    void setMuted(bool mute) override;

    Volume getVolume() const override
    {
        return m_device.getVolume();
    }

    void setVolume(Volume volume) override;

    std::string toString() const override;

    std::string getDescription() const
    {
        return m_device.getDescription();
    }

    uint32_t getCardIndex() const noexcept
    {
        return m_device.getCardIndex();
    }

    void update(const pa_source_info& info)
    {
        m_device.update(info);
    }

    void update(const pa_card_info& info)
    {
        m_device.update(info);
    }

private:
    GeneralDeviceImpl m_device;
};

} // namespace ghaf::AudioControl::Backend::PulseAudio
