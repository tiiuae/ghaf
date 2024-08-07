/*
 * Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <GhafAudioControl/AudioControl.hpp>
#include <GhafAudioControl/Backends/PulseAudio/AudioControlBackend.hpp>
#include <GhafAudioControl/utils/Logger.hpp>

#include <glibmm/optioncontext.h>
#include <gtkmm/applicationwindow.h>

#include <format>

using namespace ghaf::AudioControl;

namespace
{

int GtkClient(std::string pulseAudioServerAddress)
{
    auto app = Gtk::Application::create();

    AudioControl audioControl{std::make_unique<Backend::PulseAudio::AudioControlBackend>(std::move(pulseAudioServerAddress))};

    Gtk::ApplicationWindow window;
    window.add(audioControl);
    window.show_all();

    return app->run(window);
}

} // namespace

int main(int argc, char** argv)
{
    Glib::ustring pulseServerAddress;
    Glib::OptionEntry pulseServerOption;

    pulseServerOption.set_long_name("pulseaudio_server");
    pulseServerOption.set_description("PulseAudio server address");

    Glib::OptionGroup options("Main", "Main");
    options.add_entry(pulseServerOption, pulseServerAddress);

    Glib::OptionContext context("Application Options");
    context.set_main_group(options);

    try
    {
        if (!context.parse(argc, argv))
            throw std::runtime_error{"Couldn't parse command line arguments"};
    }
    catch (const Glib::Error& ex)
    {
        Logger::error(std::format("Error: {}", ex.what().c_str()));
        Logger::info(context.get_help().c_str());

        return 1;
    }

    return GtkClient(pulseServerAddress);
}
