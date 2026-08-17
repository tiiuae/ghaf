# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Custom Ghaf theme for Plymouth
# For more information on Plymouth script usage, see https://www.freedesktop.org/wiki/Software/Plymouth/Scripts/
{
  lib,
  cfg,
  colors,
  # Number of "throbber-NNNN.png" frames shipped by Plymouth's own "spinner"
  # theme. Kept as a plain integer (rather than discovered via readDir) so
  # evaluating this file never needs to build pkgs.plymouth first.
  spinnerFrameCount,
}:
let
  backgroundColor = with colors; "${base00-dec-r}, ${base00-dec-g}, ${base00-dec-b}";

  foregroundColor = with colors; "${base05-dec-r}, ${base05-dec-g}, ${base05-dec-b}";
in
builtins.toFile "ghaf-plymouth-theme" ''
  center_x = Window.GetWidth() / 2;
  center_y = Window.GetHeight() / 2;
  baseline_y = Window.GetHeight() * 0.9;
  message_y = Window.GetHeight() * 0.75;

  ### BACKGROUND ###

  Window.SetBackgroundTopColor(${backgroundColor});
  Window.SetBackgroundBottomColor(${backgroundColor});

  ### LOGO ###

  logo.image = Image("logo.png");
  logo.sprite = Sprite(logo.image);

  ### SPINNER ###
  # Plymouth's own "spinner" theme throbber animation, shown under the logo.

  spinner.active = ${if cfg.spinnerAnimated then "1" else "0"};
  spinner.index = 0;
  spinner.tick = 0;
  spinner.frame_count = ${toString spinnerFrameCount};
  spinner.ticks_per_frame = 2;

  for (i = 1; i <= spinner.frame_count; i++) {
    if (i < 10)
      frame_name = "throbber-000" + i + ".png";
    else if (i < 100)
      frame_name = "throbber-00" + i + ".png";
    else
      frame_name = "throbber-0" + i + ".png";
    spinner.image[i - 1] = Image(frame_name);
  }

  ### LAYOUT ###
  # Position the logo and spinner as a single group, vertically centered.

  group_gap = Window.GetHeight() * 0.15;
  group_height = logo.image.GetHeight() + group_gap + spinner.image[0].GetHeight();
  group_top = center_y - (group_height / 2);

  logo.sprite.SetPosition(
    center_x - (logo.image.GetWidth() / 2),
    group_top,
    1
  );

  spinner.sprite = Sprite(spinner.image[0]);
  spinner.sprite.SetPosition(
    center_x - (spinner.image[0].GetWidth() / 2),
    group_top + logo.image.GetHeight() + group_gap,
    1
  );
  spinner.sprite.SetOpacity(spinner.active);

  fun activate_spinner () {
    spinner.active = 1;
    spinner.sprite.SetOpacity(1);
  }

  fun deactivate_spinner () {
    spinner.active = 0;
    spinner.sprite.SetOpacity(0);
  }

  fun refresh_callback () {
    if (spinner.active) {
      spinner.tick = (spinner.tick + 1) % spinner.ticks_per_frame;
      if (spinner.tick == 0) {
        spinner.index = (spinner.index + 1) % spinner.frame_count;
        spinner.sprite.SetImage(spinner.image[spinner.index]);
      }
    }
  }

  Plymouth.SetRefreshFunction(refresh_callback);

  ### PASSWORD ###

  prompt = null;
  bullets = null;
  bullet.image = Image.Text("•", ${foregroundColor});

  fun password_callback (prompt_text, bullet_count) {
    ${lib.optionalString cfg.spinnerAnimated "deactivate_spinner();"}

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
      ${lib.optionalString cfg.spinnerAnimated "deactivate_spinner();"}

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

  status_text = "";
  boot_mode = Plymouth.GetMode();
  ${lib.optionalString (cfg.bootLabel != "") ''
    if (boot_mode == "boot")
      status_text = "${cfg.bootLabel}";
  ''}

  if (status_text != "") {
    status.image = Image.Text(status_text, ${foregroundColor});
    status.sprite = Sprite(status.image);
    status.sprite.SetPosition(
      center_x - status.image.GetWidth() / 2,
      message_y,
      1
    );
  }

  ### NORMAL ###

  fun normal_callback() {
      prompt = null;
      bullets = null;

      question = null;
      answer = null;

      message = null;

      ${lib.optionalString cfg.spinnerAnimated "activate_spinner();"}
  }

  Plymouth.SetDisplayNormalFunction(normal_callback);

  ### QUIT ###

  fun quit_callback() {
    prompt = null;
    bullets = null;
    ${lib.optionalString cfg.spinnerAnimated "deactivate_spinner();"}
  }

  Plymouth.SetQuitFunction(quit_callback);
''
