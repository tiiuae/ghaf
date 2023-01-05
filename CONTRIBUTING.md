# Contributing Code

Welcome contributors!

We like commits as they keep the project going. These two repositories with the source code that we work on:

* <https://github.com/tiiuae/ghaf>
* <https://github.com/tiiuae/sbomnix>

If you have ideas you want to experiment with, make a fork and see how it works. Use pull requests if you are unsure and suggest changes to our maintainers.

If you are considering helping to improve the Ghaf documentation, see [Contributing Documentation](https://tiiuae.github.io/ghaf/appendices/contributing_doc.html).


## Development Process

Pull requests should be created from personal forks. We follow a fork and rebase workflow.

Generally, any contributions should pass the tests.

Make sure to update the documentation with the code: [Contributing Documentation](docs/src/appendices/contributing_doc.md). Good documentation helps to bring new developers in and helps established developers work more effectively. 


## Commit Message Guidelines

We use the Linux kernel compatible commit message format.

The seven rules of a great Git commit message:

1. Separate subject from body with a blank line.
2. Limit the subject line to 50 characters.
3. Capitalize the subject line. If you start subject with a filename, capitalize after colon: “approve.sh: Fix whitespaces”.
4. Do not end the subject line with a period.
5. Use the imperative (commanding) mood in the subject line.

>”Fix a bug causing reboots on nuc” rather than “Fixed a bug causing reboots on nuc”. 
>
>”Update weston to version 10.5.1” rather than ”New weston version 10.5.1”.

6. Wrap the body at 72 characters.
7. Use the body to explain what and why vs. how.

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

## Communication

GitHub issues are the primary way for communicating about specific proposed changes to this project.

If you want to join the project team, just let us know.