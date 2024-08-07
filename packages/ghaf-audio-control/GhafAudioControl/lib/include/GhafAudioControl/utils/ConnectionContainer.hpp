/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <GhafAudioControl/utils/ScopeExit.hpp>

#include <sigc++/connection.h>

#include <vector>

namespace ghaf::AudioControl
{

class ConnectionContainer final
{
public:
    ConnectionContainer() = default;

    ConnectionContainer(std::initializer_list<sigc::connection> connections);
    ConnectionContainer(ConnectionContainer&) = delete;
    ConnectionContainer(ConnectionContainer&&) = default;

    ~ConnectionContainer();

    void add(sigc::connection&& connection)
    {
        m_connections.emplace_back(std::move(connection));
    }

    ScopeExit blockGuarded();

    ConnectionContainer& operator=(ConnectionContainer&) = delete;
    ConnectionContainer& operator=(ConnectionContainer&&) = default;

    void block();
    void unblock();

    void clear();

private:
    void forEach(auto method)
    {
        for (auto& connection : m_connections)
            (connection.*method)();
    }

    void forEach(auto method, auto args...)
    {
        for (auto& connection : m_connections)
            (connection.*method)(args);
    }

private:
    std::vector<sigc::connection> m_connections;
};

} // namespace ghaf::AudioControl
