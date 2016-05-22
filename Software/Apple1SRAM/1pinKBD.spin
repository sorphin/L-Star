'' ┌──────────────────────────────────────────────────────────────────────────┐
'' | Cluso's 1-pin PS2 Keyboard Driver                                  v1.00 |
'' ├──────────────────────────────────────────────────────────────────────────┤
'' |  Author:            "Cluso99" (Ray Rodrick)                              |
'' |  Copyright (c) 2010 "Cluso99" (Ray Rodrick)                              |
'' |  Acknowlegements    Keyboard.spin (c) 2004,2006 by Parallax Inc          |
'' |  License            MIT License - See end of file for terms of use       |
'' └──────────────────────────────────────────────────────────────────────────┘
'' Acknowledgements: The keycode conversion is mostly copied from Parallax's
''   keyboard.spin (c)2004,2006 Parallax Inc. (v1.0.1 - Updated 6/15/2006)
'' RR20100103   First version - Proof of concept
'' RR20100129   prototype working
'' RR20100130   v020 crude working version with RC circuit
'' RR20100130   v100 try version without RC circuit using the kbd data pin
'' RR20100131   v107 adj scancode decoding (from Keyboard.spin (c) Parallax)
'' RR20100131   v115 first alpha, no buffering
'' RR20100201   v120 beta
'' RR20100220   _rr121 test with 1-pin TV
'' RR20100221   _rr122 add xlate table to convert keycodes to ascii video cmd codes
''              _rr123,124 simplify init, option to display bittime,first cr, xlate codes
''              _rr125 opt bits enable <cr> & bittime output on sync, and xlate table
'' RR20100224   _rr126 does not work @ 6.5MHz; jmp [#]send2hub_ret
'' RR20100330   _rr127 working 6.5MHz on TBP#2 (was on wrong pin)
''              _rr128 standalone demo version
'' RR20100402   _rr129 add & test peek/rxavail/rxcheck 
'' RR20100407   _rr130 fine adj mincnt/maxcnt
'' RR20100410   _rr131 rework the timing code
'' RR20100421   _rr135 timing code calculated by spin or set by calling program
'' RR20100424   v1.00  improve documentation, add rx routine for compatibility
''                     make timing routine seperate call (may then  be commented out to save space)

' ─────────────────────────────────────────────────────────────────────────────────────────────────
' * This routine connects to most PS2 Keyboards, many newer USB Keyboards (via an adapter) and
'    most older DIN5 Keyboards via a cable adapter.
' * Only 1 propeller pin is used with three resistors. +5V is required for the keyboard.
' * Ideally suited to an additional debug keyboard in your program, or as the main input keyboard.
' * The driver resides in the cog including an optional ASCII code conversion from scancodes
'    and a 16 character keyboard buffer, resulting in a minimum hub footprint.
' * A <space> character is required to initialise the timing or you can preset it
'    in your calling code (provided you use the same keyboard).
' * You will not be able to reset the keyboard and the keyboard leds will not change.
' * You may also be interested in the 1pinTV driver which uses 1 propeller pin connected to a TV
'    http://forums.parallax.com/forums/default.aspx?f=25&m=431556
' ─────────────────────────────────────────────────────────────────────────────────────────────────
' 1-pin PS2 Keyboard circuit...
' Acknowldgement to Ariba (Andy) for testing the concept for me.
'
'                          ┬ 5V  not reqd      ┬ ┬ 5V                    ┬    Keyboard
'                        ──┘      (100R)   10K   10K                   └─•  +5V
'   Prop kdPin Pxx (P26) ────────────────────┻─┼─────────────────────────•  kbdclk 
'                        ──────────────────────┻─────────────────────────•  kbddata
'                        ──┐       100R                                  ┌─•  Gnd
'                          ┴                                             ┴
'                  *see http://forums.parallax.com/forums/default.aspx?f=25&m=407823
'
' Note: * If you want to try this out, you can use the existing keyboard circuitry without change.
'       * See the Propeller Forum http://forums.parallax.com/forums/default.aspx?f=25&m=431556 for
'          more information including how to build a cable.
' ─────────────────────────────────────────────────────────────────────────────────────────────────
' To use this routine in your program, simply add the following...
' OBJ
'   kb    :      "Debug_1pinKBD"
' PUB main | t
' 'start the 1pinKBD driver
'   'first calculate the timing
'   '  note you can skip this if you always use the same kbd & xtal by and hardcode the times in kb.start below
'   fdx.str(string(13,"Hit <spacebar> to synchronise keyboard "))
'   t := kb.calckbdtime(kdpin)                            'calculate the keyboard timing
'   fdx.str(string("Timing = "))                          '\ optionally show the timing calculated              
'   fdx.dec(t & $FFFF)                                    '|                                                          
'   fdx.tx(",")                                           '| 
'   fdx.dec(t >> 16)                                      '/ 
'   fdx.tx(13)                                            '<cr>
'   'start the 1pinKBD driver (using the timing returned) [mine is kb.start(kdpin,6736,7255)]
'   t := kb.start(kdpin, t & $FFFF, t >> 16)              'start the 1pinKbd driver (e.g. fixed bittimes)
' ─────────────────────────────────────────────────────────────────────────────────────────────────

CON
  opt = %0001                   ' [0] : 1 = translate keycodes to ascii control codes (screen control)
                                 
VAR
  long  cog
  long  pRENDEZVOUS                                     'buffer to pass character
  
PUB start( KdPin, startbit, databit )                   'pass kbd data pin# & start and data bit times
  stop

'set bittiming (It is presumed to be correct. You can calculate by calling kb.calkbdtime(KdPin) first)
  bittime := databit                                    'set bit time
  halfbit := startbit - (databit / 2)                   'set the start bit sample time
  idletime := bittime * 11                              'idle time = 1 char time = 11 * bits

  pRendezvous := KdPin & $FF                            'pass pin#
  result := cog := COGNEW( @entry,@pRendezvous) + 1
  repeat until pRENDEZVOUS == 0                         'wait until cleared

  
PUB stop
  COGSTOP( cog~ - 1 )
    
PUB rx : c                                              'compatability
   c := in

PUB in : c
'' Wait for an input character

  repeat until c := pRendezvous                         'wait until the mailbox has a character
  pRendezvous~                                          'clear the mailbox
  c &= $FF                      '$100 -> $00            'extract lower 8 bits (byte)

PUB peek
'' Returns a 0 if the buffer is empty,
'' else next character (+$100) but doesn't remove from the buffer.
'' The user routine must extract the 8 bits as the whole long is passed.

  return pRendezvous                                    'return ALL bits (long) in the mailbox

PUB rxavail 
'' Check if byte(s) available
'' returns true (-1) if bytes available

  return (pRendezvous <> 0)

PUB rxcheck : rxbyte
'' Check if byte received (never waits)
'' returns -1 if no byte received, $00..$FF if byte

  rxbyte := pRendezvous
  if rxbyte <> 0
    rxbyte &= $FF                                       'extract lower 8 bits
    pRendezvous~                                        'clear mailbox
  else
    rxbyte := -1                                        'no char avail so -1

PUB calckbdtime(kdpin) : times | s, b0, b1, b3, b4, b5, b6
'' Calculate keyboard timing and return them
'' Note: This routine can be commented out once calculated if you wish to use fixed timing
''         with the same keyboard and xtal.

' start counters
  frqa := 1
  ctra := %10101 << 26 + kdpin                          'time kbd bit = 0
  frqb := 1
  ctrb := %11010 << 26 + kdpin                          'time kbd bit = 1

'wait for a <space> key (scancode $29)                  'bits numbered s1234678ps
  repeat
    'wait for idle (11 bits =1)
    phsa := 0                                           'reset bit=0 counter
    phsb := 0                                           'reset bit=1 counter
    repeat
      if phsa > 0                                       'if bit=0 detected, reset counters
        phsa := 0                                     
        phsb := 0                                    
    until phsb > clkfreq / 909                          'wait until bit=1 counter > 1100uS (11 bits @ 100us)
    'wait for start bit (=0)
    phsa := 0                                           'reset counter (time bit=0)
    waitpne( |< kdpin, |< kdpin, 0)                     'wait for kdpin =0 (start)
    phsb := 0                                           'reset counter (time bit=1)
    'wait for bit0 (=1)
    waitpeq( |< kdpin, |< kdpin, 0)                     'wait for kdpin =1
    s := phsa                                           'store the kdpin=0 time (start bit time)
    phsa := 0                                           'reset
    if s =< clkfreq / 25000 or s => clkfreq /10000      'startbit 40us < a < 100us ?  (spec says 60<a<100us)
      next                                              'n: restart repeat loop
    'wait for bit1 (=0)
    waitpne( |< kdpin, |< kdpin, 0)                     'wait for kdpin =0
    b0 := phsb                                          'store the kdpin=1 time (bit0 time)
    phsb := 0                                           'reset
    if b0 =< clkfreq / 20000 or b0 => clkfreq /10000    'startbit 50us < a < 100us ?  (spec says 60<a<100us)
      next                                              'n: restart repeat loop
    'wait for bit4 (=1)
    waitpeq( |< kdpin, |< kdpin, 0)                     'wait for kdpin =1
    b1 := phsa / 2                                      'store the kdpin=0 time (bit 1&2 time /2)
    phsa := 0                                           'reset
    if b1 =< clkfreq / 20000 or b1 => clkfreq /10000    'startbit 50us < a < 100us ?  (spec says 60<a<100us)
      next                                              'n: restart repeat loop
    'wait for bit5 (=0)
    waitpne( |< kdpin, |< kdpin, 0)                     'wait for kdpin =0
    b3 := phsb                                          'store the kdpin=1 time (bit3 time)
    phsb := 0                                           'reset
    if b3 =< clkfreq / 20000 or b3 => clkfreq /10000    'startbit 50us < a < 100us ?  (spec says 60<a<100us)
      next                                              'n: restart repeat loop
    'wait for bit6 (=1)
    waitpeq( |< kdpin, |< kdpin, 0)                     'wait for kdpin =1
    b4 := phsa                                          'store the kdpin=0 time (bit4 time)
    phsa := 0                                           'reset
    if b4 =< clkfreq / 20000 or b4 => clkfreq /10000    'startbit 50us < a < 100us ?  (spec says 60<a<100us)
      next                                              'n: restart repeat loop
    'wait for bit7 (=0)
    waitpne( |< kdpin, |< kdpin, 0)                     'wait for kdpin =0
    b5 := phsb                                          'store the kdpin=1 time (bit5 time)
    phsb := 0                                           'reset
    if b5 =< clkfreq / 20000 or b5 => clkfreq /10000    'startbit 50us < a < 100us ?  (spec says 60<a<100us)
      next                                              'n: restart repeat loop
    'wait for stopbit (=1)
    waitpeq( |< kdpin, |< kdpin, 0)                     'wait for kdpin =1
    b6 := phsa / 3                                      'store the kdpin=0 time (bit6,7,p time)
    phsa := 0                                           'reset
    if b6 =< clkfreq / 20000 or b6 => clkfreq /10000    'startbit 50us < a < 100us ?  (spec says 60<a<100us)
      next                                              'n: restart repeat loop
    quit                                                'found <space> so exit
    
'stop counters
  ctra := 0
  ctrb := 0
  waitcnt (clkfreq/10 + cnt)                            'skip other kbd chars                                          

  b0 := (b0 + b1) / 2                                   'average 0 & 1 bit time
  times := b0 << 16 | s                                 'pack the times to return them to calling object


DAT

'************************************************
'* Assembly language 1-pin PS/2 keyboard driver *
'************************************************

                        org     0
'NOTE: halfbit, bittime, idlebit are all preset in hub before this program is started

entry
kbuff         'NOTE: After initialisation, the following 16 instructions will be used as the cog keyboard buffer
                        rdlong  x,par                   'get params (kbd data pin)
                        shl     dmask,x                 'convert to pin mask (dmask was 1)
                        movs    ctra,x                  'put pin no into ctra
                        movs    ctrb,x                  '                ctrb
                        mov     frqa,#1                 'set counters ready to accum.
                        mov     frqb,#1                 '
                        movd    ctra,#%0_10101_000      'Logic A=0 (accumulate when Apin=0) pin# already in ctra
                        wrlong  data,par                'clear buff (data=0 at startup)
                        jmp     #newcode
filler                  long    0[kbuff + 16 - $]       'pad for kbuff[16]

'Get scancode
newcode                 mov     stat,#0                 'reset state
:same                   call    #receive                'receive byte from keyboard
                        cmp     data,#$F0       wz      'released?
        if_z            or      stat,#2
        if_z            jmp     #:same
                        cmp     data,#$E0       wz      'extended?
        if_z            or      stat,#1
        if_z            jmp     #:same
                        cmp     data,#$83+1     wc      'scancode?
        if_nc           jmp     #newcode                'if unknown, ignore

'Translate scancode and enter into buffer
                        test    stat,#1         wc      'lookup code with extended flag
                        rcl     data,#1
                        call    #look

                        cmp     data,#0         wz      'if unknown, ignore
        if_z            jmp     #newcode

                        mov     t,_states+6             'remember lock keys in _states

                        mov     x,data                  'set/clear key bit in _states
                        shr     x,#5
                        add     x,#_states
                        movd    :reg,x
                        mov     y,#1
                        shl     y,data
                        test    stat,#2         wc
:reg                    muxnc   0,y

        if_nc           cmpsub  data,#$F0       wc      'if released or shift/ctrl/alt/win, done
        if_c            jmp     #newcode

                        mov     y,_states+7             'get shift/ctrl/alt/win bit pairs
                        shr     y,#16

                        cmpsub  data,#$E0       wc      'translate keypad, considering numlock
        if_c            test    _locks,#%100    wz
        if_c_and_z      add     data,#@keypad1-@table
        if_c_and_nz     add     data,#@keypad2-@table
        if_c            call    #look
        if_c            jmp     #:flags

                        cmpsub  data,#$DD       wc      'handle scrlock/capslock/numlock
        if_c            mov     x,#%001_000
        if_c            shl     x,data
        if_c            andn    x,_locks
        if_c            shr     x,#3
        if_c            shr     t,#29                   'ignore auto-repeat
        if_c            andn    x,t             wz
        if_c            xor     _locks,x
        if_c            add     data,#$DD
        if_c_and_nz     or      stat,#4                 'if change, set configure flag to update leds

                        test    y,#%11          wz      'get shift into nz

        if_nz           cmp     data,#$60+1     wc      'check shift1
        if_nz_and_c     cmpsub  data,#$5B       wc
        if_nz_and_c     add     data,#@shift1-@table
        if_nz_and_c     call    #look
        if_nz_and_c     andn    y,#%11

        if_nz           cmp     data,#$3D+1     wc      'check shift2
        if_nz_and_c     cmpsub  data,#$27       wc
        if_nz_and_c     add     data,#@shift2-@table
        if_nz_and_c     call    #look
        if_nz_and_c     andn    y,#%11

                        test    _locks,#%010    wc      'check shift-alpha, considering capslock
                        muxnc   :shift,#$20
                        test    _locks,#$40     wc
        if_nz_and_nc    xor     :shift,#$20
                        cmp     data,#"z"+1     wc
        if_c            cmpsub  data,#"a"       wc
:shift  if_c            add     data,#"A"
        if_c            andn    y,#%11

:flags                  ror     data,#8                 'add shift/ctrl/alt/win flags
                        mov     x,#4                    '+$100 if shift
:loop                   test    y,#%11          wz      '+$200 if ctrl
                        shr     y,#2                    '+$400 if alt
        if_nz           or      data,#1                 '+$800 if win
                        ror     data,#1
                        djnz    x,#:loop
                        rol     data,#12
                        call    #store                  'save in the buffer
                        jmp     #newcode                'next

'wait for idle condition (>11 bit times @ =1)
resync                  movd    ctrb,#%0_11010_000      'Logic A=1 (accumulate when Apin=1) pin# already in ctrb
:resync                 mov     phsa,#0                 'reset bit=0 counter
                        mov     phsb,#0                 'reset bit=1 counter
:resync1                call    #send2hub               'if poss, send chars in kbuff to hub 
                        mov     count,phsa  wz,nr       'detect bit=0 ?
        if_nz           jmp     #:resync                'y: start again
                        cmp     idletime,phsb  wc       'time up?
        if_nc           jmp     #:resync1               'no
                        movd    ctrb,#0                 'stop ctrb

'Receive a keyboard character (1-pin version)
receive                 mov     phsa,#0                 'ensure phsa=0
:wait0                  call    #send2hub               'if poss, send chars in kbuff to hub
                        mov     x,ina                   'read input
                        and     x,dmask    wc           'extract data pin
        if_c            jmp     #:wait0                 'wait if =1
                        mov     count,cnt               'copy the system cnt value
                        sub     count,phsa              'sub the lost counts (accounts for latency)
                        mov     bits,#11                'assemble 11 bits
                        mov     data,#0                 'clear char
                        add     count,halfbit           'add 1/2 bit time to start sampling the start bit
'beginning of start bit: now assemble start+8+parity+stop bits
:loop                   waitcnt count,bittime           'wait for middle of bit sample time
                        mov     x,ina                   'read input
                        and     x,dmask    wc           'extract data pin
                        rcr     data,#1                 'collect bit
                        cmp     bits,#11   wz           'middle of start bit? (ensure it is =0)
        if_c_and_z      jmp     #resync                 'yes but pin=1
                        djnz    bits,#:loop             'middle of stop bit?
'we have 10 bits in data (11 including the start)
                        shr     data,#22                'shift bits to correct position
                        mov     x,data                  'copy the char
                        and     data,#$FF  wc           'remove parity and stop bits
                        shr     x,#8                    'move stop and parity to b1..b0
        if_nc           xor     x,#1                    'make parity bit=0
                        xor     x,#2       wz           'make stop bit=0
        if_nz           jmp     #resync                 'invalid parity or stop so skip and resync
receive_ret             ret

'Store char in kbuff ready for sending to hub (will overwrite buffer if full)
store                   test    _opt,#1<<0      wz      'translate?                        
        if_nz           call    #xlate                  'y: translate the keycode to video cmd if reqd
                        cmp     data, #$80      wc      'ignore keycodes > $7F
        if_nc           jmp     #newcode
store5                  movd    :store,_head            'set kbuff cog head address
                        add     _head,#1                'inc
                        and     _head,#$0F              'wrap
:store                  mov     0-0,data                'store in kbuff[_head]
store5_ret
store_ret               ret

'check if we can send a kbuff char to hub
send2hub                cmp     _head,_tail     wz      'cog kbuff empty?
        if_z            jmp     send2hub_ret            'y
                        rdlong  x,par           wz      'hub kbuff empty?
        if_nz           jmp     send2hub_ret            'n
                        movs    :store,_tail            'set kbuff cog tail address
                        add     _tail,#1                'inc
                        and     _tail,#$0F              'wrap
:store                  mov     x,0-0                   'get from kbuff[_tail]
                        wrlong  x,par                   'store in hub buffer
send2hub_ret            ret


'Lookup byte in table
look                    ror     data,#2                 'perform lookup
                        movs    :reg,data
                        add     :reg,#table
                        shr     data,#27                'data now has byte offset *8
                        mov     x,data
:reg                    mov     data,0-0
                        shr     data,x
                        and     data,#$FF               'isolate byte
look_ret                ret

                      
'Translate table (special keycodes --> ascii screen codes) keycode    screencode     'ascii    video         key                         
xlate                                                   '  -------    ----------      -----    -----         ----------                  
                        cmp     data, #$09      wz      '  $09:       tv.out(  )     'ht                     (tab)           1=ignore    
              if_z      mov     data, #$FF              'ignore tab               
'                       cmp     data, #$13      wz      '  $13:       tv.out(13)     'cr       cr            (enter)                     
                        cmp     data, #$C0      wz      '  $C0:       tv.out(29)     'gs       left          (left)                      
              if_z      mov     data, #29               
                        cmp     data, #$C1      wz      '  $C1:       tv.out(28)     'fs       right         (right)                     
              if_z      mov     data, #28               
                        cmp     data, #$C2      wz      '  $C2:       tv.out(30)     'rs       up            (up)                        
              if_z      mov     data, #30               
                        cmp     data, #$C3      wz      '  $C3:       tv.out(31)     'us       down          (down)                      
              if_z      mov     data, #31               
                        cmp     data, #$C4      wz      '  $C4:       tv.out(11)     'vt       home          (home)                      
              if_z      mov     data, #11               
'                       cmp     data, #$C5      wz      '  $C5:       tv.out(  )     '                       (end)                       
'                       cmp     data, #$C6      wz      '  $C6:       tv.out(  )     '                       (pgup)                      
'                       cmp     data, #$C7      wz      '  $C7:       tv.out(  )     '                       (pgdn)                      
                        cmp     data, #$C8      wz      '  $C8:       tv.out( 8)     'bs       backspace     (backspace)                 
              if_z      mov     data, #08               
'                       cmp     data, #$C9      wz      '  $C9:       tv.out(  )     '                       (delete)                    
'                       cmp     data, #$CA      wz      '  $CA:       tv.out(  )     '                       (insert)                    
'                       cmp     data, #$CB      wz      '  $CB:       tv.out(27)     'esc                    (escape)                    
'                       cmp     data, #$D0..$DB wz      '  $D0..$DB:  tv.out(  )     '                       (F1..F12)                   
'                       cmp     data, #$DC      wz      '  $DC:       tv.out(  )     '                       (printscreen)               
                        cmp     data, #$DD      wz      '  $DD:       tv.out(24)     'can      clearscreen   (scroll lock)               
              if_z      mov     data, #24               
'                       cmp     data, #$DE      wz      '  $DE:       tv.out(  )     '                       (caps lock)                 
'                       cmp     data, #$DF      wz      '  $DF:       tv.out(  )     '                       (break)                     
xlate_ret               ret

_opt                    long    opt                     'options = [0] : 1 = translate keycodes to ascii control codes                 
data                    long    0                       'data char (used as "0" on initialisation)
dmask                   long    1                       'pin data mask (preset to "1", shifted later)
bittime                 long    0                       '1   bit time
halfbit                 long    0                       '1/2 bit time
idletime                long    0                       'stores 11 bit times (1 char)
bits                    long    0                       'bit counter
count                   long    0

_head                   long    0                       'points to last char inserted into kbuff (at cog $000)
_tail                   long    0                       'points to next char available in  kbuff
_states                 long    0,0,0,0,0,0,0,0         '*8 = 256 key states
_locks                  long    %0_000_100              'locks = bit 6 disallows shift-alphas (case set soley by CapsLock)
                                                        '        bits 5..3 disallow toggle of NumLock/CapsLock/ScrollLock state
                                                        '        bits 2..0 specify initial state of NumLock/CapsLock/ScrollLock


' Lookup table                  ascii   scan    extkey  regkey  ()=keypad
table                   word    $0000   '00
                        word    $00D8   '01             F9
                        word    $0000   '02
                        word    $00D4   '03             F5
                        word    $00D2   '04             F3
                        word    $00D0   '05             F1
                        word    $00D1   '06             F2
                        word    $00DB   '07             F12
                        word    $0000   '08
                        word    $00D9   '09             F10
                        word    $00D7   '0A             F8
                        word    $00D5   '0B             F6
                        word    $00D3   '0C             F4
                        word    $0009   '0D             Tab
                        word    $0060   '0E             `
                        word    $0000   '0F
                        word    $0000   '10
                        word    $F5F4   '11     Alt-R   Alt-L
                        word    $00F0   '12             Shift-L
                        word    $0000   '13
                        word    $F3F2   '14     Ctrl-R  Ctrl-L
                        word    $0071   '15             q
                        word    $0031   '16             1
                        word    $0000   '17
                        word    $0000   '18
                        word    $0000   '19
                        word    $007A   '1A             z
                        word    $0073   '1B             s
                        word    $0061   '1C             a
                        word    $0077   '1D             w
                        word    $0032   '1E             2
                        word    $F600   '1F     Win-L
                        word    $0000   '20
                        word    $0063   '21             c
                        word    $0078   '22             x
                        word    $0064   '23             d
                        word    $0065   '24             e
                        word    $0034   '25             4
                        word    $0033   '26             3
                        word    $F700   '27     Win-R
                        word    $0000   '28
                        word    $0020   '29             Space
                        word    $0076   '2A             v
                        word    $0066   '2B             f
                        word    $0074   '2C             t
                        word    $0072   '2D             r
                        word    $0035   '2E             5
                        word    $CC00   '2F     Apps
                        word    $0000   '30
                        word    $006E   '31             n
                        word    $0062   '32             b
                        word    $0068   '33             h
                        word    $0067   '34             g
                        word    $0079   '35             y
                        word    $0036   '36             6
                        word    $CD00   '37     Power
                        word    $0000   '38
                        word    $0000   '39
                        word    $006D   '3A             m
                        word    $006A   '3B             j
                        word    $0075   '3C             u
                        word    $0037   '3D             7
                        word    $0038   '3E             8
                        word    $CE00   '3F     Sleep
                        word    $0000   '40
                        word    $002C   '41             ,
                        word    $006B   '42             k
                        word    $0069   '43             i
                        word    $006F   '44             o
                        word    $0030   '45             0
                        word    $0039   '46             9
                        word    $0000   '47
                        word    $0000   '48
                        word    $002E   '49             .
                        word    $EF2F   '4A     (/)     /
                        word    $006C   '4B             l
                        word    $003B   '4C             ;
                        word    $0070   '4D             p
                        word    $002D   '4E             -
                        word    $0000   '4F
                        word    $0000   '50
                        word    $0000   '51
                        word    $0027   '52             '
                        word    $0000   '53
                        word    $005B   '54             [
                        word    $003D   '55             =
                        word    $0000   '56
                        word    $0000   '57
                        word    $00DE   '58             CapsLock
                        word    $00F1   '59             Shift-R
                        word    $EB0D   '5A     (Enter) Enter
                        word    $005D   '5B             ]
                        word    $0000   '5C
                        word    $005C   '5D             \
                        word    $CF00   '5E     WakeUp
                        word    $0000   '5F
                        word    $0000   '60
                        word    $0000   '61
                        word    $0000   '62
                        word    $0000   '63
                        word    $0000   '64
                        word    $0000   '65
                        word    $00C8   '66             BackSpace
                        word    $0000   '67
                        word    $0000   '68
                        word    $C5E1   '69     End     (1)
                        word    $0000   '6A
                        word    $C0E4   '6B     Left    (4)
                        word    $C4E7   '6C     Home    (7)
                        word    $0000   '6D
                        word    $0000   '6E
                        word    $0000   '6F
                        word    $CAE0   '70     Insert  (0)
                        word    $C9EA   '71     Delete  (.)
                        word    $C3E2   '72     Down    (2)
                        word    $00E5   '73             (5)
                        word    $C1E6   '74     Right   (6)
                        word    $C2E8   '75     Up      (8)
                        word    $00CB   '76             Esc
                        word    $00DF   '77             NumLock
                        word    $00DA   '78             F11
                        word    $00EC   '79             (+)
                        word    $C7E3   '7A     PageDn  (3)
                        word    $00ED   '7B             (-)
                        word    $DCEE   '7C     PrScr   (*)
                        word    $C6E9   '7D     PageUp  (9)
                        word    $00DD   '7E             ScrLock
                        word    $0000   '7F
                        word    $0000   '80
                        word    $0000   '81
                        word    $0000   '82
                        word    $00D6   '83             F7

keypad1                 byte    $CA, $C5, $C3, $C7, $C0, 0, $C1, $C4, $C2, $C6, $C9, $0D, "+-*/"

keypad2                 byte    "0123456789.", $0D, "+-*/"

shift1                  byte    "{|}", 0, 0, "~"

shift2                  byte    $22, 0, 0, 0, 0, "<_>?)!@#$%^&*(", 0, ":", 0, "+"


'Uninitialized data
stat                    res     1
x                       res     1
y                       res     1
t                       res     1

                        fit     $1F0

''
''
''      _________
''      Key Codes
''
''      00..DF  = keypress and keystate
''      E0..FF  = keystate only
''
''
''      09      Tab
''      0D      Enter
''      20      Space
''      21      !
''      22      "
''      23      #
''      24      $
''      25      %
''      26      &
''      27      '
''      28      (
''      29      )
''      2A      *
''      2B      +
''      2C      ,
''      2D      -
''      2E      .
''      2F      /
''      30      0..9
''      3A      :
''      3B      ;
''      3C      <
''      3D      =
''      3E      >
''      3F      ?
''      40      @
''      41..5A  A..Z
''      5B      [
''      5C      \
''      5D      ]
''      5E      ^
''      5F      _
''      60      `
''      61..7A  a..z
''      7B      {
''      7C      |
''      7D      }
''      7E      ~
''
''      80-BF   (future international character support)
''
''      C0      Left Arrow
''      C1      Right Arrow
''      C2      Up Arrow
''      C3      Down Arrow
''      C4      Home
''      C5      End
''      C6      Page Up
''      C7      Page Down
''      C8      Backspace
''      C9      Delete
''      CA      Insert
''      CB      Esc
''      CC      Apps
''      CD      Power
''      CE      Sleep
''      CF      Wakeup
''
''      D0..DB  F1..F12
''      DC      Print Screen
''      DD      Scroll Lock
''      DE      Caps Lock
''      DF      Num Lock
''
''      E0..E9  Keypad 0..9
''      EA      Keypad .
''      EB      Keypad Enter
''      EC      Keypad +
''      ED      Keypad -
''      EE      Keypad *
''      EF      Keypad /
''
''      F0      Left Shift
''      F1      Right Shift
''      F2      Left Ctrl
''      F3      Right Ctrl
''      F4      Left Alt
''      F5      Right Alt
''      F6      Left Win
''      F7      Right Win
''
''      FD      Scroll Lock State
''      FE      Caps Lock State
''      FF      Num Lock State
''
''      +100    if Shift
''      +200    if Ctrl
''      +400    if Alt
''      +800    if Win
''
''      eg. Ctrl-Alt-Delete = $6C9
''
''
'' Note: Driver will buffer up to 15 keystrokes, then ignore overflow.


{{
+------------------------------------------------------------------------------------------------------------------------------+
|                                                   TERMS OF USE: MIT License                                                  |                                                            
+------------------------------------------------------------------------------------------------------------------------------+
|Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    | 
|files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    |
|modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software|
|is furnished to do so, subject to the following conditions:                                                                   |
|                                                                                                                              |
|The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.|
|                                                                                                                              |
|THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          |
|WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         |
|COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   |
|ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         |
+------------------------------------------------------------------------------------------------------------------------------+
}}                                                            