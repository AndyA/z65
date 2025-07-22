oswrch = &FFEE
want = TOP
DIM code 1000
FOR pass = 0 TO 2 STEP 2
P% = code
[OPT pass

.hexbyt PHA
        LSR A
        LSR A
        LSR A
        LSR A
        JSR hexnyb
        PLA
.hexnyb PHA
        AND #&0F
        CMP #10
        BCC hn1
        ADC #ASC"a" - ASC"9" - 2
.hn1    ADC #ASC"0"
        JSR oswrch
        PLA
        RTS

.topup  LDX #0
.tu0    LDA 0, X
        CMP #want MOD 256
        BNE tu1
        LDA 1, X
        CMP #want DIV 256
        BNE tu1
        TXA
        JSR hexbyt
        LDA #ASC" "
        JSR oswrch
.tu1    INX
        CPX #&70
        BCC tu0
        RTS

]
NEXT
CALL topup
