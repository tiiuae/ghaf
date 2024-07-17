/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <concepts>

#include <cstdint>

namespace ghaf::AudioControl
{

template<typename T>
concept NumericType = std::unsigned_integral<T> || std::floating_point<T>;

class Volume
{
public:
    using InternalT = uint8_t;

    static constexpr InternalT Min = 0;
    static constexpr InternalT Max = 100;

private:
    explicit Volume(NumericType auto value)
        : m_volume(trunkate(value))
    {
    }

public:
    [[nodiscard]] static Volume fromPercents(NumericType auto percents) noexcept
    {
        return Volume{percents};
    }

    [[nodiscard]] InternalT getPercents() const noexcept
    {
        return m_volume;
    }

private:
    [[nodiscard]] InternalT trunkate(NumericType auto value) const noexcept
    {
        if (value < Min)
            return Min;

        if (value > Max)
            return Max;

        return value;
    }

    InternalT m_volume;
};

} // namespace ghaf::AudioControl
