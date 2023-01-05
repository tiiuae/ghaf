# Documentation for TII SSRC Secure Technologies: Ghaf Framework

The Ghaf project is an open-source framework for enhancing secrurity through compartmentalization on edge devices. The source code that we use is in the following repositories:

* https://github.com/tiiuae/build-configurations
* https://github.com/tiiuae/sbomnix


## Directory Structure

This is a source repository for https://tiiuae.github.io/ghaf/about/overview.html.

We use [mdBook](https://rust-lang.github.io/mdBook/index.html) and [Nix](https://nixos.org/manual/nix/stable/introduction.html) for building the documentation and GitHub Pages for hosting.

The basic directory structure looks like:

```
.
├── .github/workflows/
|   └── doc.yml
├── src/
|   ├── SUMMARY.md
|   ├── img/
|   ├── chapter-1/
│   │   ├── section-1.1.md
|   |   └── section-1.n.md
|   └── chapter-2/
|       ├── section-2.1.md
|   	└── section-2.n.md
├── CONTRIBUTING.md
├── README.md
├── book.toml
├── doc.nix
├── flake.lock
└── flake.nix 

```
| File | Description |
| -------- | ----------- |
| `SUMMARY.md` | Table of contents.  All listed Markdown files will be transformed as HTML. For more information, see [SUMMARY.md](https://rust-lang.github.io/mdBook/format/summary.html). |
| `book.toml` | Stores [configuration](https://rust-lang.github.io/mdBook/format/configuration/index.html) data. |
| `doc.yml` | Continuous integration and delivery (Github Action workflow) for building and deploying the generated book. |
| `flake.nix ` | Describes dependencies and provides output package. To see provided outputs, type `nix flake show`. |
| `flake.lock` | Pins dependencies of flake inputs. |


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


## Naming

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

[//]: # (Link to Style Guide.)
[//]: # (Link to Glossary.)


## Contributing

If you would like to contribute to the documentation, please read [CONTRIBUTING.md](CONTRIBUTING.md) and consider opening a pull request. One or more maintainers will use GitHub's review feature to review your pull request.

> For more information on contributing the code, see the [Contributing](https://tiiuae.github.io/ghaf/appendices/contributing_code.html) section of the Ghaf documentation.

Some things that will increase the chance that your pull request is accepted faster:
* Spelling tools usage.
* Following our Style Guide. [TBD]
* [Writing a good commit message](https://github.com/tiiuae/ghaf/blob/main/CONTRIBUTING.md#commit-message-guidelines).

If you find any bugs or errors in the content, feel free just to create an [issue](https://github.com/tiiuae/ghaf/issues). You can also use this feature to track suggestions or other information.

For questions related to repository access permissions, please contact [Ville Ilvonen](https://github.com/vilvo).


## License

Ghaf is licensed under the Attribution-ShareAlike International License, version 4.0. See [LICENSE](./LICENSE) for the full license text.