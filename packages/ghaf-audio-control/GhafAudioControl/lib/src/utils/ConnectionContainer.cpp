/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/utils/ConnectionContainer.hpp>

namespace ghaf::AudioControl
{

ConnectionContainer::ConnectionContainer(std::initializer_list<sigc::connection> connections)
    : m_connections{connections}
{
}

ConnectionContainer::~ConnectionContainer()
{
    clear();
}

ScopeExit ConnectionContainer::blockGuarded()
{
    block();

    return {[this]()
            {
                unblock();
            }};
}

void ConnectionContainer::block()
{
    forEach(&sigc::connection::block, true);
}

void ConnectionContainer::unblock()
{
    forEach(&sigc::connection::unblock);
}

void ConnectionContainer::clear()
{
    block();
    forEach(&sigc::connection::disconnect);

    m_connections.clear();
}

} // namespace ghaf::AudioControl
