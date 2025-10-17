<!--
    SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Working with Documentation

[![Style Guide](https://img.shields.io/badge/docs-Style%20Guide-blueviolet)](https://github.com/tiiuae/ghaf/blob/main/docs/style_guide.md) [![Glossary](https://img.shields.io/badge/docs-Glossary-pink)](https://ghaf.tii.ae/ghaf/appendices/glossary/)

This guidelines provide information on wotking with source files. For
information on manual of style recommended practices, see [Documentation Style
Guide](./style_guide.md).

Please note that improvements to the documentation are welcome.

If you notice something you can fix or improve, please follow the steps below to create a pull request.

## Directory Structure

This is a source repository for <https://ghaf.tii.ae>.

We use [Astro Starlight](https://starlight.astro.build/) and [Nix](https://nixos.org/manual/nix/stable/introduction.html) for building the documentation and GitHub Pages for hosting. Sources are written in [MDX](https://mdxjs.com/).

## Adding New Files

You should separate the documentation into chapters, sections, subsections, and subsubsections if needed.
The documentation is in MDX format, which is similar to GitHub flavored markdown.

To add new pages to the site:

1. Place the files for a specific topic into the related folder under `src/content/docs`.
2. Place the images under `src/assets/<project>`. The folder under assets refers to the site under `src/content/docs`. For example, if the `ghaf` site uses the image, it will be under `src/assets/ghaf`.
  * We make diagrams with [diagrams.net](https://www.diagrams.net/) (available online) or [draw.io](https://drawio-app.com/blog/use-draw-io-offline/) (available offline and on a tablet).
  * To embed a diagram, make sure you use the Editable Bitmap Image format (`<imagename>.drawio.png`). Select this when you export the diagram from by ticking **Include a copy of my diagram** check box. This allows us to import it back and modify it if needed.
  * Try to use main colors according to brand colors: [Fonts and Colors](./style_guide.md#fonts-and-colors).
3. For every page you add, you need to add it in `astro.config.mjs`.

If you are unsure where to place a document or how to organize a content addition, this should not stop you from contributing. See [Managing Content](#-managing-content) for inspiration.

### Naming

Our goal is to have a clear hierarchical structure with meaningful URLs like _https://ghaf.tii.ae/ghaf/scs/slsa-framework/_. With this pattern, you can tell that you are navigating to supply chain security related documentation about SLSA framework, under the Ghaf project.

Make sure you are following the file/image naming rules:

* Use lowercase letters.
* Use hyphens or underscores instead of spaces.
* Avoid special characters.
* Use meaningful abbreviations. The file/image names should be as short as possible while retaining enough meaning to make them identifiable.

## Managing Content

Use paragraphs to organize information in chapters, sections, and subsections.

To help others browse through content more effectively and make your topics clearer, follow the next guidelines:

* One idea per paragraph.
* Keep the number of sentences in each paragraph between 3 and 5.
* The first two paragraphs in each topic must state the most important information.

Build each topic based on the following structure:
* First paragraph. Introduction, main idea. [1-2 paragraphs]
* Develop the idea, add details. [1 paragraph]
* More information, less important. [optional, 1 paragraph]
* Conclusion. Transition to the next paragraph. [1-2 sentences]

## Contributing

If you would like to contribute, please read [CONTRIBUTING.md](../CONTRIBUTING.md) and consider opening a pull request. One or more maintainers will use GitHub's review feature to review your pull request.

In addition, you can use [issues](https://github.com/tiiuae/ghaf/issues) to track suggestions, bugs, and other information.
