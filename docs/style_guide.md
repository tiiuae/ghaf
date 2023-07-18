<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

[comment]: # (blank line)  
[comment]: # (Comment text goes here.)  
[comment]: # (blank line)  
[comment]: # (Make sure add a double space after each comment line.)  

# Documentation Style Guide

Here you can find the standards we follow for writing, formatting, and organizing Ghaf documentation. Please follow these guidelines and conventions when editing the documentation.

Writing guidelines:
- [Documentation Style Guide](#documentation-style-guide)
  - [Voice and Tone](#voice-and-tone)
  - [Fonts and Colors](#fonts-and-colors)
  - [Markdown Syntax](#markdown-syntax)
  - [Headings](#headings)
  - [Spelling and Punctuation](#spelling-and-punctuation)
  - [References](#references)
  - [Tips and Tricks](#tips-and-tricks)


## Voice and Tone

* Write in plain English—a universal language that makes information clear and better to understand:
  * Use simple tenses and active voice.
  * Understandable language, fewer gerunds.
  * Short, sharp sentence. Try to use 15-20 words max.
  * [Split information in paragraphs](https://github.com/tiiuae/ghaf/tree/main/docs#managing-content).
  * Do not use parenthesis for additional information, make a separate sentence instead.
  * Use numbered lists for actions that happen in sequence.
  * Do not contract the words: use _cannot_ instead of _can’t_.
  * Do not use Latin words. For example:
    * perform operations, **etc.** ⇒ perform operations, and **so on**
    * **e.g.** a Microsoft SQL Server ⇒ **for example**, a Microsoft SQL Server
    * **via** the system ⇒ **through** the system
* Use “we” for us and our work, use “you” for readers. Do not use “please” to provide instructions, just ask what should be done.
* Avoid buzzwords, slang, and jargon.
* Readers often scan rather than read, put the important facts first.
* Do not assume that readers know everything you currently know. Provide clear instructions.
* Do not reference future development or features that do not yet exist.


## Fonts and Colors

* Font

    The [Roboto font](https://fonts.google.com/specimen/Roboto) family is used in Ghaf digital platforms. Roboto is available via an open-source license.

* Ghaf colors

    * Primary color is Light green (#5AC379).
    * Secondary colors:

        * Dark green (#3D8252), Orange (#F15025), Yellow (#FABC3C)
        * Light grey (#3A3A3A), Mid grey (#232323), Dark grey (#121212)


## Markdown Syntax

Before you begin:

* If you are new to Markdown, see [Markdown Cheat Sheet](https://www.markdownguide.org/cheat-sheet/).
* Since Ghaf documentation is built with mdBook, you can use [mdBook's team tutorial](https://rust-lang.github.io/mdBook/format/markdown.html) for general syntax as well:

  * Text and paragraphs
  * Headings
  * Lists
  * Links
  * Images
  * Extensions: strikethrough, footnotes, tables, task lists, smart punctuation


To make our Markdown files maintainable over time and across teams, follow the rules:

* Headings
  
    Add spacing to headings: two newlines before and one after.

* Code
  
    Use double backtick quotes (`) before and after the content that you want to wrap: ``x86-64``.

* Code blocks

    There are two ways to create code blocks:
    * Use three backticks (```) on the lines before and after the code block.
    * Indent every line of the block by at least four spaces or one tab. To put a code block within a list item, the code block needs to be indented twice.

* Reference to a source code

    Instead of copying and pasting the entire code, and putting it in a code block, you can create a reference to the code as in the [example](https://github.com/stevemar/code-reference-in-readme/blob/main/README.md).
    Do the following:
    * In GitHub, open the file with a source code (the source blob) and select a string or several strings (press and hold the Shift key).
    * From the menu [...], select **Copy permalink** and paste the link to your .md file.

* Notes with quoting

    Use an angle bracket (>) for annotations. For example:
    ```
    > This is a note.
    ```
    To draw more attention, you can create note blocks simply by surrounding the content with two horizontal lines. For example:
    ```
    ---
    **IMPORTANT**

    Very importamt information.

    ---
    ```

* Markdown shields (badges)

    In [README.md](../README.md) and [README-docs.md](./README-docs.md), we used those emblems so that the user can see the needed information at first glance. In fact, it is just a reference link. To make your own shield, use [shields.io](https://shields.io/).

* Unicode characters

    For GitHub .md files (not for GitHub Pages), emojis are welcome :octocat:. [Supported GitHub emojis](https://github-emoji-picker.vercel.app/).



## Headings

Capitalize words in the heading according to title case.

> Title Case: You Capitalize All Words in the Title Except for the Little Words.

For a hyphenated compound word, capitalize both parts, unless it is an article, preposition, or coordinating conjunction. For example: Step-by-Step, Ghaf-Based, Follow-Up, Non-Functional.

In Ghaf documentation, we do not use articles in headings as soon as the meaning remains clear (compare, for example: "History of China" and "The History of China"). Headlines should be attention grabbers, not full sentences.


## Spelling and Punctuation

* We use standard United States (U.S.) English throughout all technical publications.

    In cases where US spelling differs from UK spelling, use the US spelling. There is no need to fix one by replacing it with the other. 

    For additional information, see [Manual of Style Wikipedia:Manual of Style/Spelling](https://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style/Spelling) and [American and British English spelling differences](https://en.wikipedia.org/wiki/American_and_British_English_spelling_differences).

* Use serial (Oxford) commas.
  
    The Oxford comma is a comma placed immediately before a coordinating conjunction (and, or) in a series of 3 or more items.

* Write the full name when first mentioned with the acronym in brackets: *Supply Chain Security (SCS)*.
  
    For more information on abbreviations and usage of articles before them, see the [Glossary](https://tiiuae.github.io/ghaf/appendices/glossary.html) section of Ghaf documentation.

* Numbers

  * Spell out whole-number words for one to ten, use figures for numbers above ten: *two specifications*, *16 slots*.
  * Use a combination of a figure and a word for very large round numbers (such as multiple millions, billions and so on): *7 billion people*.

* Date format

    In written American English, the month of the date comes before the day and year: 
    * The full date format is month-day-year: *November 7, 2022*.
    * A shorter date format includes only numbers separated by slashes: *11/7/2022*.

    You can also follow the ISO date format YYYY-MM-DD to avoid confusion in international communication.

* Lists (bullet points)

    Do not punctuate the end of bullet points which are a list of items. Do not use articles in a list of items. For example:
    ```
    10 complicated words in English:
    * circumstance
    * flippant
    * fiancée
    * idiosyncratic
    ...
    ```
    Separate long items within a list with semicolons. Add a full stop to the end of the list point if the text inside the bullet point is a complete sentence.

* Dashes and hyphens

    * dodgy dashes:
        * em dash (—) || use to separate extra information or mark a break in a sentence 
       > Called such since the dash is approximately the width of a typed letter M in traditional typesetting.
       >
        > Also, the em dash may serve as a sort of bullet point.
       >
       > Just copy it from here or type a pair of hyphens if you do not remember the proper keyboard shortcuts.
      * en dash (–) || use to mark ranges, to show the relationship between two words, dates, or numbers -> *pages 130–232*
        > Approximately the width of a typed letter N.
    * hyphen (-) || use it to combine words -> *cross-compiler*, *machine-readable document*

    Do not use spaces before and after dashes and hyphens.

* Brackets

    parentheses or round brackets ( ), square brackets [ ], braces { }, and angle brackets ⟨ ⟩


## References

For references (additional information on sections, terms and any other issues in a document that require supplementary explanation) use the following combination:

* *for more information on X, see B* 
* *to learn how to X, see B*


## Tips and Tricks

Congratulations! You found the Room of Requirement that adjusts itself to its seeker’s needs. Items hidden inside are useful tips and tricks on issues that you face regularly when writing documentation.

> Mind that we use standard United States (U.S.) English in Ghaf documentation.

| Words | Usage |
| -------- | ----------- |
| graphs, diagrams, and charts | A [graph](https://www.collinsdictionary.com/us/dictionary/english/graph) is a representation of information using lines on two or three axes such as x, y, and z. A [diagram](https://www.collinsdictionary.com/us/dictionary/english/diagram) is a visual representation of systems and structures, and relationships between things. A [chart](https://www.collinsdictionary.com/us/dictionary/english/chart) is used to compare data. A [flow chart](https://www.collinsdictionary.com/us/dictionary/english/flow-chart) is a process diagram with steps to follow. For more information, see [What's the difference between diagrams, charts and graphs?](https://www.diagrams.net/blog/diagrams-charts-graphs).|
| white paper vs. whitepaper | Use [white paper](https://www.collinsdictionary.com/dictionary/english/white-paper) both as a term of a marketing or technical report and as a sheet of white-colored paper. |
| on the page vs. in the page | We treat web pages similar to book pages: *someting is [on the page](https://www.ldoceonline.com/dictionary/page)*. However, if you want to describe something that is in the pages' code, you can use *in the page*. For more information, see [The choice of preposition distinguishes between the surface and the container](https://english.stackexchange.com/questions/132102/why-are-you-on-a-train-yet-in-a-car-when-you-are-inside-both-vehicles/132122#132122). |
| reestablish vs. re-establish | Use **reestablish**, as it is preferred for U.S. English. |
| proofread vs. proof read | Use [proofread](https://www.collinsdictionary.com/dictionary/english/proofread) as a verb meaning to read and correct a piece of written work before publishing. |
| pass-through vs. passthrough | In Ghaf documentation, we use **passthrough** as a noun or an adjective for the device passthrough process of providing isolation of devices to a given guest OS so that the device can be used exclusively by that guest. For more information, see [Linux virtualization and PCI passthrough](https://developer.ibm.com/tutorials/l-pci-passthrough/). Use [pass through](https://www.oxfordlearnersdictionaries.com/definition/english/pass-through) as a verb meaning to go through something for a short time. |
| cross compilation vs. cross-compilation | In Ghaf documentation, we use **cross-compilation** as a noun or an adjective to describe a compilation that is performed between different devices. Use **cross-compile** as a verb meaning to build on one platform an executable binary that will run on another platform. |


Happy writing!
