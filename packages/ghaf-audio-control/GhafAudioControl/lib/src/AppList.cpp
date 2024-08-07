/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/AppList.hpp>

#include <GhafAudioControl/utils/Logger.hpp>

#include <gtkmm/adjustment.h>
#include <gtkmm/enums.h>
#include <gtkmm/image.h>
#include <gtkmm/label.h>
#include <gtkmm/scale.h>
#include <gtkmm/switch.h>

#include <format>

namespace ghaf::AudioControl
{

namespace
{

const auto ScaleSize = 200;
const auto ScaleOrientation = Gtk::Orientation::ORIENTATION_HORIZONTAL;
const auto ScaleInitialValue = 0.0;
const auto ScaleLowerLimit = 0.0;
const auto ScaleUpperLimit = 100.0;

const auto SwitchSize = 10;
const auto IconSize = 25;
const auto NameLabelSize = 75;
const auto BoxPlaces = 4;

std::optional<size_t> GetIndexByAppId(const Glib::RefPtr<Gio::ListStore<AppRaw>>& model, AppRaw::AppIdType id) noexcept
{
    for (size_t index = 0; index < model->get_n_items(); ++index)
        if (id == model->get_item(index)->getId())
            return index;

    return std::nullopt;
}

Gtk::Scale* MakeScaleWidget()
{
    auto adjustment = Gtk::Adjustment::create(ScaleInitialValue, ScaleLowerLimit, ScaleUpperLimit);

    auto* scale = Gtk::make_managed<Gtk::Scale>(std::move(adjustment), ScaleOrientation);
    scale->set_size_request(ScaleSize);
    scale->set_digits(0);

    return scale;
}

} // namespace

AppList::AppList()
    : Gtk::Box(Gtk::ORIENTATION_HORIZONTAL)
    , m_separator(Gtk::Orientation::ORIENTATION_VERTICAL)
    , m_appsModel(Gio::ListStore<AppRaw>::create())
{
    m_listBox.bind_model(m_appsModel, sigc::mem_fun(*this, &AppList::createWidgetsForApp));
    m_listBox.set_can_focus(false);
    m_listBox.set_selection_mode(Gtk::SelectionMode::SELECTION_SINGLE);

    m_connection = m_listBox.signal_row_selected().connect(
        [this](const Gtk::ListBoxRow* row)
        {
            if (row == nullptr)
            {
                Logger::error("AppList: ListBoxRow is nullptr");
                return;
            }

            m_stack.set_visible_child(std::to_string(m_appsModel->get_item(row->get_index())->getId()));
        });

    m_stack.set_transition_type(Gtk::StackTransitionType::STACK_TRANSITION_TYPE_SLIDE_UP_DOWN);

    pack_start(m_listBox, Gtk::PACK_SHRINK);
    pack_start(m_separator, Gtk::PACK_SHRINK);
    pack_start(m_stack, Gtk::PACK_EXPAND_WIDGET);
}

void AppList::addApp(AppRaw::AppIdType id, IAudioControlBackend::IDevice::Ptr sink, IAudioControlBackend::IDevice::Ptr source)
{
    if (const auto index = GetIndexByAppId(m_appsModel, id))
        doUpdateApp(*index, std::move(sink), std::move(source));
    else
        m_appsModel->append(AppRaw::create(id, std::move(sink), std::move(source)));
}

void AppList::updateApp(AppRaw::AppIdType id, IAudioControlBackend::IDevice::Ptr sink, IAudioControlBackend::IDevice::Ptr source)
{
    if (const auto index = GetIndexByAppId(m_appsModel, id))
        doUpdateApp(*index, std::move(sink), std::move(source));
    else
        Logger::error(std::format("AppList::updateApp: no app with id: {}", id));
}

void AppList::removeAllApps()
{
    m_appsBindings.clear();
    m_appsModel->remove_all();
}

void AppList::doUpdateApp(size_t modelIndex, IAudioControlBackend::IDevice::Ptr sink, IAudioControlBackend::IDevice::Ptr source)
{
    auto item = m_appsModel->get_item(modelIndex);

    if (sink)
        item->updateSink(std::move(sink));

    if (source)
        item->updateSource(std::move(source));
}

void AppList::removeApp(AppRaw::AppIdType id)
{
    if (const auto index = GetIndexByAppId(m_appsModel, id))
    {
        std::ignore = m_appsBindings.erase(id);
        m_appsModel->remove(*index);
    }
    else
        Logger::error(std::format("AppList::deleteApp: no app with id: {}", id));
}

Gtk::Widget* AppList::createWidgetsForApp(const Glib::RefPtr<Glib::Object>& appVmPtr)
{
    if (!appVmPtr)
    {
        Logger::error("AppList: appVmPtr is nullptr");
        return nullptr;
    }

    auto appVm = Glib::RefPtr<AppRaw>::cast_dynamic<Glib::Object>(appVmPtr);
    if (!appVm)
    {
        Logger::error("AppList: appVm is not an AppRaw");
        return nullptr;
    }

    auto* icon = Gtk::make_managed<Gtk::Image>("/usr/share/pixmaps/ubuntu-logo.svg");
    auto* nameLabel = Gtk::make_managed<Gtk::Label>();
    auto* soundEnableSwitch = Gtk::make_managed<Gtk::Switch>();
    auto* soundScale = MakeScaleWidget();
    auto* microEnableSwitch = Gtk::make_managed<Gtk::Switch>();
    auto* microScale = MakeScaleWidget();

    icon->set_size_request(IconSize);
    nameLabel->set_size_request(NameLabelSize);
    nameLabel->set_halign(Gtk::Align::ALIGN_START);
    nameLabel->set_can_focus(false);
    nameLabel->set_selectable(false);
    nameLabel->set_focus_on_click(false);

    soundEnableSwitch->set_size_request(SwitchSize);
    microEnableSwitch->set_size_request(SwitchSize);

    const auto bind = [](const auto& appProp, const auto& widgetProp, bool readonly = false)
    {
        auto flag = Glib::BindingFlags::BINDING_SYNC_CREATE;
        if (!readonly)
            flag |= Glib::BindingFlags::BINDING_BIDIRECTIONAL;

        return Glib::Binding::bind_property(appProp, widgetProp, flag);
    };

    m_appsBindings[appVm->getId()] = {bind(appVm->getHasSinkProperty(), soundEnableSwitch->property_sensitive(), true),
                                      bind(appVm->getHasSinkProperty(), soundScale->property_sensitive(), true),
                                      bind(appVm->getHasSourceProperty(), microEnableSwitch->property_sensitive(), true),
                                      bind(appVm->getHasSourceProperty(), microScale->property_sensitive(), true),

                                      bind(appVm->getAppNameProperty(), nameLabel->property_label(), true),
                                      bind(appVm->getSoundEnabledProperty(), soundEnableSwitch->property_state()),
                                      bind(appVm->getSoundVolumeProperty(), soundScale->get_adjustment()->property_value()),
                                      bind(appVm->getMicroEnabledProperty(), microEnableSwitch->property_state()),
                                      bind(appVm->getMicroVolumeProperty(), microScale->get_adjustment()->property_value())};

    auto* stackGrid = Gtk::make_managed<Gtk::Box>(Gtk::ORIENTATION_HORIZONTAL, BoxPlaces);
    stackGrid->add(*soundEnableSwitch);
    stackGrid->add(*soundScale);
    stackGrid->add(*microEnableSwitch);
    stackGrid->add(*microScale);

    stackGrid->set_valign(Gtk::ALIGN_START);

    auto* sidebarGrid = Gtk::make_managed<Gtk::ListBox>();
    sidebarGrid->add(*icon);
    sidebarGrid->add(*nameLabel);

    m_stack.add(*stackGrid, std::to_string(appVm->getId()));

    return sidebarGrid;
}

} // namespace ghaf::AudioControl
