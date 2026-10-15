# fbsd-config

A small roff project: an `mdoc(7)` manual page that maps out FreeBSD's
configuration files (`rc.conf`, `loader.conf`, `sysctl.conf`, and friends).

## Files

- `fbsd-config.7` - the man page source (mdoc macros)
- `Makefile` - lint, render, and install targets

## Usage

    make lint       # check the page for mistakes
    make            # build fbsd-config.txt and fbsd-config.html
    make view       # read it in your pager
    make install    # install to /usr/local/share/man/man7 (may need root)
    make clean      # remove generated files

View without building:

    mandoc fbsd-config.7 | less
    man ./fbsd-config.7

## Requirements

`mandoc` and `col`, both in the FreeBSD base system. On other systems,
install `mandoc`, or use `groff -mdoc -T utf8 fbsd-config.7`.

## Extending

Add more pages (for example `myapp.conf.5`) by copying `fbsd-config.7`
and adding a matching entry to the `Makefile`.
