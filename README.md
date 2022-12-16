Documentation for TII SSRC Secure Technologies: Ghaf Framework
=============

Modified in test PR.

The Ghaf project is an open-source framework for enhancing secrurity through compartmentalization on edge devices. You can find the source code that we use in the following repositories:

* https://github.com/tiiuae/build-configurations
* https://github.com/tiiuae/sbomnix

Directory Structure
------------

This is a source repository for https://tiiuae.github.io/ghaf/overview.html.

We use [mdBook](https://rust-lang.github.io/mdBook/index.html) and [Nix](https://nixos.org/manual/nix/stable/introduction.html) for building the documentation and GitHub pages for hosting.

The basic directory structure description:

```
.
├── .github/workflows/
|   └── doc.yml
├── src/
|   ├── SUMMARY.md
|   ├── img/
|   ├── chapter-1/
|	|   ├── section-1.1.md
|	|   └── section-1.n.md
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

Contributing
------------

If you would like to contribute, please read [Contributing](CONTRIBUTING.md) and consider opening a pull request.
