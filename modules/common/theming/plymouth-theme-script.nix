# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Custom Ghaf theme for Plymouth
# For more information on Plymouth script usage, see https://www.freedesktop.org/wiki/Software/Plymouth/Scripts/
{
  lib,
  cfg,
  colors,
}:
let
  backgroundColor = with colors; "${base00-dec-r}, ${base00-dec-g}, ${base00-dec-b}";

  foregroundColor = with colors; "${base05-dec-r}, ${base05-dec-g}, ${base05-dec-b}";
in
builtins.toFile "ghaf-plymouth-theme" ''
  center_x = Window.GetWidth() / 2;
  center_y = Window.GetHeight() / 2;
  baseline_y = Window.GetHeight() * 0.9;
  message_y = Window.GetHeight() * 0.70;

  ### BACKGROUND ###

  Window.SetBackgroundTopColor(${backgroundColor});
  Window.SetBackgroundBottomColor(${backgroundColor});

  ### LOGO ###
  # Pulses the logo's opacity in a slow sine wave ("breathing") in place of
  # a spinner, to indicate progress without a separate throbber graphic.

  logo.image = Image("logo.png");
  logo.sprite = Sprite(logo.image);
  logo.sprite.SetPosition(
    center_x - (logo.image.GetWidth() / 2),
    center_y - (logo.image.GetHeight() / 2),
    1
  );

  breathe.active = ${if cfg.logoBreathing then "1" else "0"};
  breathe.tick = 0;
  breathe.period = 80; # ticks per full breathe cycle, at 50 ticks/second
  breathe.min_opacity = 0.35;

  fun activate_breathe () {
    breathe.active = 1;
  }

  fun deactivate_breathe () {
    breathe.active = 0;
    breathe.tick = 0;
    logo.sprite.SetOpacity(1);
  }

  fun refresh_callback () {
    if (breathe.active) {
      breathe.tick = (breathe.tick + 1) % breathe.period;
      phase = (breathe.tick / breathe.period) * 2 * Math.Pi;
      opacity = breathe.min_opacity + (1 - breathe.min_opacity) * (0.5 + 0.5 * Math.Sin(phase));
      logo.sprite.SetOpacity(opacity);
    }
  }

  Plymouth.SetRefreshFunction(refresh_callback);

  ### PASSWORD ###

  prompt = null;
  bullets = null;
  bullet.image = Image.Text("•", ${foregroundColor});

  fun password_callback (prompt_text, bullet_count) {
    ${lib.optionalString cfg.logoBreathing "deactivate_breathe();"}

    prompt.image = Image.Text(prompt_text, ${foregroundColor});
    prompt.sprite = Sprite(prompt.image);
    prompt.sprite.SetPosition(
      center_x - (prompt.image.GetWidth() / 2),
      baseline_y - prompt.image.GetHeight(),
      1
    );

    total_width = bullet_count * bullet.image.GetWidth();
    start_x = center_x - (total_width / 2);

    bullets = null;
    for (i = 0; i < bullet_count; i++) {
        bullets[i].sprite = Sprite(bullet.image);
        bullets[i].sprite.SetPosition(
          start_x + (i * bullet.image.GetWidth()),
          baseline_y + bullet.image.GetHeight(),
          1
        );
    }
  }

  Plymouth.SetDisplayPasswordFunction(password_callback);

  ### QUESTION ###

  question = null;
  answer = null;

  fun question_callback(prompt_text, entry) {
      ${lib.optionalString cfg.logoBreathing "deactivate_breathe();"}

      question = null;
      answer = null;

      question.image = Image.Text(prompt_text, ${foregroundColor});
      question.sprite = Sprite(question.image);
      question.sprite.SetPosition(
          center_x - (question.image.GetWidth() / 2),
          baseline_y - question.image.GetHeight(),
          1
      );

      answer.image = Image.Text(entry, ${foregroundColor});
      answer.sprite = Sprite(answer.image);
      answer.sprite.SetPosition(
          center_x - (answer.image.GetWidth() / 2),
          baseline_y + answer.image.GetHeight(),
          1
      );
  }

  Plymouth.SetDisplayQuestionFunction(question_callback);

  ### MESSAGE ###

  message = null;

  fun message_callback(text) {
      message.image = Image.Text(text, ${foregroundColor});
      message.sprite = Sprite(message.image);
      message.sprite.SetPosition(
          center_x - message.image.GetWidth() / 2,
          message_y,
          1
      );
  }

  Plymouth.SetMessageFunction(message_callback);

  ### STATUS ###
  # Show a mode-specific status message. Uses its own sprite rather than
  # message_callback's, since normal_callback nulls out "message" (and with
  # it, the last script reference to message.sprite) almost immediately
  # after this runs, which would otherwise remove it before it's ever seen.

  status = null;
  status_text = "";
  boot_mode = Plymouth.GetMode();
  ${lib.optionalString (cfg.bootLabel != "") ''
    if (boot_mode == "boot")
      status_text = "${cfg.bootLabel}";
  ''}

  fun set_status_text (text) {
    status_text = text;
    status.image = Image.Text(status_text, ${foregroundColor});
    status.sprite = Sprite(status.image);
    status.sprite.SetPosition(
      center_x - status.image.GetWidth() / 2,
      message_y,
      1
    );
  }

  if (status_text != "") {
    set_status_text(status_text);
  }

  ${lib.optionalString cfg.liveUpdates ''
    # A second, smaller status line below bootLabel, showing whatever any
    # process last reported via `plymouth --update="<text>"`. Unfiltered -
    # systemd itself sends one of these for every unit that starts while the
    # splash is up, so this doubles as a raw view of current boot progress.
    live_status = null;
    live_status_y = message_y + Window.GetHeight() * 0.05;

    fun set_live_status_text (text) {
      live_status.image = Image.Text(text, ${foregroundColor});
      live_status.sprite = Sprite(live_status.image);
      live_status.sprite.SetPosition(
        center_x - live_status.image.GetWidth() / 2,
        live_status_y,
        1
      );
    }

    fun update_status_callback (text) {
      if (text != "")
        set_live_status_text(text);
    }

    Plymouth.SetUpdateStatusFunction(update_status_callback);
  ''}

  ### NORMAL ###

  fun normal_callback() {
      prompt = null;
      bullets = null;

      question = null;
      answer = null;

      message = null;

      ${lib.optionalString cfg.logoBreathing "activate_breathe();"}
  }

  Plymouth.SetDisplayNormalFunction(normal_callback);

  ### QUIT ###

  fun quit_callback() {
    prompt = null;
    bullets = null;
    ${lib.optionalString cfg.logoBreathing "deactivate_breathe();"}
  }

  Plymouth.SetQuitFunction(quit_callback);
''
