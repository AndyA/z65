# hibasic: Acorn BBC HiBASIC

```
Usage:
    hibasic [OPTIONS] <prog>

Options:
    -h, --help
            Display this help and exit.

        --full-help
            Print more help.

    -c, --chain
            Do CHAIN "prog" instead of LOAD "prog".

    -s, --sync
            Auto load when prog changes on disc. Auto save when prog
            changes in memory.

    -q, --quit
            Quit after running (*BYE).

    -e, --exec <line>...
            Lines of BBC Basic to run. May be used more than once to supply
            multiple lines.

    <prog>
            Program to load or run (--chain). May be text source or BBC
            Basic native.
```

## Notes

Both native BBC Basic format source files and textual source files are supported by LOAD, SAVE and CHAIN. To work with textual source files use the extension .bbc when editing them. Any other extension - or no extension means BBC Basic native format.

There's currently no support for stopping a running program by hitting Escape and Ctrl-C will kill hibasic completely. Fixes for both are planned.

There's currently no VDU emulation - characters are sent as-is to stdout. On one hand that means you can change the terminal colour and print UTF-8 characters. On the other hand COLOUR etc don't work. I plan to add support for mapping BBC colours to terminal colours.

https://github.com/qiongzhu/multiarch-on-aarch64

## TODO

- OSFILE
  - ~~don't alloc~~ ✘
  - implement more functions
- keyboard input handling
  - tty to cooked mode
  - runs on its own thread?
  - readline?
- VDU emulations
  - png canvas
  - sdl
  - svg
  - terminal colours
- handle plain text basic
  - ~~read and write~~ ✔
- CLI options
  - ~~load~~ ✔
  - ~~chain~~ ✔
  - watch
  - ~~run commands and exit~~ ✔
- trace to file
  - currently goes to stderr; maybe that's fine?
- ~~integrate M-UTS~~ ✘
- OSCLI fixes
  - pick command based on first word
  - make optionality more formally correct?
