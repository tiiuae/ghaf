/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/Backends/PulseAudio/AudioControlBackend.hpp>

#include <GhafAudioControl/Backends/PulseAudio/Helpers.hpp>

#include <GhafAudioControl/Backends/PulseAudio/Sink.hpp>
#include <GhafAudioControl/Backends/PulseAudio/Source.hpp>

#include <GhafAudioControl/utils/Logger.hpp>

#include <pulse/error.h>
#include <pulse/glib-mainloop.h>
#include <pulse/introspect.h>
#include <pulse/subscribe.h>

#include <glibmm/main.h>

#include <format>

namespace ghaf::AudioControl::Backend::PulseAudio
{

namespace
{

constexpr pa_subscription_mask GetSubscriptionMask(auto... masks)
{
    return static_cast<pa_subscription_mask>((masks | ...));
}

constexpr pa_subscription_mask SubscriptionMask = GetSubscriptionMask(pa_subscription_mask::PA_SUBSCRIPTION_MASK_SERVER,
                                                                      pa_subscription_mask::PA_SUBSCRIPTION_MASK_SINK,
                                                                      pa_subscription_mask::PA_SUBSCRIPTION_MASK_SINK_INPUT,
                                                                      pa_subscription_mask::PA_SUBSCRIPTION_MASK_SOURCE,
                                                                      pa_subscription_mask::PA_SUBSCRIPTION_MASK_SOURCE_OUTPUT,
                                                                      pa_subscription_mask::PA_SUBSCRIPTION_MASK_CARD);

[[nodiscard]] RaiiWrap<pa_glib_mainloop*> InitMainloop()
{
    return {[](pa_glib_mainloop*& mainloop)
            {
                if (mainloop = pa_glib_mainloop_new(Glib::MainContext::get_default().get()->gobj()); mainloop == nullptr)
                    throw std::runtime_error("pa_glib_mainloop_new() failed.");
            },
            [](pa_glib_mainloop*& mainloop)
            {
                pa_glib_mainloop_free(mainloop);
            }};
}

[[nodiscard]] RaiiWrap<pa_mainloop_api*> InitApi(pa_glib_mainloop& mainloop)
{
    return {[&mainloop](pa_mainloop_api*& api)
            {
                if (api = pa_glib_mainloop_get_api(&mainloop); api == nullptr)
                    throw std::runtime_error("pa_glib_mainloop_get_api() failed.");
            },
            RaiiWrap<pa_mainloop_api*>::Destructor()};
}

[[nodiscard]] RaiiWrap<pa_context*> InitContext(pa_mainloop_api& api, pa_context_notify_cb_t contextCallback, AudioControlBackend& self)
{
    const auto constructor = [&api, &contextCallback, &self](pa_context*& context)
    {
        const auto propListConstructor = [](pa_proplist*& proplist)
        {
            proplist = pa_proplist_new();
            std::ignore = pa_proplist_sets(proplist, PA_PROP_APPLICATION_NAME, "Ghaf Audio Control");
            std::ignore = pa_proplist_sets(proplist, PA_PROP_APPLICATION_ID, "org.ghaf.audiocontrol");
            std::ignore = pa_proplist_sets(proplist, PA_PROP_APPLICATION_ICON_NAME, "audio-card");
        };

        const auto propListDestructor = [](pa_proplist*& proplist)
        {
            pa_proplist_free(proplist);
        };

        const RaiiWrap<pa_proplist*> propList(propListConstructor, propListDestructor);

        if (context = pa_context_new_with_proplist(&api, "GhafAudioControl", propList); context == nullptr)
            throw std::runtime_error("pa_context_new_with_proplist() failed.");

        pa_context_set_state_callback(context, contextCallback, &self);

        if (auto& server = self.getServerAddress(); pa_context_connect(context, server.empty() ? nullptr : server.c_str(), PA_CONTEXT_NOFAIL, nullptr) < 0)
            throw std::runtime_error(std::format("pa_context_connect() failed: {}", pa_strerror(pa_context_errno(context))));
    };

    const auto destructor = [](pa_context*& context)
    {
        pa_context_disconnect(context);
    };

    return {constructor, destructor};
}

} // namespace

AudioControlBackend::AudioControlBackend(std::string pulseAudioServerAddress)
    : m_serverAddress(std::move(pulseAudioServerAddress))
    , m_mainloop(InitMainloop())
    , m_mainloopApi(InitApi(*m_mainloop))
{
}

void AudioControlBackend::start()
{
    Logger::info(std::format("PulseAudio::AudioControlBackend: starting with server: {}", m_serverAddress));
    m_context = InitContext(*m_mainloopApi, contextStateCallback, *this);
}

void AudioControlBackend::stop()
{
    m_context.reset();
}

void AudioControlBackend::onSinkInfo(const pa_sink_info& info)
{
    const Index index = info.index;

    if (auto sinkIt = m_sinks.findByKey(index))
    {
        const ISink& sink = *sinkIt.value()->second;

        Logger::debug(std::format("Updating... Before: {}", sink.toString()));
        m_sinks.update(*sinkIt, [&info](ISink& sink) { dynamic_cast<Sink&>(sink).update(info); });
        Logger::debug(std::format("Updating... After: {}", sink.toString()));
    }
    else
    {
        m_sinks.add(index, std::make_shared<Sink>(info, *m_context->get()));
    }
}

void AudioControlBackend::deleteSink(Sinks::IndexT index)
{
    if (auto sinkIt = m_sinks.findByKey(index))
    {
        Logger::debug(std::format("AudioControlBackend::deleteSink: delete sink with id: {}", index));
        m_sinks.remove(*sinkIt);
    }
    else
        Logger::error(std::format("AudioControlBackend::deleteSink: no sink with id: {}", index));
}

void AudioControlBackend::onSourceInfo(const pa_source_info& info)
{
    const Index index = info.index;

    if (auto sourceIt = m_sources.findByKey(index))
    {
        m_sources.update(*sourceIt, [&info](ISource& source) { dynamic_cast<Source&>(source).update(info); });
    }
    else
    {
        m_sources.add(index, std::make_shared<Source>(info, *m_context->get()));
    }
}

void AudioControlBackend::deleteSource(Sources::IndexT index)
{
    if (auto sourceIt = m_sources.findByKey(index))
    {
        Logger::debug(std::format("AudioControlBackend::deleteSource: delete source with id: {}", index));
        m_sources.remove(*sourceIt);
    }
    else
        Logger::error(std::format("AudioControlBackend::deleteSource: no source with id: {}", index));
}

void AudioControlBackend::subscribeCallback(pa_context* context, pa_subscription_event_type_t type, uint32_t index, void* data)
{
    auto* self = static_cast<AudioControlBackend*>(data);
    const bool needRemove = (type & pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_TYPE_MASK) == pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_REMOVE;
    const auto eventType = static_cast<pa_subscription_event_type>(type & pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_FACILITY_MASK);

    switch (eventType)
    {
    case pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_SERVER:
        ExecutePulseFunc(pa_context_get_server_info, context, serverInfoCallback, data);
        break;

    case pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_SINK:
        if (needRemove)
            self->deleteSink(index);
        else
            ExecutePulseFunc(pa_context_get_sink_info_by_index, context, index, sinkInfoCallback, data);

        break;

    case pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_SINK_INPUT:
        ExecutePulseFunc(pa_context_get_sink_info_list, context, sinkInfoCallback, data);
        break;

    case pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_SOURCE:
        if (needRemove)
            self->deleteSource(index);
        else
            ExecutePulseFunc(pa_context_get_source_info_by_index, context, index, sourceInfoCallback, data);

        break;

    case pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_SOURCE_OUTPUT:
        ExecutePulseFunc(pa_context_get_source_info_list, context, sourceInfoCallback, data);
        break;

    case pa_subscription_event_type::PA_SUBSCRIPTION_EVENT_CARD:
        ExecutePulseFunc(pa_context_get_card_info_by_index, context, index, cardInfoCallback, data);
        break;

    default:
        Logger::error(std::format("subscribeCallback: unknown eventType: {0}", static_cast<int>(eventType)));
        break;
    };
}

void AudioControlBackend::contextStateCallback(pa_context* context, void* data)
{
    auto* self = static_cast<AudioControlBackend*>(data);

    switch (const auto state = pa_context_get_state(context))
    {
    case pa_context_state_t::PA_CONTEXT_TERMINATED:
        self->m_onError("pa_context_state_t::PA_CONTEXT_TERMINATED");
        break;

    case pa_context_state_t::PA_CONTEXT_READY:
        ExecutePulseFunc(pa_context_get_server_info, context, serverInfoCallback, data);
        pa_context_set_subscribe_callback(context, subscribeCallback, data);
        ExecutePulseFunc(pa_context_subscribe, context, SubscriptionMask, nullptr, nullptr);
        break;

    case pa_context_state_t::PA_CONTEXT_FAILED:
        self->m_onError(std::format("Connection to the server '{}' has failed", self->getServerAddress()));
        // std::this_thread::sleep_for(1s);
        // self->m_context = InitContext(*self->m_mainloopApi, AudioControlBackend::contextStateCallback, *self);

        break;

    case pa_context_state_t::PA_CONTEXT_CONNECTING:
    case pa_context_state_t::PA_CONTEXT_AUTHORIZING:
    case pa_context_state_t::PA_CONTEXT_SETTING_NAME:
        break;

    default:
        Logger::error(std::format("contextStateCb: unknown state: {0}", static_cast<int>(state)));
        break;
    }
}

void AudioControlBackend::sinkInfoCallback(pa_context* context, const pa_sink_info* info, int eol, void* data)
{
    if (!PulseCallbackCheck(context, eol, __FUNCTION__) || info == nullptr)
        return;

    static_cast<AudioControlBackend*>(data)->onSinkInfo(*info);
}

void AudioControlBackend::sourceInfoCallback(pa_context* context, const pa_source_info* info, int eol, void* data)
{
    if (!PulseCallbackCheck(context, eol, __FUNCTION__) || info == nullptr)
        return;

    static_cast<AudioControlBackend*>(data)->onSourceInfo(*info);
}

void AudioControlBackend::serverInfoCallback(pa_context* context, const pa_server_info* info, void* data)
{
    if (info == nullptr)
        return;

    auto* self = static_cast<AudioControlBackend*>(data);
    self->m_defaultSinkName = info->default_sink_name;
    self->m_defaultSourceName = info->default_source_name;

    ExecutePulseFunc(pa_context_get_sink_info_list, context, sinkInfoCallback, data);
    ExecutePulseFunc(pa_context_get_source_info_list, context, sourceInfoCallback, data);
    ExecutePulseFunc(pa_context_get_card_info_list, context, cardInfoCallback, data);
}

void AudioControlBackend::cardInfoCallback(pa_context* context, const pa_card_info* info, int eol, void* data)
{
    if (!PulseCallbackCheck(context, eol, __FUNCTION__))
        return;

    if (info == nullptr)
        return;

    auto* self = static_cast<AudioControlBackend*>(data);

    auto sinkPredicate = [&info](const ISink& sink) -> bool
    {
        return dynamic_cast<const Sink&>(sink).getCardIndex() == info->index;
    };

    for (auto it : self->m_sinks.findByPredicate(sinkPredicate))
    {
        self->m_sinks.update(it, [&info](ISink& sink) { dynamic_cast<Sink&>(sink).update(*info); });
    }

    auto sourcePredicate = [&info](const ISource& source)
    {
        return dynamic_cast<const Source&>(source).getCardIndex() == info->index;
    };

    for (auto it : self->m_sources.findByPredicate(sourcePredicate))
    {
        self->m_sources.update(it, [&info](ISource& source) { dynamic_cast<Source&>(source).update(*info); });
    }
}

} // namespace ghaf::AudioControl::Backend::PulseAudio
