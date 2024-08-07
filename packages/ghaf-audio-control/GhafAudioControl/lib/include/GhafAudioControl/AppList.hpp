/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <GhafAudioControl/AppListRow.hpp>

#include <gtkmm/box.h>
#include <gtkmm/listbox.h>
#include <gtkmm/separator.h>
#include <gtkmm/stack.h>

#include <glibmm/binding.h>

namespace ghaf::AudioControl
{

class AppList final : public Gtk::Box
{
public:
    AppList();

    void addApp(AppRaw::AppIdType id, IAudioControlBackend::ISink::Ptr sink, IAudioControlBackend::ISource::Ptr source);
    void updateApp(AppRaw::AppIdType id, IAudioControlBackend::ISink::Ptr sink, IAudioControlBackend::ISource::Ptr source);
    void removeApp(AppRaw::AppIdType id);
    void removeAllApps();

private:
    void doUpdateApp(size_t modelIndex, IAudioControlBackend::ISink::Ptr sink, IAudioControlBackend::ISource::Ptr source);

    [[nodiscard]] Gtk::Widget* createWidgetsForApp(const Glib::RefPtr<Glib::Object>& appVmPtr);

private:
    Gtk::ListBox m_listBox;
    Gtk::Separator m_separator;
    Gtk::Stack m_stack;

    Glib::RefPtr<Gio::ListStore<AppRaw>> m_appsModel;
    std::map<AppRaw::AppIdType, std::vector<Glib::RefPtr<Glib::Binding>>> m_appsBindings;
    sigc::connection m_connection;
};

} // namespace ghaf::AudioControl
