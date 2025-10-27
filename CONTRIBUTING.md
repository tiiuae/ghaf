<!--
    SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Welcome Contributors!

We like commits as they keep the project going. If you have ideas you want to experiment with, make a fork and see how it works. Use pull requests if you are unsure and suggest changes to our maintainers.

- [Welcome Contributors!](#welcome-contributors)
  - [Our Philosophy](#our-philosophy)
  - [Contributing Code](#contributing-code)
    - [Development Process](#development-process)
    - [Commit Message Guidelines](#commit-message-guidelines)
  - [Contributing Documentation](#contributing-documentation)
    - [Working with Documentation Source Files](#working-with-documentation-source-files)
    - [Submitting Changes](#submitting-changes)
    - [Manual of Style](#manual-of-style)
  - [Communication](#communication)


## Our Philosophy

* Update docs with the code.
* Content is King, consistency is Queen.
* Do not assume that readers know everything you currently know.
* Avoid jargon and acronyms, if you can.
* Do not reference future development or features that do not yet exist.


## Contributing Code

### Development Process

Pull requests should be created from personal forks. We follow a fork and rebase workflow.

> The concept of a fork originated with GitHub, it is not a Git concept. If you are new to forks, see [About forks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/about-forks) and [Contributing Guide when you fork a repository](https://medium.com/@rishabhmittal200/contributing-guide-when-you-fork-a-repository-3b97657b01fb).

Make sure the [license](https://github.com/tiiuae/ghaf#licensing) information is added on top of all your source files as in the example:

    # Copyright [year project started]-[current year], [project founder] and the [project name] contributors
    # SPDX-License-Identifier: Apache-2.0

<!--
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
-->

Generally, any contributions should pass the tests.

Documentation is the story of your code. Update Ghaf documentation with the code. Good documentation helps to bring new developers in and helps established developers work more effectively.

> Make sure to run spelling checking tools to catch common miss spellings before making a pull request. For example, you can use [aspell](https://www.manuel-strehl.de/check_markdown_spelling_with_aspell) in Linux/UNIX.


### Commit Message Guidelines

We use the Linux kernel compatible commit message format.

The seven rules of a great Git commit message:

1. Separate subject from body with a blank line.
2. Limit the subject line to 50 characters.
3. Capitalize the subject line. If you start subject with a filename, capitalize after colon: “approve.sh: Fix whitespaces”.
4. Do not end the subject line with a period. For example:
5. Use the imperative (commanding) mood in the subject line.
    * ”Fix a bug causing reboots on nuc” rather than “Fixed a bug causing reboots on nuc”.
    * ”Update weston to version 10.5.1” rather than ”New weston version 10.5.1”.
6. Wrap the body at 72 characters.
7. Use the body to explain **what** and **why** vs. how.

Example:
```
Subject line: explain the commit in one line

Body of commit message is a few lines of text, explaining things
in more detail, possibly giving some background about the issue
being fixed, etc etc.

The body of the commit message can be several paragraphs, and
please do proper word-wrap and keep columns shorter than about
72 characters or so. That way "git log" will show things
nicely even when it's indented.

Signed-off-by: Your Name <youremail@yourhost.com>
```

The seven rules of a great Git commit message are originally from Google. Original commit message example is from Linus Torvalds. Both have been modified. Comments and suggestions are welcome.

---

## Contributing Documentation

The Ghaf project is free and open source. We use [Starlight](https://starlight.astro.build) and [Nix](https://nixos.org/manual/nix/stable/introduction.html) for building the documentation and GitHub Pages for hosting. Sources are written in Markdown.

### Working with Documentation Source Files

See the following instructions:

- [Adding New Files](https://github.com/tiiuae/ghaf/blob/main/docs/README-docs.md#adding-new-files) for information on how to manage files/images.
- [Naming](https://github.com/tiiuae/ghaf/blob/main/docs/README-docs.md#naming) for information on file/image naming rules.
- [Managing Content](https://github.com/tiiuae/ghaf/blob/main/docs/README-docs.md#managing-content) for information on how to organize information in chapters, sections, and subsections.


### Submitting Changes

Create a pull request to propose and collaborate on changes to a repository. Please follow the steps below:

1. Fork the project repository.
2. Clone the forked repository to your computer.
3. Create and switch into a new branch with your changes: `git checkout -b doc_my_changes`
4. [Make your changes](#working-with-documentation-source-files).
5. :sunglasses: Check what you wrote with a spellchecker to make sure you did not miss anything.
6. Test your changes before submitting a pull request using the `nix build .#doc` command.
7. Commit your changes: `git commit --signoff`
    - Use "Docs:" in the subject line to indicate the documentation changes. For example: **Docs: rename "Research" to "Research Notes"**.
    - Keep text hard-wrapped at 50 characters.
    - For more inspiration, see [How to Write a Git Commit Message](https://cbea.ms/git-commit/).
8. Push changes to the main branch: `git push origin doc_my_changes`
9. Submit your changes for review using the GitHub UI.
10. After publishing keep your ear to the ground for any feedback and comments in [Pull requests](https://github.com/tiiuae/ghaf/pulls).

When a merge to main occurs it will automatically build and deploy to <https://ghaf.tii.ae>.


### Manual of Style

For information on recommended practices, see [Documentation Style Guide](./docs/style_guide.md).

---

## Communication

GitHub issues are the primary way for communicating about specific proposed changes to this project.

If you want to join the project team, just let us know.
