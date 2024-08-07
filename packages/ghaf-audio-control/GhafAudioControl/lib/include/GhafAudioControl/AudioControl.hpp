/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <GhafAudioControl/AppList.hpp>
#include <GhafAudioControl/IAudioControlBackend.hpp>

#include <gtkmm/menubutton.h>
#include <gtkmm/popover.h>
#include <gtkmm/separator.h>
#include <gtkmm/stacksidebar.h>

#include <glibmm/refptr.h>

namespace ghaf::AudioControl
{

class AudioControl final : public Gtk::Box
{
public:
    static inline std::string ModuleName = "ghaf-audio-control";

    AudioControl(std::unique_ptr<IAudioControlBackend> backend);
    ~AudioControl() override = default;

    AudioControl(AudioControl&) = delete;
    AudioControl(AudioControl&&) = delete;

    AudioControl& opeartor(AudioControl&) = delete;
    AudioControl& opeartor(AudioControl&&) = delete;

private:
    void init();

    void onPulseSinksChanged(IAudioControlBackend::EventType eventType, IAudioControlBackend::Sinks::IndexT extIndex, IAudioControlBackend::Sinks::PtrT sink);
    void onPulseSourcesChanged(IAudioControlBackend::EventType eventType, IAudioControlBackend::Sinks::IndexT extIndex,
                               IAudioControlBackend::Sources::PtrT source);
    void onPulseError(std::string_view error);

private:
    AppList m_appList;
    std::unique_ptr<IAudioControlBackend> m_audioControl;

    ConnectionContainer m_connections;
};

} // namespace ghaf::AudioControl
