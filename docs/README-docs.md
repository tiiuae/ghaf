<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Working with Documentation

[![Style Guide](https://img.shields.io/badge/docs-Style%20Guide-blueviolet)](https://github.com/tiiuae/ghaf/blob/main/docs/style_guide.md) [![Glossary](https://img.shields.io/badge/docs-Glossary-pink)](https://tiiuae.github.io/ghaf/appendices/glossary.html)

This guidelines provide information on wotking with source files. For information on manual of style recommended practices, see [Documentation Style Guide](./style_guide.md).

- [Working with Documentation](#working-with-documentation)
  - [Directory Structure](#directory-structure)
  - [Adding New Files](#adding-new-files)
    - [Naming](#naming)
  - [Managing Content](#managing-content)
  - [Contributing](#contributing)

Please note that improvements to the documentation are welcome.

If you notice something that can be fixed or improved, please follow the steps below to create a pull request.


## Directory Structure

This is a source repository for <https://tiiuae.github.io>.

We use [mdBook](https://rust-lang.github.io/mdBook/index.html) and [Nix](https://nixos.org/manual/nix/stable/introduction.html) for building the documentation and GitHub Pages for hosting. Sources are written in Markdown.

The `docs` folder of this repository is used to generate the documentation site. The basic directory structure looks like:

```
...
├── docs
│   ├── README.md
│   ├── book.toml
│   ├── doc.nix
│   ├── src
│   │   ├── SUMMARY.md
│   │   ├── index.md
│   │   ├── chapter-1
│   │   │   └── section-1.1.md
│   │   ├── chapter-2
│   │   │   ├── section-2.1.md
│   │   │   └── section-2.2.md
│   │   ├── chapter-N
│   │   │   └── section-N.1.md
│   │   ├── img
│   │   │   └── image_name.drawio.png
│   └── style_guide.md
...

```

| File | Description |
| -------- | ----------- |
| `book.toml` | Stores [configuration](https://rust-lang.github.io/mdBook/format/configuration/index.html) data. |
| `doc.nix` | Builds and deploys the generated book. |
| `SUMMARY.md` | Table of contents.  All listed Markdown files will be transformed as HTML. For more information, see [SUMMARY.md](https://rust-lang.github.io/mdBook/format/summary.html). |
| `index.md` | The main page of the website that is rendered to `index.html` in the book. This [preprocessor is built-in](https://rust-lang.github.io/mdBook/format/configuration/preprocessors.html?highlight=readme#configuring-preprocessors) and included by default. Make sure to keep `index.md` out of any subdirectory. |



## Adding New Files

The documentation is separated into chapters, sections, subsections, and subsubsections if needed.

To add new pages to the book:

1.  Put files for a specific topic into the related folder:

| Folder | Description |
| --------- | ----------- |
| `src/chapter-name/...` | Top-level folders with high-level information: _architecture_, _technologies_, _build configurations_, etc.|
| `src/chapter-name/section-name/...`, `src/chapter-name/subsection-name/...` | Documentation related to the special topic. Use subsections within the section when the subject changes, but you are still writing about a particular aspect of a larger subject. Note that both section and subsection files are in the chapter folder. |

2. Put images into the `src/img` folder. We make diagrams with [diagrams.net](https://www.diagrams.net/) (use it online) or [draw.io](https://drawio-app.com/blog/use-draw-io-offline/) (use it offline and on a tablet).
    
    * To embed a diagram, make sure that you use the Editable Bitmap Image format `<imagename>.drawio.png`. When creating a new diagram, choose *Editable Bitmap Image format (.png)* from the list. When editing the existing diagram, select **File > Export as > PNG...** and select the **Include a copy of my diagram** check box.

    * Try to use main colors according to brand colors: [Fonts and Colors](./style_guide.md#fonts-and-colors).
    
3. Add new structure elements (chapters, sections, subsections) to **SUMMARY.md** to update the table of contents. Otherwise, the files that you added will not be visible on GitHub Pages. Example:

```
- [Chapter-name](src/chapter-name.md)
    - [Section-name.md](src/chapter-name/section-name.md)
        - [Subsection.md](src/chapter-name/subsection-name.md)
    - [Section-name.md](src/chapter-name/section-name.md)
        - [Subsection.md](src/chapter-name/subsection-name.md)
```

If you are unsure where to place a document or how to organize a content addition, this should not stop you from contributing. See [Managing Content](#-managing-content) for inspiration. You can also ask a technical writer [Jenni Nikolaenko](https://github.com/jenninikko) at any stage in the process.


### Naming

Our goal is to have a clear hierarchical structure with meaningful URLs like _tiiuae.github.io/ghaf/scs/slsa-build-system.html_. With this pattern, you can tell that you are navigating to supply chain security related documentation about SLSA build system. 

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
