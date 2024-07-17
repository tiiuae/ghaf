/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <functional>

namespace ghaf::AudioControl
{

class ScopeExit
{
public:
    using Deleter = std::function<void()>;

    ScopeExit(Deleter&& exit_function)
        : m_deleter{std::move(exit_function)}
    {
    }

    ScopeExit(const ScopeExit&) = delete;
    ScopeExit(ScopeExit&&) = default;

    ScopeExit& operator=(const ScopeExit&) = delete;
    ScopeExit& operator=(ScopeExit&&) = default;

    ~ScopeExit()
    {
        try
        {
            m_deleter();
        }
        catch (...)
        {
        }
    }

private:
    Deleter m_deleter;
};

} // namespace ghaf::AudioControl
