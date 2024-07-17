/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <functional>

namespace ghaf::AudioControl
{

template<class T>
class RaiiWrap final
{
public:
    using Functor = std::function<void(T&)>;
    using Constructor = Functor;
    using Destructor = Functor;

    RaiiWrap(Constructor constructor, Destructor destructor, T initValue = T())
        : m_destructor(destructor)
        , m_data(initValue)
    {
        constructor(m_data);
    }

    ~RaiiWrap()
    {
        try
        {
            m_destructor(m_data);

            if constexpr (std::is_pointer_v<T>)
                m_data = nullptr;
        }
        catch (...)
        {
        }
    }

    RaiiWrap(const RaiiWrap&) = delete;
    RaiiWrap(RaiiWrap&&) = default;

    RaiiWrap& operator=(const RaiiWrap&) = delete;
    RaiiWrap& operator=(RaiiWrap&&) = default;

    operator const T&() const noexcept
    {
        return get();
    }

    operator T&() noexcept
    {
        return get();
    }

    const T& get() const noexcept
    {
        return m_data;
    }

    T& get() noexcept
    {
        return m_data;
    }

private:
    Destructor m_destructor;
    T m_data;
};

} // namespace ghaf::AudioControl
