/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <GhafAudioControl/IAudioControlBackend.hpp>
#include <GhafAudioControl/utils/ConnectionContainer.hpp>
#include <GhafAudioControl/utils/ScopeExit.hpp>

#include <glibmm/object.h>
#include <glibmm/property.h>

namespace ghaf::AudioControl
{

class AppRaw final : public Glib::Object
{
public:
    using AppIdType = uint32_t;

private:
    AppRaw(AppIdType id, IAudioControlBackend::ISink::Ptr sink, IAudioControlBackend::ISource::Ptr source);

public:
    static Glib::RefPtr<AppRaw> create(AppIdType id, IAudioControlBackend::ISink::Ptr sink, IAudioControlBackend::ISource::Ptr source);

    static int compare(const Glib::RefPtr<const AppRaw>& a, const Glib::RefPtr<const AppRaw>& b);

    [[nodiscard]] AppIdType getId() const noexcept
    {
        return m_id;
    }

    void updateSink(IAudioControlBackend::ISink::Ptr sink);
    void updateSource(IAudioControlBackend::ISource::Ptr source);

    [[nodiscard]] auto getIsEnabledProperty() const
    {
        return m_isEnabled.get_proxy();
    }

    [[nodiscard]] auto getHasSinkProperty() const
    {
        return m_hasSink.get_proxy();
    }

    [[nodiscard]] auto getHasSourceProperty() const
    {
        return m_hasSource.get_proxy();
    }

    [[nodiscard]] auto getAppNameProperty() const
    {
        return m_appName.get_proxy();
    }

    [[nodiscard]] auto getIconUrlProperty() const
    {
        return m_iconUrl.get_proxy();
    }

    [[nodiscard]] auto getSoundEnabledProperty()
    {
        return m_isSoundEnabled.get_proxy();
    }

    [[nodiscard]] auto getSoundVolumeProperty()
    {
        return m_soundVolume.get_proxy();
    }

    [[nodiscard]] auto getMicroEnabledProperty()
    {
        return m_isMicroEnabled.get_proxy();
    }

    [[nodiscard]] auto getMicroVolumeProperty()
    {
        return m_microVolume.get_proxy();
    }

private:
    [[nodiscard]] bool sendSinkVolume();

    void onSoundEnabledChange();
    void onSoundVolumeChange();

    void onMicroEnabledChange();
    void onMicroVolumeChange();

private:
    const AppIdType m_id;
    IAudioControlBackend::ISink::Ptr m_sink;
    IAudioControlBackend::ISource::Ptr m_source;

    Glib::Property<bool> m_isEnabled{*this, "m_isEnabled", false};

    Glib::Property<bool> m_hasSink{*this, "m_hasSink", false};
    Glib::Property<bool> m_hasSource{*this, "m_hasSource", false};

    Glib::Property_ReadOnly<Glib::ustring> m_iconUrl{*this, "m_iconUrl", "/usr/share/pixmaps/ubuntu-logo.svg"};
    Glib::Property<Glib::ustring> m_appName;

    Glib::Property<bool> m_isSoundEnabled{*this, "m_isSoundEnabled", false};
    Glib::Property<double> m_soundVolume{*this, "m_soundVolume", 0};

    Glib::Property<bool> m_isMicroEnabled{*this, "m_isMicroEnabled", false};
    Glib::Property<double> m_microVolume{*this, "m_microVolume", 0};

    ConnectionContainer m_connections;
};

} // namespace ghaf::AudioControl
