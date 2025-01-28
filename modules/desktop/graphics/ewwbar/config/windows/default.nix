# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
          :focusable "false"
          :hexpand "false"
          :vexpand "false"
          :stacking "fg"
          :exclusive "true"
          (bar :screen screen))

      ;; Calendar Window ;;
      (defwindow calendar
          :geometry (geometry :y "0px"
                              :x "0px"
                              :anchor "top center")
          :stacking "fg"
          (cal))

      ;; Power menu window ;;
      (defwindow power-menu
          :geometry (geometry :y "0px"
                              :x "0px"
                              :anchor "top right")
          :stacking "fg"
          (power-menu-widget))

      ${lib.optionalString useGivc ''
        ;; Quick settings window ;;
        (defwindow quick-settings
            :geometry (geometry :y "0px"
                                :x "0px"
                                :width "360px"
                                :anchor "top right")
            :stacking "fg"
            (quick-settings-widget))


        ;; Volume Popup Window ;;
        (defwindow volume-popup
            :monitor 0
            :geometry (geometry :y "10%"
                                :x "0px"
                                :anchor "bottom center")
            :stacking "overlay"
            (volume-popup))

        ;; Brightness Popup Window ;;
        (defwindow brightness-popup
            :monitor 0
            :geometry (geometry :y "10%"
                                :x "0px"
                                :anchor "bottom center")
            :stacking "overlay"
            (brightness-popup))

        ;; Workspace Popup Window ;;
        (defwindow workspace-popup
            :monitor 0
            :geometry (geometry :y "10%"
                                :x "0px"
                                :anchor "bottom center")
            :stacking "overlay"
            (workspace-popup))
      ''}

      ;; Closer Window ;;
      (defwindow closer [window]
          :geometry (geometry :width "100%" :height "100%")
          :stacking "fg"
          :focusable false
          (closer :window window))
''
