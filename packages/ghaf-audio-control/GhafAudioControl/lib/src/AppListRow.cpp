/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/AppListRow.hpp>

#include <GhafAudioControl/utils/Logger.hpp>

#include <glibmm/main.h>

#include <format>

namespace ghaf::AudioControl
{

namespace
{

template<class T>
void LazySet(Glib::Property<T>& property, const typename Glib::Property<T>::PropertyType& newValue)
{
    if (property == newValue)
        return;

    property = newValue;
}

} // namespace

AppRaw::AppRaw(AppIdType id, IAudioControlBackend::ISink::Ptr sink, IAudioControlBackend::ISource::Ptr source)
    : Glib::ObjectBase(typeid(AppRaw))
    , m_id(id)
    , m_appName(*this, "m_appName", "Undefined")
    , m_connections{m_isSoundEnabled.get_proxy().signal_changed().connect(sigc::mem_fun(*this, &AppRaw::onSoundEnabledChange)),
                    m_isMicroEnabled.get_proxy().signal_changed().connect(sigc::mem_fun(*this, &AppRaw::onMicroEnabledChange)),

                    m_soundVolume.get_proxy().signal_changed().connect(sigc::mem_fun(*this, &AppRaw::onSoundVolumeChange)),
                    m_microVolume.get_proxy().signal_changed().connect(sigc::mem_fun(*this, &AppRaw::onMicroVolumeChange))}
{
    updateSink(std::move(sink));
    updateSource(std::move(source));
}

Glib::RefPtr<AppRaw> AppRaw::create(AppIdType id, IAudioControlBackend::IDevice::Ptr sink, IAudioControlBackend::IDevice::Ptr source)
{
    return Glib::RefPtr<AppRaw>(new AppRaw(id, std::move(sink), std::move(source)));
}

int AppRaw::compare(const Glib::RefPtr<const AppRaw>& a, const Glib::RefPtr<const AppRaw>& b)
{
    if (!a || !b)
        return 0;

    return a->m_appName.get_value().compare(b->m_appName.get_value());
}

void AppRaw::updateSink(IAudioControlBackend::ISink::Ptr sink)
{
    {
        const auto scopeExit = m_connections.blockGuarded();

        LazySet(m_isSoundEnabled, sink ? !sink->isMuted() : false);
        LazySet(m_soundVolume, sink ? sink->getVolume().getPercents() : 0);
    }

    m_isEnabled = (sink ? sink->isEnabled() : false) || (m_source ? m_source->isEnabled() : false);

    if (sink)
        LazySet(m_appName, "sink: " + sink->getName() + (m_isEnabled ? " enabled" : " disabled"));

    m_sink = std::move(sink);
    m_hasSink = m_sink != nullptr;
}

void AppRaw::updateSource(IAudioControlBackend::ISource::Ptr source)
{
    {
        const auto scopeExit = m_connections.blockGuarded();

        LazySet(m_isMicroEnabled, source ? !source->isMuted() : false);
        LazySet(m_microVolume, source ? source->getVolume().getPercents() : 0);
    }

    if (source)
        LazySet(m_appName, "source: " + source->getName() + (m_isEnabled ? " enabled" : " disabled"));

    m_isEnabled = (m_sink ? m_sink->isEnabled() : false) || (source ? source->isEnabled() : false);
    m_source = std::move(source);
    m_hasSource = m_source != nullptr;
}

bool AppRaw::sendSinkVolume()
{
    Logger::debug(std::format("SoundVolume has changed to: {0}", m_soundVolume.get_value()));

    if (m_sink)
        m_sink->setVolume(Volume::fromPercents(m_soundVolume.get_value()));

    return true;
}

void AppRaw::onSoundEnabledChange()
{
    const auto isEnabled = m_isSoundEnabled.get_value();

    Logger::debug(std::format("SoundEnabled has changed to: {0}", isEnabled));

    if (m_sink)
        m_sink->setMuted(!isEnabled);
}

void AppRaw::onSoundVolumeChange()
{
    sendSinkVolume();
    // if (m_sinkUpdateConnection)
    // m_sinkUpdateConnection.disconnect();

    // const sigc::slot<bool> slot = sigc::mem_fun(*this, &AppRaw::sendSinkVolume);
    // m_sinkUpdateConnection = Glib::signal_timeout().connect(slot, 200);
}

void AppRaw::onMicroEnabledChange()
{
    const auto isEnabled = m_isMicroEnabled.get_value();

    Logger::debug(std::format("MicroEnabled has changed to: {0}", isEnabled));

    if (m_source)
        m_source->setMuted(!isEnabled);
    // if (!isEnabled)
    // lazySet(m_microVolume, 0);
}

void AppRaw::onMicroVolumeChange()
{
    Logger::debug(std::format("MicroVolume has changed to: {0}", m_microVolume.get_value()));

    if (m_source)
        m_source->setVolume(Volume::fromPercents(m_microVolume.get_value()));
}

} // namespace ghaf::AudioControl
