DIM code 1000

oswrch = &FFEE
osnewl = &FFE7
min_c = 32
max_c = 127
zig_trace = &FE90
rot = &70

FOR pass = 0 TO 3 STEP 3
P% = code
[OPT pass

.chars    STX rot
          LDX #min_c
.c1       TXA
          CLC
          ADC rot
          CMP #max_c
          BCC c2
          SBC #max_c - min_c
.c2       JSR oswrch
          INX
          CPX #max_c
          BCC c1
          LDX rot
          RTS

.lines    LDX #0
.l1       JSR chars
          JSR osnewl
          INX
          CPX #20
          BCC l1
          RTS


.trace    EQUS FNzig_trace(lines, 1)

]
NEXT
END

DEF FNzig_trace(sub, mode)
[OPT pass
          LDA zig_trace
          PHA
          LDA #mode
          STA zig_trace
          JSR sub
          PLA
          STA zig_trace
          RTS
]
=""
