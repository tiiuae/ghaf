# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  writeText,
  pkgs,
  lib,
  useGivc,
  cliArgs ? "",
  cfg,
  ewwScripts,
  ghaf-powercontrol,
  ...
}:
let
  ghaf-workspace = pkgs.callPackage ../../../../../../packages/ghaf-workspace { };
in
writeText "widgets.yuck" ''
  ;; Launcher ;;
      (defwidget launcher []
          (button :class "default_button"
              :onclick "${pkgs.nwg-drawer}/bin/nwg-drawer &"
              (box :class "icon"
                  :style "background-image: url(\"${pkgs.ghaf-artwork}/icons/launcher.svg\")")))

      ;; Generic slider widget ;;
      (defwidget slider [?visible ?header-left ?header-onclick ?header-right ?icon ?image ?app_icon ?settings_icon level ?onchange ?settings-onclick ?icon-onclick ?class ?min]
          (box :orientation "v"
              :visible { visible ?: "true"}
              :class "''${class}"
              :spacing 10
              :space-evenly false
              (box
                :hexpand true
                :visible { header-left != "" }
                :orientation "h"
                :spacing 5
                :halign "fill"
                :space-evenly false
                (label :class "header"
                  :visible { header-left != "" && header-left != "null" }
                  :text header-left
                  :halign "start")
                (eventbox
                  :halign "start"
                  :visible { header-onclick != "" && header-onclick != "null" }
                  :onclick header-onclick
                  :height 24
                  :width 24
                  :class "default_button"
                  (image
                    :class "icon"
                    :icon "arrow-down"
                  )
                )
                (label :class "header"
                  :visible { header-right != "" && header-right != "null" }
                  :text header-right
                  :hexpand "true"
                  :limit-width 35
                  :halign "end")
              )
              (box :orientation "h"
                  :valign "end"
                  :spacing 5
                  :space-evenly false
                  (eventbox
                      :active { icon-onclick != "" && icon-onclick != "null" }
                      :visible {image != "" || icon != "" || app_icon != ""}
                      :onclick icon-onclick
                      :height 24
                      :width 24
                      :class "default_button"
                      (box
                        (image :class "icon" :visible { image != "" } :path image :image-height 24 :image-width 24)
                        (image
                          :class "icon"
                          :visible { image == "" }
                          :icon {icon != "" ? icon : app_icon != "" ? app_icon : "icon-missing" }
                          :image-height 24
                          :image-width 24
                          :style {app_icon != "" ? "opacity: ''${level == 0 || level == min ? "0.5" : "1"}" : ""}
                        )
                      )
                  )
                  (eventbox
                      :class "slider"
                      :hexpand true
                      (scale
                          :orientation "h"
                          :value level
                          :round-digits 0
                          :onchange onchange
                          :max 100
                          :min { min ?: 0 }))
                  (eventbox
                      :visible { settings-onclick != "" && settings-onclick != "null" }
                      :onclick settings-onclick
                      :height 24
                      :width 24
                      :class "default_button"
                      (image :class "icon" :icon settings_icon)))))

      (defwidget slider_with_children [?visible ?child_0_visible ?child_1_visible ?header-left ?header-onclick ?header-right ?icon ?image ?app_icon ?settings_icon level ?onchange ?settings-onclick ?icon-onclick ?class ?min]
          (box :orientation "v"
              :visible { visible ?: "true"}
              :class "''${class}"
              :spacing 10
              :space-evenly false
              (box :orientation "v" :space-evenly "false" :spacing 0
              (box
                :hexpand true
                :visible { header-left != "" }
                :orientation "h"
                :spacing 5
                :halign "fill"
                :space-evenly false
                (eventbox
                  :halign "start"
                  :hexpand true
                  :active { header-onclick != "" && header-onclick != "null" }
                  :visible { header-left != "" }
                  :onclick header-onclick
                  :height 24
                  :width 24
                  :class "default_button"
                  (box :orientation "h" :space-evenly "false" :spacing 5 :halign "fill"
                    (label :class "header"
                      :visible { header-left != "" && header-left != "null" }
                      :text header-left
                      :halign "start")
                    (image
                      :class "icon"
                      :icon "arrow-down")
                  )
                )

                (label :class "header"
                  :visible { header-right != "" && header-right != "null" }
                  :text header-right
                  :hexpand "true"
                  :limit-width 35
                  :halign "end")
              )
              (revealer
                :transition "slidedown"
                :duration "250ms"
                :reveal {child_0_visible ?: "false"}
                (children :nth 0)
              )
              )
              (box :orientation "v" :space-evenly "false" :spacing 0
              (box :orientation "h"
                  :valign "end"
                  :spacing 5
                  :space-evenly false
                  (eventbox
                      :active { icon-onclick != "" && icon-onclick != "null" }
                      :visible {image != "" || icon != "" || app_icon != ""}
                      :onclick icon-onclick
                      :height 24
                      :width 24
                      :class "default_button"
                      (box
                        (image :class "icon" :visible { image != "" } :path image :image-height 24 :image-width 24)
                        (image
                          :class "icon"
                          :visible { image == "" }
                          :icon {icon != "" ? icon : app_icon != "" ? app_icon : "icon-missing" }
                          :image-height 24
                          :image-width 24
                          :style {app_icon != "" ? "opacity: ''${level == 0 || level == min ? "0.5" : "1"}" : ""}
                        )
                      )
                  )
                  (eventbox
                      :class "slider"
                      :hexpand true
                      (scale
                          :orientation "h"
                          :value level
                          :round-digits 0
                          :onchange onchange
                          :max 100
                          :min { min ?: 0 }))
                  (eventbox
                      :visible { settings-onclick != "" && settings-onclick != "null" }
                      :onclick settings-onclick
                      :height 24
                      :width 24
                      :class "default_button"
                      (image :class "icon" :icon settings_icon)))
              (revealer
                :transition "slidedown"
                :duration "250ms"
                :reveal {child_1_visible ?: "false"}
                (children :nth 1)
              )
              )))

      (defwidget sys_sliders []
          (box
              :orientation "v"
              :spacing 10
              :hexpand false
              :space-evenly false
              (slider_with_children
                      :visible { audio_output != "" }
                      :class "qs-slider"
                      :header-left {audio_output.friendly_name =~ '.*sof-hda-dsp.*' ? "Built-in ''${audio_output.device_type}" :
                                    audio_output.friendly_name}
                      :header-onclick "''${EWW_CMD} update audio_output_selector_visible=''${!audio_output_selector_visible} &"
                      :child_0_visible audio_output_selector_visible
                      :child_1_visible volume-mixer-visible
                      :image { audio_output.is_muted == "true" || audio_output.volume_percentage == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                              audio_output.volume_percentage <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                              audio_output.volume_percentage <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" }
                      :icon-onclick "${ewwScripts.eww-audio}/bin/eww-audio mute &"
                      :settings_icon "adjustlevels"
                      :level { audio_output.is_muted == "true" ? "0" : audio_output.volume_percentage }
                      :onchange "${ewwScripts.eww-audio}/bin/eww-audio set_volume {} &"
                      (audio_output_selector)
                      (box :orientation "v"
                        (label :text "No audio streams" :visible {arraylength(audio_streams) == 0} :halign "center" :valign "center")
                        (volume_mixer :visible {arraylength(audio_streams) > 0})
                      ))
              (slider_with_children
                      :visible { audio_input != "" && audio_input.state == "RUNNING" }
                      :class "qs-slider"
                      :header-left {audio_input.friendly_name =~ '.*sof-hda-dsp.*' ? "Built-in ''${audio_input.device_type}" :
                                    audio_input.friendly_name }
                      :header-onclick "''${EWW_CMD} update audio_input_selector_visible=''${!audio_input_selector_visible} &"
                      :child_0_visible audio_input_selector_visible
                      :icon { audio_input.is_muted == "true" || audio_input.volume_percentage == 0 ? "microphone-sensitivity-muted" :
                              audio_input.volume_percentage <= 25 ? "microphone-sensitivity-low" :
                              audio_input.volume_percentage <= 75 ? "microphone-sensitivity-medium" : "microphone-sensitivity-high" }
                      :icon-onclick "${ewwScripts.eww-audio}/bin/eww-audio mute_source ''${audio_input.device_index} &"
                      :level { audio_input.is_muted == "true" ? "0" : audio_input.volume_percentage }
                      :onchange "${ewwScripts.eww-audio}/bin/eww-audio set_source_volume ''${audio_input.device_index} {} &"
                      (audio_input_selector)
                      (label :text "Placeholder" :visible false)
                      )

              (slider
                      :class "qs-slider"
                      :header-left "Brightness"
                      :level {brightness.screen.level}
                      :image { brightness.screen.level == 0 ? "${pkgs.ghaf-artwork}/icons/brightness-0.svg" :
                              brightness.screen.level < 12 ? "${pkgs.ghaf-artwork}/icons/brightness-1.svg" :
                              brightness.screen.level < 25 ? "${pkgs.ghaf-artwork}/icons/brightness-2.svg" :
                              brightness.screen.level < 37 ? "${pkgs.ghaf-artwork}/icons/brightness-3.svg" :
                              brightness.screen.level < 50 ? "${pkgs.ghaf-artwork}/icons/brightness-4.svg" :
                              brightness.screen.level < 62 ? "${pkgs.ghaf-artwork}/icons/brightness-5.svg" :
                              brightness.screen.level < 75 ? "${pkgs.ghaf-artwork}/icons/brightness-6.svg" :
                              brightness.screen.level < 87 ? "${pkgs.ghaf-artwork}/icons/brightness-7.svg" :
                                                              "${pkgs.ghaf-artwork}/icons/brightness-8.svg" }
                      :min "5"
                      :onchange "${ewwScripts.eww-brightness}/bin/eww-brightness set_screen {} &")
          )
      )

      (defwidget audio_output_selector []
        (scroll
          :hscroll "false"
          :vscroll "true"
          :height { 30 * min(4,arraylength(audio_outputs)) }
          (box :orientation "v" :space-evenly false :spacing 5
            (for device in {audio_outputs}
              (button
                :class "default_button"
                :onclick "${ewwScripts.eww-audio}/bin/eww-audio set_default_sink ''${device.id} && ''${EWW_CMD} update audio_output_selector_visible=false &"
                (box :orientation "h" :spacing 10 :space-evenly "false"
                  (image :halign "start" :path {  device.is_muted == "true" || device.volume_percentage == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                                                  device.volume_percentage <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                                                  device.volume_percentage <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" })
                  (label :halign "start" :limit-width 30 :text { device.friendly_name =~ '.*sof-hda-dsp.*' ? "Built-in ''${device.device_type}" : device.friendly_name })
                  (image :halign "start" :icon "emblem-ok" :style "opacity: ''${device.is_default ? "1" : "0"}")
                )
              )
            )
          )
        )
      )

      (defwidget audio_input_selector []
        (scroll
          :hscroll "false"
          :vscroll "true"
          :height { 30 * min(4,arraylength(audio_inputs)) }
          (box :orientation "v" :space-evenly false :spacing 5
            (for device in {audio_inputs}
              (button
                :class "default_button"
                :onclick "${ewwScripts.eww-audio}/bin/eww-audio set_default_source ''${device.id} && ''${EWW_CMD} update audio_input_selector_visible=false &"
                (box :orientation "h" :spacing 10 :space-evenly "false"
                  (image :halign "start" :icon { device.is_muted == "true" || device.volume_percentage == 0 ? "microphone-sensitivity-muted" :
                                                 device.volume_percentage <= 25 ? "microphone-sensitivity-low" :
                                                 device.volume_percentage <= 75 ? "microphone-sensitivity-medium" : "microphone-sensitivity-high" })
                  (label :halign "start" :limit-width 30 :text { device.friendly_name =~ '.*sof-hda-dsp.*' ? "Built-in ''${device.device_type}" : device.friendly_name })
                  (image :halign "start" :icon "emblem-ok" :style "opacity: ''${device.is_default ? "1" : "0"}")
                )
              )
            )
          )
        )
      )

      (defwidget volume_mixer [?visible]
          (scroll
              :hscroll "false"
              :vscroll "true"
              :visible { visible ?: "true" }
              :height { 30 * min(4,arraylength(audio_streams)) }
              (box :orientation "v" :space-evenly false :spacing 10
                (for entry in {audio_streams}
                  (slider
                      :class "qs-slider"
                      :header-left {entry.name}
                      :level {entry.muted == "true" ? "0" : entry.level}
                      :app_icon {entry.icon_name != "" ? entry.icon_name : "icon-missing"}
                      :image { entry.muted == "true" || entry.level == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                              entry.level <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                              entry.level <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" }
                      :onchange "${ewwScripts.eww-audio}/bin/eww-audio set_sink_input_volume ''${entry.id} {} &"
                      :icon-onclick "${ewwScripts.eww-audio}/bin/eww-audio mute_sink_input ''${entry.id} {} &")
                )
              )
          )
      )

      ;; Generic Widget Buttons For Quick Settings ;;
      (defwidget widget_button [icon ?title ?header ?subtitle ?onclick ?class]
          (eventbox :class { class == "" ? "widget-button" : "''${class}" }
              :onclick onclick
              (box :orientation "v"
                  :class "inner-box"
                  :spacing 6
                  :space-evenly false
                  (label :class "header"
                      :visible { header != "" && header != "null" }
                      :text header
                      :hexpand true
                      :vexpand true
                      :halign "start"
                      :valign "fill")
                  (box :orientation "h"
                      :spacing 10
                      :valign "fill"
                      :halign "start"
                      :hexpand true
                      :vexpand true
                      :space-evenly false
                      (image :class "icon"
                        :visible { icon != "" }
                        :path icon
                        :image-height 24
                        :image-width 24
                        :valign "center"
                        :halign "start")
                      (box :class "text"
                          :valign "center"
                          :orientation "v"
                          :spacing 3
                          :halign "start"
                          :hexpand true
                          (label :halign "start" :class "title" :text title)
                          (label :visible {subtitle != ""} :halign "start" :class "subtitle" :text subtitle :limit-width 13))))))

      ;; Power Menu Buttons ;;
      (defwidget power_menu []
          (box
          :orientation "v"
          :halign "start"
          :hexpand "false"
          :vexpand "false"
          :spacing 10
          :space-evenly "false"
          (widget_button
                  :class "power-menu-button"
                  :icon "${pkgs.ghaf-artwork}/icons/lock.svg"
                  :title "Lock"
                  :onclick "''${EWW_CMD} close power-menu closer & loginctl lock-session &")
          (widget_button
                  :class "power-menu-button"
                  :icon "${pkgs.ghaf-artwork}/icons/suspend.svg"
                  :title "Suspend"
                  :onclick "''${EWW_CMD} close power-menu closer & ${ghaf-powercontrol}/bin/ghaf-powercontrol suspend &")
          (widget_button
                  :class "power-menu-button"
                  :icon "${pkgs.ghaf-artwork}/icons/logout.svg"
                  :title "Log Out"
                  :onclick "''${EWW_CMD} close power-menu closer & ${pkgs.labwc}/bin/labwc --exit &")
          (widget_button
                  :class "power-menu-button"
                  :icon "${pkgs.ghaf-artwork}/icons/restart.svg"
                  :title "Reboot"
                  :onclick "''${EWW_CMD} close power-menu closer & ${ghaf-powercontrol}/bin/ghaf-powercontrol reboot &")
          (widget_button
                  :class "power-menu-button"
                  :icon "${pkgs.ghaf-artwork}/icons/power.svg"
                  :title "Shutdown"
                  :onclick "''${EWW_CMD} close power-menu closer & ${ghaf-powercontrol}/bin/ghaf-powercontrol poweroff &")))

      ${lib.optionalString useGivc ''
        ;; Quick Settings Buttons ;;
        (defwidget settings_buttons []
            (box
                :orientation "v"
                :spacing 10
                (box
                    :orientation "h"
                    (widget_button
                        :icon "${pkgs.ghaf-artwork}/icons/bluetooth-1.svg"
                        :header "Bluetooth"
                        :onclick "''${EWW_CMD} close quick-settings closer & ${pkgs.bt-launcher}/bin/bt-launcher &")
                    (box
                        :hexpand true
                        :vexpand true
                        :class "spacer"))))

          (defwidget battery_settings_buttons []
              (box :orientation "h"
                  :space-evenly true
                  :spacing 10
                  (widget_button
                      :visible { EWW_BATTERY != "" }
                      :header "Battery"
                      :title {EWW_BATTERY != "" ? "''${battery.capacity}%" : "100%"}
                      :subtitle { battery.status == 'Charging' ? "Charging" :
                                  battery.hours != "0" && battery.minutes != "0" ? "''${battery.hours}h ''${battery.minutes}m" :
                                  battery.hours == "0" && battery.minutes != "0" ? "''${battery.minutes}m" :
                                  battery.hours != "0" && battery.minutes == "0" ? "''${battery.hours}h" :
                                  "" }
                      :icon { battery.status == 'Charging' ? "${pkgs.ghaf-artwork}/icons/battery-charging.svg" :
                              battery.capacity < 10 ? "${pkgs.ghaf-artwork}/icons/battery-0.svg" :
                              battery.capacity < 30 ? "${pkgs.ghaf-artwork}/icons/battery-1.svg" :
                              battery.capacity < 70 ? "${pkgs.ghaf-artwork}/icons/battery-2.svg" :
                                                      "${pkgs.ghaf-artwork}/icons/battery-3.svg" })
                  (widget_button
                      :icon "${pkgs.ghaf-artwork}/icons/admin-cog.svg"
                      :header "Settings"
                      :onclick "''${EWW_CMD} close quick-settings closer & ${pkgs.ctrl-panel}/bin/ctrl-panel ${cliArgs} >/dev/null &")))
      ''}

      ;; Reusable Widgets ;;
      (defwidget desktop-widget [?space-evenly ?spacing ?orientation ?class]
        (box
          :class "floating-widget ''${class}"
          :space-evenly {space-evenly != "" ? space-evenly : "false"}
          :spacing {spacing != "" ? spacing : "10"}
          :orientation {orientation != "" ? orientation : "v"}
          (children)))

      ;; Quick Settings Widget ;;
      (defwidget quick-settings-widget []
          (desktop-widget
              (battery_settings_buttons)
              (sys_sliders)))

      ;; Power Menu Widget ;;
      (defwidget power-menu-widget []
          (desktop-widget
              (power_menu)))

      ;; Brightness Popup Widget ;;
      (defwidget brightness-popup []
          (revealer :transition "crossfade" :duration "200ms" :reveal brightness-popup-visible :active false
              (desktop-widget :class "popup"
                  (slider
                      :valign "center"
                      :image { brightness.screen.level == 0 ? "${pkgs.ghaf-artwork}/icons/brightness-0.svg" :
                              brightness.screen.level < 12 ? "${pkgs.ghaf-artwork}/icons/brightness-1.svg" :
                              brightness.screen.level < 25 ? "${pkgs.ghaf-artwork}/icons/brightness-2.svg" :
                              brightness.screen.level < 37 ? "${pkgs.ghaf-artwork}/icons/brightness-3.svg" :
                              brightness.screen.level < 50 ? "${pkgs.ghaf-artwork}/icons/brightness-4.svg" :
                              brightness.screen.level < 62 ? "${pkgs.ghaf-artwork}/icons/brightness-5.svg" :
                              brightness.screen.level < 75 ? "${pkgs.ghaf-artwork}/icons/brightness-6.svg" :
                              brightness.screen.level < 87 ? "${pkgs.ghaf-artwork}/icons/brightness-7.svg" :
                                                              "${pkgs.ghaf-artwork}/icons/brightness-8.svg" }
                      :level {brightness.screen.level}))))

      ;; Volume Popup Widget ;;
      (defwidget volume-popup []
          (revealer :transition "crossfade" :duration "200ms" :reveal volume-popup-visible :active false
              (desktop-widget :class "popup"
                  (slider
                      :valign "center"
                      :image { audio_output.is_muted == "true" || audio_output.volume_percentage == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                               audio_output.volume_percentage <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                               audio_output.volume_percentage <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" }
                      :level { audio_output.is_muted == "true" ? "0" : audio_output.volume_percentage }))))

      ;; Workspace Popup Widget ;;
      (defwidget workspace-popup []
          (revealer :transition "crossfade" :duration "200ms" :reveal workspace-popup-visible :active false
              (desktop-widget :class "popup"
                  (label :text "Desktop ''${workspace}"))))

      ;; Quick Settings Button ;;
      (defwidget quick-settings-button [screen bat-icon vol-icon bright-icon]
          (button :class "default_button"
              :onclick "''${EWW_CMD} update audio_output_selector_visible=false audio_input_selector_visible=false & ${ewwScripts.eww-open-widget}/bin/eww-open-widget quick-settings \"''${screen}\" &"
              (box :orientation "h"
                  :space-evenly "false"
                  :spacing 14
                  :valign "center"
                  (image :visible { bright-icon != "" }
                      :class "icon"
                      :path bright-icon
                      :image-height 24
                      :image-width 24)
                  (image :visible { vol-icon != "" && audio_output != "" }
                      :class "icon"
                      :path vol-icon
                      :image-height 24
                      :image-width 24)
                  (image :visible { audio_input != "" && audio_input.state == "RUNNING" }
                      :icon "microphone-sensitivity-high")
                  (image :visible { bat-icon != "" }
                      :class "icon"
                      :path bat-icon
                      :image-height 24
                      :image-width 24))))

      ;; Power Menu Launcher ;;
      (defwidget power-menu-launcher [screen]
          (button :class "default_button icon"
              :halign "center"
              :valign "center"
              :onclick "${ewwScripts.eww-open-widget}/bin/eww-open-widget power-menu \"''${screen}\" &"
              (box :class "icon"
                  :hexpand false
                  :style "background-image: url(\"${pkgs.ghaf-artwork}/icons/power.svg\")")))
      ;; Closer Widget ;;
      ;; This widget, and the closer window, acts as a transparent area that fills the whole screen
      ;; so the user can close the specified window (widget) simply by clicking "outside"
      (defwidget closer [window]
          (eventbox
            :onclick "(''${EWW_CMD} close ''${window} closer) &"
            :onmiddleclick "(''${EWW_CMD} close ''${window} closer) &"
            :onrightclick "(''${EWW_CMD} close ''${window} closer) &"))
      ;; Quick Settings Launcher ;;
      (defwidget control [screen]
          (box :orientation "h"
              :space-evenly "false"
              :spacing 14
              :valign "center"
              :class "control"
              (quick-settings-button :screen screen
                  :bright-icon { brightness.screen.level == 0 ? "${pkgs.ghaf-artwork}/icons/brightness-0.svg" :
                              brightness.screen.level < 12 ? "${pkgs.ghaf-artwork}/icons/brightness-1.svg" :
                              brightness.screen.level < 25 ? "${pkgs.ghaf-artwork}/icons/brightness-2.svg" :
                              brightness.screen.level < 37 ? "${pkgs.ghaf-artwork}/icons/brightness-3.svg" :
                              brightness.screen.level < 50 ? "${pkgs.ghaf-artwork}/icons/brightness-4.svg" :
                              brightness.screen.level < 62 ? "${pkgs.ghaf-artwork}/icons/brightness-5.svg" :
                              brightness.screen.level < 75 ? "${pkgs.ghaf-artwork}/icons/brightness-6.svg" :
                              brightness.screen.level < 87 ? "${pkgs.ghaf-artwork}/icons/brightness-7.svg" :
                                                              "${pkgs.ghaf-artwork}/icons/brightness-8.svg" }
                  :vol-icon { audio_output.is_muted == "true" || audio_output.volume_percentage == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                              audio_output.volume_percentage <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                              audio_output.volume_percentage <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" }
                  :bat-icon { battery.status == 'Charging' ? "${pkgs.ghaf-artwork}/icons/battery-charging.svg" :
                              battery.capacity < 10 ? "${pkgs.ghaf-artwork}/icons/battery-0.svg" :
                              battery.capacity < 30 ? "${pkgs.ghaf-artwork}/icons/battery-1.svg" :
                              battery.capacity < 70 ? "${pkgs.ghaf-artwork}/icons/battery-2.svg" :
                                                      "${pkgs.ghaf-artwork}/icons/battery-3.svg" })))

      ;; Divider ;;
      (defwidget divider []
          (box
              :active false
              :orientation "v"
              :class "divider"))

      ;; Language ;;
      (defwidget language []
          (box
              :class "keyboard-layout"
              :halign "center"
              :valign "center"
              :visible "false"
              (label  :text keyboard_layout)))

      ;; DateTime Widget ;;
      (defwidget datetime [screen]
          (button
              :onclick "${ewwScripts.eww-open-widget}/bin/eww-open-widget calendar \"''${screen}\" &"
              :class "default_button date" "''${formattime(EWW_TIME, "%H:%M  %a %b %-d")}"))

      ;; Calendar ;;
      (defwidget cal []
          (desktop-widget
              (calendar :class "cal"
                  :show-week-numbers false)))

      ;; Left Widgets ;;
      (defwidget workspaces []
          (box :class "workspace"
              :orientation "h"
              :space-evenly "false"
              (button :class "default_button"
                      :tooltip "Current desktop"
                      :onclick {workspaces-visible == "false" ? "''${EWW_CMD} update workspaces-visible=true" : "''${EWW_CMD} update workspaces-visible=false"}
                      workspace)
              (revealer
                  :transition "slideright"
                  :duration "250ms"
                  :reveal workspaces-visible
                  (eventbox :onhoverlost "''${EWW_CMD} update workspaces-visible=false"
                      (box :orientation "h"
                          :space-evenly "true"
                          ${
                            lib.concatStringsSep "\n" (
                              builtins.map (index: ''
                                (button :class "default_button"
                                    :onclick "${ghaf-workspace}/bin/ghaf-workspace switch ${toString index}; ''${EWW_CMD} update workspaces-visible=false"
                                    "${toString index}")
                              '') (lib.lists.range 1 cfg.maxDesktops)
                            )
                          })))))

      (defwidget bar_left []
          (box
              :orientation "h"
              :space-evenly "false"
              :spacing 14
              :halign "start"
              :valign "center"
              (launcher)
              (label :text audio_streams :visible "false")
              (divider)
              (workspaces)))

      ;; Center Widgets ;;
      (defwidget bar_center [screen]
          (box
              :orientation "h"
              :space-evenly "false"
              :spacing 14
              :halign "center"
              :valign "center"
              (datetime :screen screen)))

      ;; Right Widgets ;;
      (defwidget datetime-locale [screen]
          (box
              :orientation "h"
              :space-evenly "false"
              :spacing 14
              (language)
              (datetime :screen screen)))

      ;; End Widgets ;;
      (defwidget bar_right [screen]
          (box :orientation "h"
              :space-evenly "false"
              :halign "end"
              :valign "center"
              :spacing 14
              (systray :orientation "h" :spacing 14 :prepend-new true :class "tray")
              (divider)
              ${lib.optionalString useGivc "(control :screen screen) (divider)"}
              (power-menu-launcher :screen screen)))

      ;; Bar ;;
      (defwidget bar [screen]
          (centerbox
              :class "eww_bar"
              :orientation "h"
              :vexpand "false"
              :hexpand "false"
              (bar_left)
              (bar_center :screen screen)
              (bar_right :screen screen)))
''
