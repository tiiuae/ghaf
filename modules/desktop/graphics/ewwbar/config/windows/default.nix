# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  writeText,
  lib,
  useGivc,
  ...
}:
writeText "windows.yuck" ''
  ;; Bar Window ;;
      (defwindow bar [screen ?width]
          :geometry (geometry
                      :x "0px"
                      :y "0px"
                      :height "28px"
                      :width {width ?: "100%"}
                      :anchor "top center")
          :focusable "none"
          :hexpand "false"
          :vexpand "false"
          :stacking "fg"
          :exclusive "true"
          (bar :screen screen))

      ;; Window manager window ;;
        (defwindow window-manager
            :geometry (geometry :y "35px"
                                :x "0px"
                                :anchor "bottom center")
            :stacking "overlay"
            (window-manager))

      ;; Window manager trigger zone ;;
      (defwindow window-manager-trigger [screen]
          :geometry (geometry :width "500px"
                              :height "2px"
                              :anchor "bottom center")
          :stacking "overlay"
          :focusable "none"
          (window-manager-trigger :screen screen))

      ;; Calendar Window ;;
      (defwindow calendar
          :geometry (geometry :y "0px"
                              :x "0px"
                              :anchor "top center")
          :stacking "overlay"
          (cal))

      ;; Power menu window ;;
      (defwindow power-menu
          :geometry (geometry :y "0px"
                              :x "0px"
                              :anchor "top right")
          :stacking "overlay"
          (power-menu-widget))

      ${lib.optionalString useGivc ''
        ;; Quick settings window ;;
        (defwindow quick-settings
            :geometry (geometry :y "0px"
                                :x "0px"
                                :width "360px"
                                :anchor "top right")
            :stacking "overlay"
            (quick-settings-widget))


        ;; Volume Popup Window ;;
        (defwindow volume-popup
            :monitor 0
            :geometry (geometry :y "10%"
                                :x "0px"
                                :anchor "bottom center")
            :stacking "overlay"
            :focusable "none"
            (volume-popup))

        ;; Brightness Popup Window ;;
        (defwindow brightness-popup
            :monitor 0
            :geometry (geometry :y "10%"
                                :x "0px"
                                :anchor "bottom center")
            :stacking "overlay"
            :focusable "none"
            (brightness-popup))

        ;; Workspace Popup Window ;;
        (defwindow workspace-popup
            :monitor 0
            :geometry (geometry :y "10%"
                                :x "0px"
                                :anchor "bottom center")
            :stacking "overlay"
            :focusable "none"
            (workspace-popup))
      ''}

      ;; Closer Window ;;
      (defwindow closer [window]
          :geometry (geometry :width "300%" :height "300%")
          :stacking "overlay"
          :focusable "none"
          (closer :window window))
''
