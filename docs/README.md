# Working with Documentation

This guidelines provide information on wotking with source files. For information on manual of style recommended practices, see [Documentation Style Guide](./style_guide.md).

- [Working with Documentation](#working-with-documentation)
  - [Directory Structure](#directory-structure)
  - [Working with Files](#working-with-files)
    - [Naming](#naming)
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
│   ├── book.toml
│   ├── doc.nix
│   ├── README.md
│   └── src
│       ├── chapter-1
│       │   └── section-1.1.md
│       ├── chapter-2
│       │   ├── section-2.1.md
│       │   └── section-2.2.md
│       ├── img
│       │   └── image_name.drawio.png
│       ├── SUMMARY.md
│       └── chapter-N
│           └── section-N.1.md
...

```

| File | Description |
| -------- | ----------- |
| `SUMMARY.md` | Table of contents.  All listed Markdown files will be transformed as HTML. For more information, see [SUMMARY.md](https://rust-lang.github.io/mdBook/format/summary.html). |
| `book.toml` | Stores [configuration](https://rust-lang.github.io/mdBook/format/configuration/index.html) data. |
| `doc.nix` | Builds and deploys the generated book. |


## Working with Files

The documentation is separated into chapters, sections, subsections, and subsubsections if needed.

**To add new pages to the book:**

1. Put files for a specific topic into the related folder:

| Folder | Description |
| --------- | ----------- |
| `src/chapter-name/...` | Top-level folders with high-level information: _about_, _architecture_, _technologies_, _build configurations_, etc.|
| `src/chapter-name/section-name/...`, `src/chapter-name/subsection-name/...` | Documentation related to the special topic. Use subsections within the section when the subject changes, but you are still writing about a particular aspect of a larger subject. Note that both section and subsection files are in the chapter folder. |

2. Put images into the `src/img` folder. We make diagrams with [draw.net](https://www.diagrams.net/).
    
    To embed a diagram, make sure that you use the following image format `<imagename>.drawio.png`. When editing your diagram, select **File > Export as > PNG...** and select the **Include a copy of my diagram** check box.
    
3. Add new structure elements (chapters, sections, subsections) to **SUMMARY.md** to update the table of contents. Example:

```
- [Chapter-name](src/chapter-name.md)
    - [Section-name.md](src/chapter-name/section-name.md)
        - [Subsection.md](src/chapter-name/subsection-name.md)
    - [Section-name.md](src/chapter-name/section-name.md)
        - [Subsection.md](src/chapter-name/subsection-name.md)
```

If you are unsure where to place a document or how to organize a content addition, this should not stop you from contributing. See [Managing Content](#-managing-content) for inspiration. You can also ask a technical writer [Jenni Nikolaenko](https://github.com/jenninikko) at any stage in the process.

[//]: # (Link to Style Guide.)
[//]: # (Link to Glossary.)


### Naming

Our goal is to have a clear hierarchical structure with meaningful URLs like _tiiuae.github.io/ghaf/scs/slsa-build-system.html_. With this pattern, you can tell that you are navigating to supply chain security related documentation about SLSA build system. 

Make sure you are following the file/image naming rules:

* Use lowercase letters.
* Use hyphens or underscores instead of spaces.
* Avoid special characters.
* Use meaningful abbreviations. The file/image names should be as short as possible while retaining enough meaning to make them identifiable.


## Contributing

If you would like to contribute, please read [CONTRIBUTING.md](../CONTRIBUTING.md) and consider opening a pull request. One or more maintainers will use GitHub's review feature to review your pull request.

In addition, you can use [issues](https://github.com/tiiuae/ghaf/issues) to track suggestions, bugs, and other information.
