REM Sorts Illustrated
REM
REM Andy Armstrong <andy@hexten.net>

oswrch = &FFEE
osnewl = &FFE7

min_c = 32 : max_c = 127 : count_c = 75

zig_trace = &FE90 : REM Magic trace flag

tmp0 = &70
acc0 = &74
stride = &78
flag = &79
enable_show = &7A

DIM chars count_c
DIM code 1000

FOR pass = 0 TO 2 STEP 2
P% = code
[OPT pass

\ Selection sort
.selection_t  JSR trace 
.selection    JSR clear
              LDX #0
.sel1         JSR show
              TXA
              TAY
              INY
.sel2         LDA chars, Y : CMP chars, X : BCS sel3          
              PHA : LDA chars, X : STA chars, Y : PLA : STA chars, X
.sel3         INY
              CPY #count_c
              BCC sel2
              INX
              CPX #count_c - 1
              BCC sel1
              JMP show

\ Bubble (exchange) sort
.bubble_t     JSR trace
.bubble       JSR clear
.bub0         JSR show
              LDX #0
              LDY #0
.bub1         LDA chars + 1, X : CMP chars, X : BCS bub2
              PHA : LDA chars, X : STA chars + 1, X : PLA : STA chars, X
              INY
.bub2         INX
              CPX #count_c - 1
              BCC bub1
              TYA
              BNE bub0
              JMP show

\ Shell sort with 2^N stride
.shell_t      JSR trace
.shell        JSR clear
              LDA #FNp2(count_c)
              STA stride
.shl1         JSR show
              LDX #0
              STX flag
              LDY stride
.shl2         LDA chars, Y : CMP chars, X : BCS shl3
              PHA : LDA chars, X : STA chars, Y : PLA : STA chars, X
              STY flag
.shl3         INX
              INY
              CPY #count_c
              BCC shl2
              LDA flag
              BNE shl1
              LSR stride
              BCC shl1
              JMP show

.gaps         EQUB 1 : EQUB 2 : EQUB 4 : EQUB 10
              EQUB 23 : EQUB 57 : EQUB 132
.gaps_end

\ Shell sort with Ciura stride
.ciura_t      JSR trace
.ciura        JSR clear
              LDY #gaps_end - gaps
.ci1          DEY
              LDA gaps, Y
              CMP #count_c
              BCS ci1
              STY stride

.ci2          JSR show
              LDX stride
              LDY gaps, X
              LDX #0
              STX flag
.ci3          LDA chars, Y : CMP chars, X : BCS ci4
              PHA : LDA chars, X : STA chars, Y : PLA : STA chars, X
              STY flag
.ci4          INX
              INY
              CPY #count_c
              BCC ci3
              LDA flag
              BNE ci2
              DEC stride
              BPL ci2
              JMP show

\ Reverse the chars
.reverse      LDX #0
              LDY #count_c - 1
.rev1         LDA chars, Y : PHA
              LDA chars, X : STA chars, Y
              PLA : STA chars, X
              DEY
              INX
              STY tmp0 + 0
              CPX tmp0 + 0
              BCC rev1
              RTS

\ Print a 32 bit decimal number 
\   acc0  the value to print
\   Y     the width to pad to
.prdec        PHA : TXA : PHA : TYA: PHA
              LDA acc0 + 0 : STA tmp0 + 0 : LDA acc0 + 1 : STA tmp0 + 1
              LDA acc0 + 2 : STA tmp0 + 2 : LDA acc0 + 3 : STA tmp0 + 3
              LDA #0
              PHA
.prd1         LDA #0
              LDX #32
.prd2         ASL tmp0 + 0 : ROL tmp0 + 1 : ROL tmp0 + 2 : ROL tmp0 + 3
              ROL A
              CMP #10
              BCC prd3
              SBC #10
              INC tmp0
.prd3         DEX
              BNE prd2
              CLC
              ADC #ASC "0"
              PHA
              DEY
              LDA tmp0 + 0 : ORA tmp0 + 1 : ORA tmp0 + 2 : ORA tmp0 + 3
              BNE prd1
              LDA #ASC" "
.prd4         PHA
              DEY
              BPL prd4        
.prd5         PLA
              BEQ prd6
              JSR oswrch
              JMP prd5
.prd6         PLA : TAY : PLA : TAX : PLA
              RTS

\ Clear acc0
.clear        LDA #0
              STA acc0 + 0
              STA acc0 + 1
              STA acc0 + 2
              STA acc0 + 3
              RTS

\ Show the char buf
.show         INC acc0 + 0 : BNE sh0
              INC acc0 + 1 : BNE sh0
              INC acc0 + 2 : BNE sh0
              INC acc0 + 3
.sh0          LDA enable_show
              BEQ sh2
              TXA : PHA : TYA : PHA
              LDY #5
              JSR prdec
              JSR psep
              JSR pspace
              LDX #0
.sh1          LDA chars, X
              JSR oswrch
              INX
              CPX #count_c
              BCC sh1
              JSR psep
              JSR osnewl
              PLA : TAY : PLA : TAX
.sh2          RTS

.psep_t       JSR trace
.psep         JSR pspace
              LDA #ASC"|"
              BNE psp1
.pspace       LDA #ASC" "
.psp1         JMP oswrch

\ Enable tracing for the following subroutine
.trace        STA tmp0 + 0
              PHP : PLA : STA tmp0 + 1
              PLA : STA tmp0 + 2            \ return address
              PLA : STA tmp0 + 3

              LDA zig_trace : PHA           \ save zig_trace
              LDA #(trace_x - 1) DIV 256 : PHA
              LDA #(trace_x - 1) MOD 256 : PHA

              LDA tmp0 + 3 : PHA
              LDA tmp0 + 2 : PHA
              LDA #1 : STA zig_trace
              LDA tmp0 + 1 : PHA
              LDA tmp0 + 0
              PLP
              RTS

.trace_x      STA tmp0 + 0
              PHP : PLA : STA tmp0 + 1
              PLA : STA zig_trace           \ restore zig_trace
              LDA tmp0 + 1 : PHA
              LDA tmp0 + 0
              PLP
              RTS

]
NEXT
PRINT "Code size: "; P% - code
seed% = TIME
?enable_show = 1
PROCrun_sort("selection", selection)
PROCrun_sort("bubble", bubble)
PROCrun_sort("shell", shell)
PROCrun_sort("ciura", ciura)
END

DEF FNp2(limit)
  LOCAL P%
  P% = 1
  REPEAT
    P% = P% * 2
  UNTIL P% >= limit
=P% DIV 2

DEF PROCfill(buf)
  LOCAL I%
  I% = RND(-seed%)
  FOR I% = 0 TO count_c - 1
    buf?I% = RND(max_c - min_c) + min_c - 1
  NEXT
ENDPROC

DEF PROCrun_sort(name$, sub)
  IF ?enable_show THEN PRINT "Running "; name$; " sort"
  PROCfill(chars)
  CALL sub
ENDPROC

DEF PROCsoak(name$, sub)
  LOCAL I%, seed%, min%, max%, min_seed%, max_seed%, ?enable_show
  ?enable_show = 0
  FOR I% = 1 TO 1000
    seed% = TIME + I%
    PROCrun_sort(name$, sub)
    IF I% = 1 THEN min% = !acc0 : max% = !acc0 : NEXT
    IF !acc0 < min% THEN min% = !acc0 : min_seed% = seed%
    IF !acc0 > max% THEN max% = !acc0 : max_seed% = seed%
  NEXT
  ?enable_show = 1
  seed% = max_seed%
  PROCrun_sort("max " + name$, sub)
  seed% = min_seed%
  PROCrun_sort("min " + name$, sub)
ENDPROC
