# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Ghaf lock screen layout
# Base layout taken from gtklock upstream: https://github.com/jovanlanik/gtklock/blob/master/res/gtklock.ui 
{
  writeText,
  ...
}:
writeText "gtklock.ui.xml" ''
  <?xml version="1.0" encoding="UTF-8"?>
  <interface>
      <object class="GtkBox" id="window-box">
          <property name="name">window-box</property>
          <property name="margin">100</property>
          <property name="halign">center</property>
          <property name="valign">center</property>
          <property name="orientation">vertical</property>
          <property name="spacing">30</property>
          <child>
              <object class="GtkBox" id="info-box">
                  <property name="name">info-box</property>
                  <property name="halign">center</property>
                  <property name="orientation">vertical</property>
                  <property name="spacing">10</property>
                  <child>
                      <object class="GtkBox" id="time-box">
                          <property name="name">time-box</property>
                          <property name="halign">center</property>
                          <property name="orientation">vertical</property>
                          <child>
                              <object class="GtkLabel" id="clock-label">
                                  <property name="name">clock-label</property>
                                  <property name="halign">center</property>
                              </object>
                          </child>
                          <child>
                              <object class="GtkLabel" id="date-label">
                                  <property name="name">date-label</property>
                                  <property name="halign">center</property>
                              </object>
                          </child>
                      </object>
                  </child>
              </object>
          </child>
          <child>
              <object class="GtkRevealer" id="body-revealer">
                  <property name="transition-type">crossfade</property>
                  <property name="reveal-child">0</property>
                  <child>
                      <object class="GtkGrid" id="body-grid">
                          <property name="row-spacing">30</property>
                          <property name="column-spacing">5</property>
                          <child>
                              <object class="GtkEntry" id="input-field">
                                  <property name="name">input-field</property>
                                  <property name="placeholder-text" translatable="yes">Password</property>
                                  <property name="width-request">380</property>
                                  <property name="visibility">0</property>
                                  <property name="caps-lock-warning">0</property>
                                  <property name="input-purpose">password</property>
                                  <property name="secondary-icon-name">view-reveal-symbolic</property>
                                  <signal name="icon-release" handler="window_pw_toggle_vis"/>
                                  <signal name="activate" handler="window_pw_check"/>
                              </object>
                              <packing>
                                  <property name="left-attach">1</property>
                                  <property name="top-attach">0</property>
                                  <property name="width">2</property>
                              </packing>
                          </child>
                          <child>
                              <object class="GtkRevealer" id="message-revealer">
                                  <property name="transition-type">none</property>
                                  <property name="no-show-all">1</property>
                                  <child>
                                      <object class="GtkScrolledWindow" id="message-scrolled-window">
                                          <property name="hscrollbar-policy">never</property>
                                          <property name="max-content-height">256</property>
                                          <property name="propagate-natural-height">1</property>
                                          <child>
                                              <object class="GtkViewport">
                                                  <child>
                                                      <object class="GtkBox" id="message-box">
                                                          <property name="orientation">vertical</property>
                                                          <property name="homogeneous">1</property>
                                                      </object>
                                                  </child>
                                              </object>
                                          </child>
                                      </object>
                                  </child>
                              </object>
                              <packing>
                                  <property name="left-attach">1</property>
                                  <property name="top-attach">1</property>
                                  <property name="width">2</property>
                              </packing>
                          </child>
                          <child>
                              <object class="GtkBox">
                                  <property name="halign">center</property>
                                  <property name="valign">top</property>
                                  <property name="spacing">15</property>
                                  <property name="orientation">vertical</property>
                                  <property name="homogeneous">0</property>
                                  <property name="vexpand">true</property>
                                  <property name="hexpand">true</property>
                                  <child>
                                      <object class="GtkLabel" id="warning-label">
                                          <property name="name">warning-label</property>
                                          <property name="vexpand">true</property>
                                          <property name="hexpand">true</property>
                                      </object>
                                  </child>
                                  <child>
                                      <object class="GtkLabel" id="error-label">
                                          <property name="name">error-label</property>
                                          <property name="vexpand">true</property>
                                          <property name="hexpand">true</property>
                                      </object>
                                  </child>
                              </object>
                              <packing>
                                  <property name="left-attach">1</property>
                                  <property name="top-attach">2</property>
                                  <property name="width">2</property>
                              </packing>
                          </child>
                      </object>
                  </child>
              </object>
          </child>
      </object>
  </interface>
''
