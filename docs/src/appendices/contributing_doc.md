# Contributing Documentation

The Ghaf project is free and open source. We use [mdBook](https://rust-lang.github.io/mdBook/index.html) and [Nix](https://nixos.org/manual/nix/stable/introduction.html) for building the documentation and GitHub Pages for hosting. Sources are written in Markdown.

Improvements to the documentation are welcome! We would love to get contributions from you.

> This guideline is about contributing to the documentation. For more information on contributing the code, see [CONTRIBUTING.md](CONTRIBUTING.md).


## Our Philosophy

* Update docs with the code.
* Content is King, consistency is Queen.
* Do not assume that readers know everything you currently know.
* Avoid jargon and acronyms, if you can.
* Do not reference future development or features that do not yet exist.


## Before You Begin

Please see the following instructions:

- [Working with Files]() for information on how to manage files and images.
- [Naming]() for information on file/image naming rules.
- [Managing Content]() for information on how to organize information in chapters, sections, and subsections.


## Submitting Changes

Create a pull request to propose and collaborate on changes to a repository. Please follow the steps below:

1. Fork the project repository.
2. Clone the forked repository to your computer.
3. Create and switch into a new branch (`git checkout -b doc_my_changes`) with your changes.
4. :four_leaf_clover: Check what you wrote with a spellchecker to make sure you did not miss anything.
5. Test your changes before submitting a pull request using the `nix build .#doc` command.
6. Commit your changes (`git commit --signoff`). Keep text hard-wrapped at 50 characters. For more inspiration, see [How to Write a Git Commit Message](https://cbea.ms/git-commit/).
7. Push changes to the main branch (`git push origin doc_my_changes`).
8. Submit your changes for review using the GitHub UI.
9. After publishing keep your ear to the ground for any feedback and comments in [Pull requests](https://github.com/tiiuae/ghaf/pulls).


## Manual of Style

Recommended practicies. TBD


## Communication

GitHub issues are the primary way for communicating about specific proposed changes to this project.

If you want to join the project team, just let us know.
