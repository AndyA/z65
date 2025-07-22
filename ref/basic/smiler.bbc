REM Turns out BBC Basic is UTF-8 safe

oswrch = &FFEE
osnewl = &FFE7

DIM code 1000

FOR pass = 0 TO 3 STEP 3
P% = code
[OPT pass

.smile  EQUS "😊"
        EQUB 0

.smiler LDX #0
.sm1    LDA smile, X
        BEQ sm2
        JSR oswrch
        INX
        BNE sm1
.sm2    RTS

]
NEXT
CALL smiler
