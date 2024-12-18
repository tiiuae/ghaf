# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  writeText,
  pkgs,
  lib,
  useGivc,
  cfg,
  pulseaudioTcpControlPort,
  ewwScripts,
  ghaf-powercontrol,
  ghaf-workspace,
  ...
}:
let
  iconThemeBase = "/run/current-system/sw/share/icons/${
    if cfg.gtk.colorScheme == "prefer-dark" then "${cfg.gtk.iconTheme}-Dark" else cfg.gtk.iconTheme
  }";
in
writeText "widgets.yuck" ''
  ;; Launcher ;;
      (defwidget launcher []
          (button :class "icon_button"
              :onclick "${pkgs.nwg-drawer}/bin/nwg-drawer &"
              (box :class "icon"
                  :style "background-image: url(\"${pkgs.ghaf-artwork}/icons/launcher.svg\")")))

      ;; Generic slider widget ;;
      (defwidget sys_slider [?header ?icon ?app_icon ?settings_icon level ?onchange ?settings-onclick ?icon-onclick ?class ?font-icon ?min]
          (box :orientation "v"
              :class "''${class}"
              :spacing 10
              :space-evenly false
              (label :class "header"
                  :visible { header != "" && header != "null" ? "true" : "false" }
                  :text header
                  :halign "start"
                  :hexpand true)
              (box :orientation "h"
                  :valign "end"
                  :space-evenly false
                  (eventbox
                      :active { icon-onclick != "" && icon-onclick != "null" ? "true" : "false" }
                      :visible {font-icon == "" ? "true" : "false"}
                      :onclick icon-onclick
                      :hexpand false
                      :class "icon_settings"
                      (overlay
                        (box :class "icon"
                            :hexpand false
                            :style "background-image: url(\"''${icon}\"); opacity: ''${app_icon != "" ? "0" : "1"}")
                        (box :class "icon"
                            :hexpand false
                            :style "background-image: url(\"''${app_icon}\"); opacity: ''${level == 0 || level == min ? "0.5" : "1"}")
                        ))
                  (label :class "icon" :visible {font-icon != "" ? "true" : "false"} :text font-icon)
                  (eventbox
                      :valign "CENTER"
                      :class "slider"
                      :hexpand true
                      (scale
                          :hexpand true
                          :orientation "h"
                          :halign "fill"
                          :value level
                          :round-digits 0
                          :onchange onchange
                          :max 100 
                          :min { min ?: 0 }))
                  (eventbox
                      :visible { settings-onclick != "" && settings-onclick != "null" ? "true" : "false" }
                      :onclick settings-onclick
                      :class "settings"
                      (box :class "icon"
                          :hexpand false
                          :style "background-image: url(\"''${settings_icon}\")")))
          (children)))

      (defwidget sys_sliders []
          (box
              :orientation "v"
              :spacing 10
              :hexpand false
              :space-evenly false
              (sys_slider
                      :class "qs-slider"
                      :header "Volume"
                      :icon { volume.system.muted == "true" || volume.system.level == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                              volume.system.level <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                              volume.system.level <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" }
                      :icon-onclick "${ewwScripts.eww-volume}/bin/eww-volume mute &"
                      :settings_icon "${iconThemeBase}/24x24/actions/adjustlevels.svg"
                      :settings-onclick {volume-mixer-visible == "false" ? "''${EWW_CMD} update volume-mixer-visible=true &" : "''${EWW_CMD} update volume-mixer-visible=false &"}
                      :level { volume.system.muted == "true" ? "0" : volume.system.level }
                      :onchange "PULSE_SERVER=audio-vm:${toString pulseaudioTcpControlPort} ${pkgs.pamixer}/bin/pamixer --unmute --set-volume {} &"
                      (revealer 
                              :transition "slidedown"
                              :duration "250ms"
                              :reveal volume-mixer-visible
                              (box :orientation "v"
                                (label :text "No audio streams" :visible {arraylength(volume.sinkInputs) == 0} :halign "center" :valign "center")
                                (volume_mixer)
                              )))
              (sys_slider
                      :class "qs-slider"
                      :header "Brightness"
                      :level {brightness.screen.level}
                      :icon { brightness.screen.level == 0 ? "${pkgs.ghaf-artwork}/icons/brightness-0.svg" :
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

      (defwidget volume_mixer []
          (scroll
              :hscroll "false"
              :vscroll "true"
              :height { 50 * min(3,arraylength(volume.sinkInputs)) }
              (box :orientation "v" :space-evenly false
                (for entry in {volume.sinkInputs}
                  (sys_slider 
                      :class "qs-slider"
                      :header {entry.name}
                      :level {entry.muted == "true" ? "0" : entry.level} 
                      :app_icon {entry.icon_name != "" ? "${iconThemeBase}/24x24/apps/''${entry.icon_name}.svg" : ""}
                      :icon { entry.muted == "true" || entry.level == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                              entry.level <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                              entry.level <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" }
                      :onchange "${pkgs.pulseaudio}/bin/pactl -s audio-vm:${toString pulseaudioTcpControlPort} set-sink-input-volume ''${entry.id} {}% & ${pkgs.pulseaudio}/bin/pactl -s audio-vm:${toString pulseaudioTcpControlPort} set-sink-input-mute ''${entry.id} 0 &"
                      :icon-onclick "${pkgs.pulseaudio}/bin/pactl -s audio-vm:${toString pulseaudioTcpControlPort} set-sink-input-mute ''${entry.id} toggle &")
                )
              )
          )
      )

      ;; Generic Widget Buttons For Quick Settings ;;
      (defwidget widget_button [icon ?title ?header ?subtitle ?onclick ?font-icon ?class]
          (eventbox :class { class == "" ? "widget-button" : "''${class}" }
              :onclick onclick
              (box :orientation "v"
                  :class "inner-box"
                  :spacing 6
                  :space-evenly false
                  (label :class "header"
                      :visible { header != "" && header != "null" ? "true" : "false" }
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
                      (box :class "icon"
                          :visible {font-icon == "" ? "true" : "false"}
                          :valign "center"
                          :halign "start"
                          :hexpand false
                          :style "background-image: url(\"''${icon}\")")
                      (label :class "icon" :visible {font-icon != "" ? "true" : "false"} :text font-icon)
                      (box :class "text"
                          :valign "center"
                          :orientation "v"
                          :spacing 3
                          :halign "start"
                          :hexpand true
                          (label :halign "start" :class "title" :text title)
                          (label :visible {subtitle != "" ? "true" : "false"} :halign "start" :class "subtitle" :text subtitle :limit-width 13))))))

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
                        :onclick "''${EWW_CMD} close quick-settings closer & ''${EWW_CMD} update volume-mixer-visible=false & ${pkgs.bt-launcher}/bin/bt-launcher &")
                    (box
                        :hexpand true
                        :vexpand true
                        :class "spacer"))))

          ;; Battery Widget In Quick Settings ;;
          (defwidget etc []
              (box :orientation "h"
                  :space-evenly true
                  :spacing 10
                  (widget_button
                      :visible { EWW_BATTERY != "" ? "true" : "false" }
                      :header "Battery"
                      :title {EWW_BATTERY != "" ? "''${battery.capacity}%" : "100%"}
                      :subtitle { battery.status == 'Charging' ? "Charging" :
                                  battery.hours != "0" && battery.minutes != "0" ? "''${battery.hours}h ''${battery.minutes}m" :
                                  battery.hours == "0" && battery.minutes != "0" ? "''${battery.minutes}m" :
                                  battery.hours != "0" && battery.minutes == "0" ? "''${battery.hours}h" :
                                  "" }
                      :icon { battery.capacity < 10 ? "${pkgs.ghaf-artwork}/icons/battery-0.svg" :
                              battery.capacity < 30 ? "${pkgs.ghaf-artwork}/icons/battery-1.svg" :
                              battery.capacity < 70 ? "${pkgs.ghaf-artwork}/icons/battery-2.svg" : 
                                                      "${pkgs.ghaf-artwork}/icons/battery-3.svg" })
                  (widget_button
                      :icon "${pkgs.ghaf-artwork}/icons/admin-cog.svg"
                      :header "Settings"
                      :onclick "''${EWW_CMD} close quick-settings closer & ''${EWW_CMD} update volume-mixer-visible=false & ${pkgs.ctrl-panel}/bin/ctrl-panel >/dev/null &")))
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
              (etc)
              (sys_sliders)))

      ;; Power Menu Widget ;;
      (defwidget power-menu-widget []
          (desktop-widget
              (power_menu)))

      ;; Brightness Popup Widget ;;
      (defwidget brightness-popup []
          (revealer :transition "crossfade" :duration "200ms" :reveal brightness-popup-visible :active false
              (desktop-widget :class "popup"
                  (sys_slider
                      :valign "center"
                      :icon { brightness.screen.level == 0 ? "${pkgs.ghaf-artwork}/icons/brightness-0.svg" :
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
                  (sys_slider
                      :valign "center"
                      :icon { volume.system.muted == "true" || volume.system.level == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                              volume.system.level <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                              volume.system.level <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" }
                      :level {volume.system.level}))))

      ;; Workspace Popup Widget ;;
      (defwidget workspace-popup []
          (revealer :transition "crossfade" :duration "200ms" :reveal workspace-popup-visible :active false
              (desktop-widget :class "popup"
                  (label :text "Desktop ''${workspace}"))))

      ;; Quick Settings Button ;;
      (defwidget quick-settings-button [screen bat-icon vol-icon bright-icon]
          (button :class "icon_button"
              :onclick "''${EWW_CMD} update volume-mixer-visible=false & ${ewwScripts.eww-open-widget}/bin/eww-open-widget quick-settings \"''${screen}\" &"
              (box :orientation "h"
                  :space-evenly "false"
                  :spacing 14
                  :valign "center"
                  (box :class "icon"
                      :hexpand false
                      :style "background-image: url(\"''${bright-icon}\")")
                  (box :class "icon"
                      :hexpand false
                      :style "background-image: url(\"''${vol-icon}\")")
                  (box :class "icon"
                      :hexpand false
                      :style "background-image: url(\"''${bat-icon}\")"))))

      ;; Power Menu Launcher ;;
      (defwidget power-menu-launcher [screen]
          (button :class "icon_button icon" 
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
          (eventbox :onclick "(''${EWW_CMD} close ''${window} closer) &"))
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
                  :vol-icon { volume.system.muted == "true" || volume.system.level == 0 ? "${pkgs.ghaf-artwork}/icons/volume-0.svg" :
                              volume.system.level <= 25 ? "${pkgs.ghaf-artwork}/icons/volume-1.svg" :
                              volume.system.level <= 75 ? "${pkgs.ghaf-artwork}/icons/volume-2.svg" : "${pkgs.ghaf-artwork}/icons/volume-3.svg" }
                  :bat-icon { battery.capacity < 10 ? "${pkgs.ghaf-artwork}/icons/battery-0.svg" :
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
              :class "icon_button date" "''${formattime(EWW_TIME, "%H:%M  %a %b %-d")}"))

      ;; Calendar ;;
      (defwidget cal []
          (desktop-widget 
              (calendar :class "cal" 
                  :show-week-numbers false
                  :day calendar_day
                  :month calendar_month
                  :year calendar_year)))

      ;; Left Widgets ;;
      (defwidget workspaces []
          (box :class "workspace"
              :orientation "h"
              :space-evenly "false"
              (button :class "icon_button"
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
                                (button :class "icon_button"
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
