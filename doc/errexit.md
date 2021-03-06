---
in_progress: yes
default_highlighter: oil-sh
---

Error Handling With `set -e` / `errexit`
========================================

Unix shell programmers disagree on what the best way to handle errors is.  The
`set -e` mechanism is unreliable, and that can make your **programs**
unreliable.

A primary goal of Oil is: *Don't give anyone an excuse not to use `set -e`*.

This doc explains how we accomplish this, but most users don't need to know the
details.  All you need to do is to follow the instructions in [Oil
Options](oil-options.html).

That is, add `shopt --set oil:basic` to the top of your program, or use
`bin/oil` instead of `bin/osh`.  

The basic guarantee that Oil gives you is that **it doesn't lose errors**.
Your program won't chug along in a bad state for hours after `rm` fails.

<div id="toc">
</div>

## Overview

TODO: Transcribe [Reliable Error
Handling](//www.oilshell.org/blog/2020/10/osh-features.html#reliable-error-handling).

We have:

- Shell options: `strict_errexit`, `command_errexit`, `process_sub_fail`
- Special variables: `_process_sub_status`, analogous to `PIPESTATUS`
- The `run` builtin, which accepts `--status-ok`, `--allow-status-01`, and
  `--assign-status`.

## What Mechanisms Does Oil Provide?

TODO: organize this.

- turned on by option group `strict:all`:
  - `errexit`, `pipefail` -- POSIX sh stuff
  - `inherit_errexit` -- bash thing
  - `strict_errexit` -- Oil thing
- turned on by option group `oil:basic`
  - command_sub_errexit` -- fail more often.  It's not in "strict" because
    it doesn't disallow dangerous constructs.
  - `process_sub_fail` -- analogous to `pipefail`.  If the status was otherwise zero,
    and a process sub within the command exited nonzero, set the status of the
    command to one of those values.  Then `errexit` will make the whole command
    fail.
    - Note that process subs are "async" like pipelines, while command subs are
      synchronous.  That is why the `command_sub_errexit` and
      `process_sub_fail` options don't work the same way.

These are new in Oil:

1. `strict_errexit`: Disallow programming patterns that would lead to ignored
   errors.
2. `command_sub_errexit`: Check for failure at the end of command subs, like
   `local d=$(date %x)`.

<!-- TODO: copy section from OSH manual -->

## Background

Here's some background knowledge on Unix shell, which will motivate the
improvements in Oil.

(1) Shell has a global variable `$?` that stores the integer status of the last
command.  For example:

- the builtin `echo hi` returns `0`
- `ls /zzz` will return an error like `2`
- `nonexistent-command` returns `127`

(2) "Bare" Assignments are considered commands.

- The exit status of `a=b` is `0`.
- The exit status of `a=$(false)` is `1`, because `false` returned 1.

(3) Assignment builtins have their own exit status.

Surprisingly, the exit status of `local a=$(false)` is `0`, not `1`.  That is,
simply adding `local` changes the exit status of an assignment.

The `local` builtin has its own status which overwrites `$?`, and you lose the
status of `false`.

(4) You can explicitly check `$?` for failure, e.g. `test $? -eq 0 || die
"fail"`.

The `set -e` / `set -o errexit` mechanism tries to automate these checks, but
it does it in a surprising way.

This rule causes a lot of problems:

> The -e setting shall be ignored when executing the compound list following
> the while, until, if, or elif reserved word, a pipeline beginning with the !
> reserved word, or any command of an AND-OR list other than the last.

(5) Bash implement `errexit` differently than other shells.  `shopt -s More details:

- The implements `errexit` differently.
- The status of a pipeline is the status of its last component.  For example,
  after `ls | grep foo`, the variable `$?` is set to the exit status of `grep`.
  - If `set -o pipefail`, then the status of a pipeline is the maximum of any
    status.

## The Fundmental Problem

- success/fail of a command and logical true/false are conflated in shell.
- Oil has commands and expressions.  Commands have a status but expressions
  don't.

- TODO:
  - grep
  - test
  - command -v



## Problem

### Solution in Shell

    set +o errexit

    my-complex-func
    status=$?

    other-func
    status=$?

    set -o errexit


### Solution Oil

    shopt -u errexit {
      var status = 0 

      my-complex-func
      setvar status = $?

      other-func
      setvar status = $?
    }

## Style Guide

No:

    if myfunc ...             # internal exit codes would be thrown away

    if ls | wc -l ;           # first exit code would be thrown away


Yes:

    if external-command ...   # e.g. grep
    if builtin ...            # e.g. test
    if $0 myfunc ...          # $0 pattern


The `$0 myfunc` pattern wraps the function in an external command.

<!-- TODO: link to blog post explaining it -->

### Links


- Spec Test Suites:
  - <https://www.oilshell.org/release/latest/test/spec.wwz/survey/errexit.html>
  - <https://www.oilshell.org/release/latest/test/spec.wwz/survey/errexit-oil.html>

## OSH Has Four `errexit` Options (while Bash Has Two)

The complex behavior of these global execution options requires extra attention
in this manual.

But you don't need to understand all the details.  Simply choose between:

```
# Turn on four errexit options.  I don't run this script with other shells.
shopt -s oil:all
```

and

```
# Turn on three errexit options.  I run this script with other shells.
shopt -s strict:all
```

### Quirk 1: the Shell Sometimes Disables And Restores `errexit`

Here's some background for understanding the additional `errexit` options
described below.

In all Unix shells, the `errexit` check is disabled in these situations:
 
1. The condition of the `if`, `while`, and `until`  constructs
2. A command/pipeline prefixed by `!`
3. Every clause in `||` and `&&` except the last.

Now consider this situation:

1. `errexit` is **on**
2. The shell disables it one of those three situations
3. While disabled, the user touches it with `set -o errexit` (or `+o` to turn
   it off).

Surprising behavior: Unix shells **ignore** the `set` builtin for awhile,
delaying its execution until **after** the temporary disablement.

### Quirk 2: x=$(false) is inconsitent with local x=$(false)

Background: In shell, `local` is a builtin rather than a keyword, which means
`local foo=$(false)` behaves differently than than `foo=$(false)`.

### Additional `errexit` options

OSH aims to fix the many quirks of `errexit`.  It has this bash-compatible
option:

- `inherit_errexit`: `errexit` is inherited inside `$()`, so errors aren't
  ignored.  It's enabled by both `strict:all` and `oil:all`.

And two more options:

- `strict_errexit` makes the quirk above irrelevant.  Compound commands,
  including **functions**, can't be used in any of those three situations.  You
  can write `set -o errexit || true`, but not `{ set -o errexit; false } ||
  true`.  When this option is set, you get a runtime error indicating that you
  should **change your code**.  Consider using the ["at-splice
  pattern"][at-splice] to fix this, e.g. `$0 myfunc || echo errexit`.
- `command_sub_errexit`: Check more often for non-zero status.  In particular, the
  failure of a command sub can abort the entire script.  For example, `local
  foo=$(false)` is a fatal runtime error rather than a silent success.

### Example

When both `inherit_errexit` and `command_sub_errexit` are on, this code

    echo 0; echo $(touch one; false; touch two); echo 3

will print `0` and touch the file `one`.

1. The command sub aborts at `false` (`inherrit_errexit), and
2. The parent process aborts after the command sub fails (`command_sub_errexit`).

### Recap/Summary

- `errexit` -- abort the shell script when a command exits nonzero, except in
  the three situations described above.
- `inherit_errexit` -- A bash option that OSH borrows.
- `strict_errexit` -- Turned on with `strict:all`.
- `command_sub_errexit` -- Turned on with `oil:all`.

Good articles on `errexit`:

- <http://mywiki.wooledge.org/BashFAQ/105>
- <http://fvue.nl/wiki/Bash:_Error_handling>

## Related Documents

- [Shell Idioms](shell-idioms.html).  There's a section  on fixing
  `strict_errexit` problems.


