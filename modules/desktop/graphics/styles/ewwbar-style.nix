# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  fontName,
  ...
}:
''
  $bg-primary: #121212;
  $widget-bg: #1A1A1A;
  $widget-hover: #282828;
  $bg-secondary: #2B2B2B;
  $text-base: #FFFFFF;
  $text-disabled: #9c9c9c;
  $text-success: rgba(90, 195, 121, 1);
  $icon-subdued: #3D3D3D;
  $stroke-success: rgba(90, 195, 121, 1);
  $stroke-success-muted: rgba(90, 195, 121, 0.75);
  $font-bold: 600;

  @mixin unset($rec: false) {
      all: unset;

      @if $rec {
          * {
              all: unset
          }
      }
  }

  * {
      color: $text-base;
      font-family: "${fontName}";
      :disabled {
          color: $text-disabled;
      }
  }

  window.background {
      background-color: transparent;
  }

  tooltip {
      background-color: $bg-primary;
  }

  @mixin widget($bg: $bg-primary, $padding: 10px, $radius: 12px){
      border-radius: $radius;
      background-color: $bg;
      padding: $padding;
  }

  @mixin floating_widget($bg: $bg-primary, $margin: 0.3em 0.3em 0em 0em, $padding: 14px, $radius: 12px, $unset: true) {
      @if $unset {
        @include unset;
      }
      background-color: $bg;
      border-radius: $radius;
      margin: $margin;
      padding: $padding;
  }

  @mixin icon(){
      background-color: transparent;
      background-repeat: no-repeat;
      background-position: center;
      background-size: contain;
      min-height: 24px;
      min-width: 24px;
      color: #FFFFFF;
  }

  @mixin button($bg: transparent, $hover-bg: $widget-hover) {
      @include unset;
      @include icon;

      border-radius: 0.25em;
      padding: 0.4em;
      background-color: $bg;

      .icon{
          @include icon;
      }

      &:hover {
          transition: 200ms linear background-color;
          background-color: $hover-bg;
      }

      &:active {
          transition: 200ms linear background-color;
          background-color: #1F1F1F;
      }
  }

  @mixin slider($slider-width: 150px, $slider-height: 2px, $thumb: true, $thumb-width: 1em, $focusable: true, $radius: 7px, $shadows: true, $trough-bg: $widget-hover, $trough-fg: $stroke-success) {
      scale {
          padding: 0px;
      }

      trough {
          border-radius: $radius;
          border: 0;
          background-color: $trough-bg;
          min-height: $slider-height;
          min-width: $slider-width;
          margin: $thumb-width / 2;

          highlight,
          progress {
              background-color: $trough-fg;
              border-radius: $radius;
          }
      }

      slider {
          border: 0 solid transparent;
          border-radius: 50%;
          background-image: none;
          box-shadow: none;
          @if $thumb {
              background-color: #D3D3D3;
              min-height: $thumb-width;
              min-width: $thumb-width;
              margin: -($thumb-width / 2) 0;
          } @else {
              margin: 0;
              min-width: 0;
              min-height: 0;
              background-color: transparent;
          }
      }

      &:hover {
          slider {
              @if $thumb {
                  background-color: #D3D3D3;

                  @if $shadows {
                      box-shadow: 0px 0px 3px 0px $bg-primary;
                  }
              }
          }
      }

      &:disabled {
          highlight,
          progress {
              background-image: none;
          }
      }

      @if $focusable {
          trough:focus {
              box-shadow: inset 0px 0px 0px 1px $bg-primary;

              slider {
                  @if $thumb {
                      background-color: red;
                      box-shadow: inset 0px 0px 0px 1px $bg-primary;
                  }
              }
          }

      }
  }

  @mixin sys-sliders () {
      .slider{ @include slider; }

      .header {
          font-size: 0.9em;
          font-weight: $font-bold;
      }
  }

  @mixin qs-widget($min-height: 70px, $min-width: 150px, $radius: 0.75em, $bg: $widget-bg) {
      min-height: $min-height;
      min-width: $min-width;
      border-radius: $radius;
      background-color: $bg;
  }

  @mixin widget-button($min-width: 133px, $min-height: 58px, $radius: 0.75em, $bg: $widget-bg, $padding: 0.9em) {
      @include qs-widget($min-width: $min-width, $min-height: $min-height);

      .inner-box {
          padding: $padding;
          min-width: $min-width;
          min-height: $min-height;
          .header {
              font-weight: $font-bold;
              font-size: 0.9em;
          }
      }

      &:hover {
          transition: 200ms linear background-color;
          background-color: $widget-hover;
      }

      &:active {
          transition: 200ms linear background-color;
          background-color: #1F1F1F;
      }

      .icon {
          background-color: transparent;
          background-repeat: no-repeat;
          background-position: center;
          min-height: 24px;
          min-width: 24px;
      }

      .text {
          .title {
              font-size: 0.9em;
              font-weight: 500;
          }

          .subtitle {
              font-weight: 400;
              font-size: 0.8em;
              min-height: 0px;
          }
      }
  }

  .qs-widget {
      @include unset;
      @include qs-widget;
  }

  .icon { @include icon; }

  .floating-widget { @include floating_widget; }

  .qs-slider {
      @include unset;
      @include sys-sliders;
      @include qs-widget($min-height: 0px);
      padding: 0.9em;
  }

  .popup {
      .slider{ @include slider($slider-width: 150px, $thumb: false, $slider-height: 5px); }
      :disabled {
          color: $text-base;
      }
  }

  .widget-button {@include widget-button; }

  .power-menu-button {@include widget-button($min-height: 33px); }

  .eww_bar {
      background-color: $bg-primary;
  }

  .default_button {
      @include button;
      label {
        font-size: 0.9em;
      }
      .header {
        font-size: 0.9em;
        font-weight: $font-bold;
      }
  }

  .taskbar_button {
      @include button;
      padding: 2px 14px;
  }

  .divider {
      background-color: $icon-subdued;
      padding-left: 1px;
      padding-right: 1px;
      border-radius: 10px;
  }

  .time {
      padding: 0.4em 0.25em;
      border-radius: 0.25em;
      background-color: $bg-primary;
      font-weight: $font-bold;
      font-size: 1em;
  }

  .date {
      font-weight: $font-bold;
      font-size: 1em;
  }

  .keyboard-layout {
      padding: 0.4em 0.25em;
      border-radius: 4px;
      background-color: $bg-primary;
      font-weight: $font-bold;
      font-size: 1em;
  }

  .spacer {
      background-color: transparent;
  }

  .cal {
      @include unset($rec: true);
      padding: 0.2em 0.2em;

      calendar {
          padding: 0.2em 0.2em;

          &.header {
              font-weight: $font-bold;
          }

          &.button {
              color: $stroke-success;
              padding: 0.3em;
              border-radius: 4px;
              border: none;

              &:hover {
                  background-color: $bg-secondary;
              }
          }

          &.stack.month {
              padding: 0 5px;
          }
          &.label.year {
              padding: 0 5px;
          }

          &:selected {
              color: $text-success;
          }

          &:indeterminate {
              color: $text-disabled;
          }
      }
  }

  .tray menu {
      background-color: $bg-primary;

      >menuitem {
          padding: 5px 7px;

          &:hover {
              background-color: $widget-hover;
          }

          >check {
            border-width: 1px;
            border-color: transparent;
            min-height: 16px;
            min-width: 16px;
            color: transparent;
            background-color: transparent;

            &:checked {
              border-color: $text-base;
              color: $text-base;
            }
          }

          >arrow {
              color: $text-base;
              background-color: transparent;
              margin-left: 10px;
              min-height: 16px;
              min-width: 16px;
          }
      }

      >arrow {
          background-color: transparent;
          color: $text-base;
      }

      separator {
          background-color: $icon-subdued;
          padding-top: 1px;
          padding-bottom: 1px;
          border-radius: 10px;

          &:last-child {
              padding: unset;
          }
      }
  }

  .tray {
    padding: 2px 14px;
  }
''
