https://github.com/qiongzhu/multiarch-on-aarch64

## TODO

- OSFILE
  - ~~don't alloc~~ ✘
  - implement more functions
- keyboard input handling
  - tty to cooked mode
  - runs on its own thread
  - readline?
- VDU emulations
  - png canvas
  - sdl
  - svg
- handle plain text basic
  - ~~read and write~~ ✔
  - watch
- CLI options
  - load
  - chain
  - watch
  - run commands and exit
- trace to file
- integrate M-UTS
- OSCLI fixes
  - pick command based on first word
  - make optionality more formally correct?

## CLI

```
z64 [OPTIONS] <prog>

  -c, --chain <PROG>  CHAIN "prog"
      --watch <PROG>  CHAIN "prog" when it changes
  -q, --quit          Quit after running
  -e          <CMD>   Execute BBC Basic. May be used more than once
      --help
```
