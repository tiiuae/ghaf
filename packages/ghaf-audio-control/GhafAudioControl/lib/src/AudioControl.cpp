/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/AudioControl.hpp>

#include <GhafAudioControl/Backends/PulseAudio/AudioControlBackend.hpp>
#include <GhafAudioControl/utils/Logger.hpp>

#include <gtkmm/grid.h>
#include <gtkmm/image.h>
#include <gtkmm/scale.h>
#include <gtkmm/switch.h>
#include <gtkmm/volumebutton.h>

#include <glibmm/binding.h>

#include <format>

namespace ghaf::AudioControl
{

AudioControl::AudioControl(std::unique_ptr<IAudioControlBackend> backend)
    : Gtk::Box(Gtk::ORIENTATION_HORIZONTAL)
    , m_audioControl(std::move(backend))
{
    init();
}

void AudioControl::init()
{
    if (m_audioControl)
    {
        pack_start(m_appList);

        m_connections.add(m_audioControl->onSinksChanged().connect(sigc::mem_fun(*this, &AudioControl::onPulseSinksChanged)));
        m_connections.add(m_audioControl->onSourcesChanged().connect(sigc::mem_fun(*this, &AudioControl::onPulseSourcesChanged)));
        m_connections.add(m_audioControl->onError().connect(sigc::mem_fun(*this, &AudioControl::onPulseError)));

        show_all_children();

        m_audioControl->start();
    }
    else
    {
        onPulseError("No audio backend");
    }
}

void AudioControl::onPulseSinksChanged(IAudioControlBackend::EventType eventType, IAudioControlBackend::Sinks::IndexT index,
                                       IAudioControlBackend::Sinks::PtrT sink)
{
    switch (eventType)
    {
    case IAudioControlBackend::EventType::Add:
        Logger::debug(std::format("onPulseSinksChanged: ADD sink: {}", sink->toString()));
        m_appList.addApp(index, std::move(sink), nullptr);
        break;

    case IAudioControlBackend::EventType::Update:
        Logger::debug(std::format("onPulseSinksChanged: UPDATE sink: {}", sink->toString()));
        m_appList.updateApp(index, std::move(sink), nullptr);
        break;

    case IAudioControlBackend::EventType::Delete:
        Logger::debug(std::format("onPulseSinksChanged: DELETE sink with index: {}", index));
        m_appList.removeApp(index);
        break;
    }

    show_all_children();
}

void AudioControl::onPulseSourcesChanged(IAudioControlBackend::EventType eventType, IAudioControlBackend::Sources::IndexT index,
                                         IAudioControlBackend::Sources::PtrT source)
{
    // Disable sources for now
    return;

    switch (eventType)
    {
    case IAudioControlBackend::EventType::Add:
        Logger::debug(std::format("onPulseSourcesChanged: ADD source: {}", source->toString()));
        m_appList.addApp(index, nullptr, std::move(source));
        break;

    case IAudioControlBackend::EventType::Update:
        Logger::debug(std::format("onPulseSourcesChanged: UPDATE source: {}", source->toString()));
        m_appList.updateApp(index, nullptr, std::move(source));
        break;

    case IAudioControlBackend::EventType::Delete:
        Logger::debug(std::format("onPulseSourcesChanged: DELETE source with index: {}", index));
        m_appList.removeApp(index);
        break;
    }
}

void AudioControl::onPulseError(std::string_view error)
{
    m_connections.clear();
    m_audioControl->stop();

    Logger::error(error);

    m_appList.removeAllApps();
    remove(m_appList);

    auto* errorLabel = Gtk::make_managed<Gtk::Label>();
    errorLabel->set_label(error.data());
    errorLabel->show_all();

    pack_start(*errorLabel);

    show_all_children();
}

} // namespace ghaf::AudioControl
