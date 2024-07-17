/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <GhafAudioControl/Volume.hpp>
#include <GhafAudioControl/utils/Logger.hpp>
#include <GhafAudioControl/utils/RaiiWrap.hpp>

#include <pulse/context.h>
#include <pulse/volume.h>

#include <string_view>

#define DEBUG 1

namespace ghaf::AudioControl::Backend::PulseAudio
{

template<class Fx, class... ArgsT>
void ExecutePulseFuncPrivate(Fx fx, ArgsT... args)
{
    RaiiWrap<pa_operation*> wrap{[fx, args...](pa_operation*& op)
                                 {
                                     if (op = fx(args...); op == nullptr)
                                         Logger::error("Pulseaudio function failed");
                                 },
                                 [](pa_operation*& op)
                                 {
                                     pa_operation_unref(op);
                                 }};
}

#if defined(DEBUG)
    #define ExecutePulseFunc(FX, ARGS...)                            \
        {                                                            \
            Logger::debug(std::format("ExecutePulseFunc: {}", #FX)); \
            ExecutePulseFuncPrivate(FX, ARGS);                       \
        }
#else
template<class Fx, class... ArgsT>
void ExecutePulseFunc(Fx fx, ArgsT&&... args)
{
    ExecutePulseFuncPrivate(fx, args...);
}
#endif

bool PulseCallbackCheck(const pa_context* context, int eol, std::string_view callbackName);

} // namespace ghaf::AudioControl::Backend::PulseAudio
