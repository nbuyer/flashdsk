;
; Comment:
;   This source is an ASM device driver for DOS that
;   makes a piece of SAMSUNG flash memory (sorry, I forgot the model name,
;   long time ago) a normal DOS "fixed" drive. It was original written
;   to support our PDA product (one of our abortion :<, never mind).
;
;
;   * I AM NOT RESPONSIBLE FOR ANY DAMAGE CAUSED BY THIS SOURCE
;   * Do NOT WRITE ME ANY EMAIL except that you want to thank me for this
;     source, DO NOT ASK ME ANY QUESTION about this source file.
;   * You may copy/use/distribute anything of this source freely. 
;     But please do not change anything of THIS FILE if you want
;     to distribute it.
;   * Thank for those people who published their source to others.
;
; Author: Edward G.
; mailto:nbuyer@gmail.com
;

;****************************************************************************;
; Project: G&S VG330 PDA                                                     ;
; File: flashdsk.asm                                                         ;
; Description: Flash memory DOS disk driver(PDA version)                     ;
; Copyright: Copr. 1998 Shenzhen G&S Co. Ltd., ALL RIGHT RESERVED !          ;
; Author: Edward G.                                                         ;
; Comment: standard 80186 asm                                                ;
;****************************************************************************;
; History:                                                                   ;
; Ver   When          Who     Changes                                        ;
; 1.0  May 30th 1998  Edward  Original version(beta)                         ;
;                                                                            ;
;****************************************************************************;

;############################################################################
; To be done:
; * Device command line
;############################################################################


; Information (for more info, pls ref to DOS book/interrupt list)
;============================================================================
;  Format of device driver request header:
;  Offset  Size    Description            
;   00h    BYTE    length of request header
;   01h    BYTE    subunit within device driver
;   02h    BYTE    command code (see below)
;   03h    WORD    status (filled in by device driver)
;          bit 15: error
;          bits 14-10: reserved
;          bit 9: busy
;          bit 8: done
;          bits 7-0: error code if bit 15 set (see below)
;   05h  8 BYTEs   reserved (unused in DOS 2.x and 3.x)
;  ---command code 00h---
;   0Dh    BYTE    number of units (set by driver)
;   0Eh    DWORD   address of first free byte following driver (set by
;                     driver)
;   12h    DWORD   pointer to BPB array (set by block drivers only)
;   16h    BYTE    (DOS 3+) drive number for first unit of block driver (0=A)
;  ---command code 01h---
;   0Dh    BYTE    media descriptor
;   0Eh    BYTE    returned status
;          00h don't know
;          01h media has not changed
;          FFh media has been changed
;   0Fh    DWORD   (DOS 3+) pointer to previous volume ID if OPEN/CLOSE/RM
;            bit in device header set and disk changed (set by driver)
;  ---command code 02h---
;   0Dh    BYTE    media descriptor
;   0Eh    DWORD   transfer address
;          -> scratch sector if NON-IBM FORMAT bit in device header set
;          -> first FAT sector otherwise
;   12h    DWORD   pointer to BPB (set by driver)
;  ---command codes 03h,0Ch---
;   0Dh    BYTE    media descriptor (block devices only)
;   0Eh    DWORD   transfer address
;   12h    WORD    byte count (character devices) or sector count (block
;                      devices)
;   14h    WORD    starting sector number (block devices only)
;  ---command codes 04h,08h,09h---
;   0Dh    BYTE    media descriptor (block devices only)
;   0Eh    DWORD   transfer address
;   12h    WORD    byte count (character devices) or sector count (block
;                      devices)
;   14h    WORD    starting sector number (block devices only)
;   16h    DWORD   (DOS 3+) pointer to volume ID if error 0Fh returned
;
;  Values for command code:
;    * 00h INIT
;    * 01h MEDIA CHECK (block devices)
;    * 02h BUILD BPB (block devices)
;    * 04h INPUT
;    * 08h OUTPUT
;    * 09h OUTPUT WITH VERIFY
;      0Dh (DOS 3+) DEVICE OPEN
;      0Eh (DOS 3+) DEVICE CLOSE
;      0Fh (DOS 3+) REMOVABLE MEDIA (block devices)
;    (* minimum requirement)
;
;  Values for error code:
;      00h write-protect violation
;      01h unknown unit
;      02h drive not ready
;      03h unknown command
;      04h CRC error
;      05h bad drive request structure length
;      06h seek error
;      07h unknown media
;      08h sector not found
;      09h printer out of paper
;      0Ah write fault
;      0Bh read fault
;      0Ch general failure
;      0Dh reserved
;      0Eh reserved
;      0Fh invalid disk change


; Definition
;============================================================================
_BUGGY    = 1                           ; Use buggy chip
;_DEBUG    = 1                           ; Debug version
;_COMFILE  = 1                           ; .com file
;_DEVTEST  = 1                           ; Test version(.com) of device
;_NEEDBUF  = 1                           ; Allocated buffer
;_DEBUGGER = 1                           ; Use int 3
;_SHOWRQ   = 1                           ; Show request


ifdef           _DEBUG
ifndef          _COMFILE
ifndef          _NEEDBUF
_NEEDBUF  = 1
endif           ;!_NEEDBUF
endif           ;!_COMFILE
endif           ;_DEBUG


; Constant
;============================================================================

;----- Version related
VOL_NAME        equ     'GSFLASHDSK1'   ; 11 bytes volumn label
VER_NUM         equ     '1.0'           ; Version number
RELEASE_NUM     equ     '0', '1'        ; Release number
DEF_SEC_SIZE    equ     512             ; Driver sector size
DRV_MEDIA       equ     0fah            ; media descriptor byte
DEF_ROOT_DIR    equ     64              ; root dir directory count
MIN_DOS         equ     2               ; minumum DOS version
MAX_RETRY       equ     3               ; max fault retry
DEV_READONLY    equ     'R'             ; Readonly flag
DEV_WRITE       equ     'W'             ; Writable

;----- Char in DEB_PUTC
CHR_RQ          equ     '#'             ; A request
CHR_BUILDBPB1   equ     'b'             ; Build BPB start
CHR_BUILDBPB2   equ     'B'             ; Build BPB end
CHR_INPUT1      equ     'r'             ; Input/read begin
CHR_INPUT2      equ     'R'             ; Input/read end
CHR_OUTPUT1     equ     'w'             ; Output/write begin
CHR_OUTPUT2     equ     'W'             ; Output/write end
CHR_OUTPUT3     equ     'v'             ; Output verify begin
CHR_OUTPUT4     equ     'V'             ; Output verify end
CHR_INIT1       equ     'i'             ; Initialize begin
CHR_INIT2       equ     'I'             ; Initialize end
CHR_BUG         equ     '~'             ; Bug hit
CHR_RETRY       equ     '!'             ; Fail retry
CHR_OVERFLOW    equ     '^'             ; Transfer buffer > 64K
CHR_RANGE       equ     '%'             ; Range clipped
CHR_INVSEC      equ     '&'             ; Start sector invalid
CHR_ERROR       equ     'E'             ; Error

;----- Normal constant
TRUE            equ     1               ; Boolean
FALSE           equ     0

BELL            equ     7               ; Keys
TAB             equ     9
RETURN          equ     13
LINEFEED        equ     10
ESCKEY          equ     27

RL              equ     13, 10          ; Return+Linefeed
EOS             equ     '$'             ; End of sentence
EOM             equ     RL, EOS         ; End of message
EOL             equ     RL              ; End of line
EOF             equ     26              ; End of file

;----- INT values
DOS             equ     21h             ; DOS function rq interrupt
VIDEO           equ     10h             ; Video interrupt
KEYB            equ     16h             ; Keyboard interrupt
ONEBYTE         equ     03h             ; One-byte interrupt

DOS_PRNMSG      equ     09h             ; Output string($)
DOS_PRNCHAR     equ     02h             ; Output char
DOS_EXIT        equ     4ch             ; Exit to caller
DOS_GETLOL      equ     52h             ; Get list of list
DOS_GETVER      equ     30h             ; Get DOS version
DOS_SETVECTOR   equ     25h             ; Set vector
DOS_FLUSH       equ     0dh             ; Reset disk

VD_GETPAGE      equ     0fh             ; Get page/attr
VD_PRNCHAR      equ     0eh             ; Display char
VD_PRNSTR       equ     13h             ; Display string
VD_GETCURSOR    equ     03h             ; Get cursor shape/position
VD_GETATTR      equ     08h             ; Get test attr at cursor

KB_READKEY      equ     00h             ; Read a key
KB_TESTKEY      equ     01h             ; Test if key ready


;----- device request   command
DEV_RQ          equ     es:[di]         ; device request header

DR0_INIT        equ     00h             ; initialize
DR1_MEDIACHK    equ     01h             ; media check
DR2_BUILDBPB    equ     02h             ; build BPB
DR4_INPUT       equ     04h             ; input/read
DR8_OUTPUT      equ     08h             ; output/write
DR9_OUTPUTV     equ     09h             ; output verify/write
DR_MAXNUM       equ     09h             ; max request number

;----- device error code
DER_NOERR       equ     0000h           ; no error
DEV_ERROR       equ     8000h           ; error bit
DER_PROTECT     equ     8000h           ; write-protect violation
DER_UKUNIT      equ     8001h           ; unknown unit
DER_NOTREADY    equ     8002h           ; drive not ready
DER_UKCMD       equ     8003h           ; unknown command
DER_CRC         equ     8004h           ; CRC error
DER_BADLEN      equ     8005h           ; bad drive request structure length
DER_SEEKERR     equ     8006h           ; seek error
DER_UKMEDIA     equ     8007h           ; unknown media
DER_MISSEC      equ     8008h           ; sector not found
DER_OUTPAPER    equ     8009h           ; printer out of paper
DER_WRFAULT     equ     800Ah           ; write fault
DER_RDFAULT     equ     800Bh           ; read fault
DER_GENERAL     equ     800Ch           ; general failure
DER_DISCHG      equ     800Fh           ; invalid disk change

;----- application error code
APE_NOERR       equ     00h             ; no error
APE_READ        equ     01h             ; read fault
APE_WRITE       equ     02h             ; write fault
APE_ERASE       equ     03h             ; erase error
APE_NODEV       equ     04h             ; no device/flash installed
APE_FORMAT      equ     05h             ; format error
APE_NOFLASH     equ     06h             ; no flash
APE_ABORT       equ     0ffh            ; user abort

; Macros
;============================================================================

XIN             macro WhichPort         ; In from a port
                  mov dx, WhichPort
                  in al, dx
                endm

XOUTB1          macro Value             ; Out with one value
                  mov al, Value
                  out dx, al
                endm

XOUTB2          macro WhichPort, Value  ; Out with port/value
                  mov dx, WhichPort
                  mov al, Value
                  out dx, al
                endm

DOSINT          macro                   ; DOS interrupt
                  int DOS
                endm

CALLDOS         macro SubFunc           ; DOS function call
                  mov ah, SubFunc
                  DOSINT
                endm

CALLDOSX        macro SubFuncx          ; DOS function call via AX
                  mov ax, SubFuncx
                  DOSINT
                endm

CALLDOS2        macro SubFunc,AL_val    ; DOS function call with al
                  mov ax, SubFunc*256+Al_val
                  DOSINT
                endm

PRINTMSG        macro sMsg              ; Print message use DOS
                  mov dx, offset sMsg
                  mov ah, DOS_PRNMSG
                  DOSINT
                endm

PRINTERRMSG     macro sErr              ; Print error message
                  PRINTMSG  msg_error
                  PRINTMSG  msg_errcode
                  PRINTMSG  sErr
                endm    

DOSSETVEC       macro Interrupt, Vector
                  mov ax, DOS_SETVECTOR*256+Interrupt
                  mov dx, offset Vector
                  DOSINT
                endm

DEB_PUTC        macro Char              ; Debug putc()
ifdef           _DEBUG
                  push ax
                  mov al, Char
                  call _deb_outchar
                  pop ax
else            ;_DEBUG
                ;;; do nothing
endif           ;_DEBUG
                endm

GETRQADDR       macro                   ; Get request ptr to ES:DI
                  les di, [req_headadr]
                endm

SETBUFADDR      macro                   ; Save transfer buffer addr
                  mov cx, ax            ; Adjust DX:AX
                  and ax, 000fh         ; make offset minimum
                  shr cx, 4             ; SHOULD I ?????
                  add dx, cx
                  mov [tbuf_seg], dx
                  mov [tbuf_ofs], ax
                endm

DELAY           macro                   ; Delay macro
                  jmp short $+2
                endm

BREAK_HERE      macro                   ; Break to debugger
ifdef           _DEBUGGER
                  int ONEBYTE
endif           ;_DEBUGGER
                endm


; Structure
;============================================================================
;----------------------------------------------------------------------------
;structure of the device driver request header
;----------------------------------------------------------------------------
REQ_HEAD_PUB    struc
len             db      ?                       ; request length
unit            db      ?                       ; unit number
command         db      ?                       ; command code
status          dw      ?                       ; return status
reserved        db      8 dup (?)
REQ_HEAD_PUB    ends

;----- All requests
REQ_ALL         struc
                db      (16h+4+1) dup (?)       ; max size
REQ_ALL         ends

;----- Request 0: init
REQ_INIT        struc                           
                db      (type REQ_HEAD_PUB) dup (?)
init_num_unit   db      ?                       ; Number of unit
init_free1_ofs  dw      ?                       ; First free byte ofs
init_free1_seg  dw      ?                       ; First free byte seg
init_bpb_ofs    dw      ?                       ; BPB array ofs (cmd line ?)
init_bpb_seg    dw      ?                       ; BPB array seg
init_drv_num    db      ?                       ; driver number (3+)
REQ_INIT        ends    

;----- Request 1: media check
REQ_MEDIA       struc
                db      (type REQ_HEAD_PUB) dup (?)
mdc_media       db      ?                       ; media descriptor
mdc_status      db      ?                       ; status
mdc_pvid_addr   dd      ?                       ; Previous volume ID addr(3+)
REQ_MEDIA       ends

;----- Request 2: build BPB
REQ_BUILD_BPB   struc
                db      (type REQ_HEAD_PUB) dup (?)
bpb_media       db      ?                       ; media descriptor
bpb_trans_ofs   dw      ?                       ; transfer address offset
bpb_trans_seg   dw      ?                       ; transfer address segment
bpb_bpb_ofs     dw      ?
bpb_bpb_seg     dw      ?                       ; BPB address
REQ_BUILD_BPB   ends

;----- Request 4,8,9: I/O
REQ_IO          struc   
                db      (type REQ_HEAD_PUB) dup (?)
io_media        db      ?                       ; media descriptor
io_trans_ofs    dw      ?                       ; transfer address offset
io_trans_seg    dw      ?                       ; transfer address segment
io_sec_cnt      dw      ?                       ; sector count
io_start_sec    dw      ?                       ; starting sector
io_pvid_addr    dd      ?                       ; Previous volume ID addr(3+)
REQ_IO          ends



; Code start
;============================================================================
.186            ; our PDA uses 80186

code            segment public 'code'

ifdef           _COMFILE
                assume  cs:code, ds:code, es:code
                org     100h                    ; .com file start at 0100h
else
ifdef           _DEVTEST
                assume  cs:code, ds:code, es:code
                org     100h                    ; .com file start at 0100h
else            ;_DEVTEST
                assume  cs:code, ds:code, es:NOTHING
                org     0h                      ; drivers start at offset 0
endif           ;_DEVTEST
endif           ;_COMFILE

start:

ifdef           _COMFILE

                jmp     @com_start

else            ;_COMFILE

ifdef           _DEVTEST

                jmp     @test_start

myreq           REQ_ALL     <>                  ; Universal request buffer

endif           ;_DEVTEST
endif           ;_COMFILE

;++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
; Driver information data block
;----------------------------------------------------------------------------
; device header begin
;----------------------------------------------------------------------------
header          dd      -1                      ; pointer to next driver
                dw      0000h                   ; device attribute word
ifndef          _COMFILE
                dw      offset _strategy        ; pointer to strategy routine
                dw      offset _interrupt       ; pointer to interrupt routine
else            ;!_COMFILE
                dw      0
                dw      0
endif           ;!_COMFILE
                db      1                       ; number of drive
                db      'GS_FMD_'               ; name of driver
disknum         db      'X'                     ; which drive
; device header end
DEV_HEAD_LEN    equ     this byte - header

                db      0

appname         db      'G&S Flash Disk ', VER_NUM, ' '
APP_NAME_LEN    equ     this byte - appname
ifdef           _DEBUG
                db      'debug R '
else            ;_DEBUG
                db      'release '
endif           ;_DEBUG
                db      RELEASE_NUM, EOM, EOF

devstatus       db      DEV_WRITE       ; device status r/w
req_headadr     dd      ?               ; far pointer to request header

bpbary          dw      offset ourbpb

ourboot         label   byte
                db      'GS_'
                db      'FLASH_', RELEASE_NUM     ; 8 bytes OEM ID

ourbpb          label   byte            ; These BPB values are arbitrary
bytes_sector    dw      DEF_SEC_SIZE    ; bytes per sector
sec_cluster     db      1               ; sectors per cluster
sec_reserved    dw      1               ; reserved sector
num_fats        db      1               ; number of FAT
root_dirs       dw      DEF_ROOT_DIR    ; root dir entries
num_sec         dw      128             ; number of sectors
media_byte      db      DRV_MEDIA       ; media type
sector_fat      dw      3               ; sectors per FAT
                dw      1               ; sectors per track
                dw      1               ; sides
                dd      0               ; special hidden sectors
                dd      0               ; BigDOS num of sectors(num_sec=0)
                dw      00h             ; physical drive number
                db      00h ;29h        ; extended boot record signature
                dd      88888888h       ; volume serial number
                db      VOL_NAME        ; volume name(11 bytes)
                db      'FAT16   '      ; file system id(8 bytes)
bootcode:
copyright       db      'Copr. 1998 Shenzhen G&S Co. Ltd.', EOM
fatsecnum       dw      1               ; FAT sector start number
freserved       dw      0               ; flash reserved block
OURBOOTLEN      equ     this byte - ourboot

flash_kb        dw      0               ; total KB
flash_blk       dw      0               ; total blocks

DEV_INFO_LEN    equ     this byte - header
;++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

ifndef          _COMFILE

tbuf_ofs        dw      ?               ; Transfer buffer(r/w) offset
tbuf_seg        dw      ?               ; Transfer buffer(r/w) segment

;----------------------------------------------------------------------------
;strategy routine. this routine stores the address of the request header
;----------------------------------------------------------------------------
_strategy       proc    far 
                mov     word ptr cs:[req_headadr], bx   ; save offset
                mov     word ptr cs:[req_headadr+2], es ; save segment
                ret         
_strategy       endp        
                            
;----------------------------------------------------------------------------
;interrupt routine. this routine executes the command code in the req header.
;----------------------------------------------------------------------------
_interrupt      proc    far 
                pushf                           ; Save regs
                pusha       
                push    ds
                push    es
                ; ??? change stack ???

                mov     ax, cs                  ; set ds
                mov     ds, ax
                cld                             ; any string operations move up.

                GETRQADDR                       ; load address of req header
                mov     bl, DEV_RQ.command
                cmp     bl, DR_MAXNUM           ; see if command out of range
                ja      @err_rq

ifdef           _SHOWRQ
DEB_PUTC CHR_RQ
                mov     al, bl
                add     al, '0'
                call    _deb_outchar
endif           ;_SHOWRQ
;;;
;;;             Process request here
;;;             A block device must process these requests
;;;     00h INIT
;;;     01h MEDIA CHECK (block devices)
;;;     02h BUILD BPB (block devices)
;;;     04h INPUT
;;;     08h OUTPUT
;;;     09h OUTPUT WITH VERIFY
;;;                     
@process4:                                      ; Input
                cmp     bl, DR4_INPUT
                jne     @process8
                call    _devinput
                jmp     @done_int

@process8:                                      ; Output
                cmp     bl, DR8_OUTPUT
                jne     @process1
                call    _devoutput
                jmp     @done_int

@process1:                                      ; Media check
                cmp     bl, DR1_MEDIACHK
                jne     @process9
                mov     DEV_RQ.mdc_status, 1    ; Media not changed
                mov     ax, DER_NOERR
                jmp     @done_int

@process9:                                      ; Output with verify
                cmp     bl, DR9_OUTPUTV
                jne     @process0
                call    _devoutput;v
                jmp     @done_int

@process0:                                      ; Initialization
                cmp     bl, DR0_INIT
                jne     @process2
                call    _initialize
                jmp     @done_int

@process2:                                      ; Build BPB
                cmp     bl, DR2_BUILDBPB
                jne     @process3
                call    _buildbpb
                jmp     @done_int

@process3:      ; other requsts are invalid
@process5:
@process6:
@process7:

@err_rq:                
                mov     ax, DER_UKCMD           ; unknown command error code
@done_int:
                or      ax, 0100h               ; set the 'done' bit
                GETRQADDR
                mov     DEV_RQ.status, ax

                ; ??? restore stack ???
                pop     es                      ; Restore regs
                pop     ds
                popa
                popf
                ret
_interrupt      endp


ifdef           _DEBUG
;----------------------------------------------------------------------------
; Display a char to the video(for debug usage)
;----------------------------------------------------------------------------
_deb_outchar    proc    near
                pushf
                push bx                         ; save regs
                push ax
                mov ah, VD_GETPAGE
                int VIDEO                       ; get the current page
                pop ax
                mov ah, VD_PRNCHAR              ; print the character
                int VIDEO
                pop bx                          ; restore regs
                popf
                ret
_deb_outchar    endp
endif           ;_DEBUG


;----------------------------------------------------------------------------
; Build BPB
;----------------------------------------------------------------------------
_buildbpb       proc    near
DEB_PUTC CHR_BUILDBPB1
                mov     DEV_RQ.bpb_bpb_ofs, offset ourbpb    ; the offset
                mov     DEV_RQ.bpb_bpb_seg, cs               ; in our CS
                mov     word ptr DEV_RQ.bpb_trans_ofs, 1     ; first FAT sector
                mov     ax, DER_NOERR
DEB_PUTC CHR_BUILDBPB2
                ret     
_buildbpb       endp    

                        
;----------------------------------------------------------------------------
; Process device input(read)
;----------------------------------------------------------------------------
_devinput       proc    near
DEB_PUTC CHR_INPUT1
                mov     dx, DEV_RQ.io_trans_seg              ; Get transfer
                mov     ax, DEV_RQ.io_trans_ofs              ; address
                SETBUFADDR
                mov     cx, DEV_RQ.io_sec_cnt                ; Get sec/count
                mov     ax, DEV_RQ.io_start_sec
                call    _readsec
DEB_PUTC CHR_INPUT2
                ret     
_devinput       endp    
                        
                        
;----------------------------------------------------------------------------
; Process device output(write)
;----------------------------------------------------------------------------
_devoutput      proc    near
DEB_PUTC CHR_OUTPUT1
                cmp     byte ptr [devstatus], DEV_READONLY
                jne     @can_write          ; Readonly ?
                mov     ax, DER_PROTECT
ifdef           _DEBUG
                jmp     @end_writerq
else            ;_DEBUG
                ret
endif           ;_DEBUG
@can_write:
                mov     dx, DEV_RQ.io_trans_seg     ; Get transfer ptr
                mov     ax, DEV_RQ.io_trans_ofs
                SETBUFADDR
                mov     cx, DEV_RQ.io_sec_cnt       ; Get sector count
                mov     ax, DEV_RQ.io_start_sec     ; Start sector
                call    _writesec
@end_writerq:
DEB_PUTC CHR_OUTPUT2
                ret     
_devoutput      endp


;----------------------------------------------------------------------------
; Process device output(write) with verify
;----------------------------------------------------------------------------
;_devoutputv     proc    near
;DEB_PUTC CHR_OUTPUT3
;                cmp     byte ptr [devstatus], DEV_READONLY
;                jne     @can_writev
;                mov     ax, DER_PROTECT
;ifdef           _DEBUG
;                jmp     @end_writerqv
;else            ;_DEBUG
;                ret
;endif           ;_DEBUG
;@can_writev:
;                mov     dx, DEV_RQ.io_trans_seg
;                mov     ax, DEV_RQ.io_trans_ofs
;                SETBUFADDR
;                mov     cx, DEV_RQ.io_sec_cnt
;                mov     ax, DEV_RQ.io_start_sec
;                call    _writesec
;@end_writerqv:
;DEB_PUTC CHR_OUTPUT4
;                ret
;_devoutputv     endp

endif            ;!_COMFILE

                        
;****************************************************************************
; Device dependent code
;
; for each kind of flash memory
; you need to implement the following procs and make some changes
; of other messages/procs/vars if needed:
;
; 1. _readsec: read sector(s)
; 2. _writesec: write sector(s)
; 3. _resetflash: reset flash memory
; 4. _do_format: initialize flash memory and write boot area to flash
; 5. _getflashinfo: get flash information
; 6. _do_scan1: perform read test(.com file)
; 7. _do_scan2: perform write test(.com file)
;****************************************************************************
TMP_BUF1_SIZE   equ    (16*FLASH_BLK_SIZE)
TMP_BUF2_SIZE   equ    FLASH_BLK_SIZE

FLASH_SEC_SIZE  equ     512  ; FLASH sector size
SPARE_SIZE      equ     16   ; Each 512 bytes block has 16 bytes spare space
FLASH_BLK_SIZE  equ     (FLASH_SEC_SIZE+SPARE_SIZE)
                        
DEF_DELAY_LOOP  equ     500                 ; Default delay loop times
MAX_DELAY_LOOP  equ     30000               ; Maximum delay loop times
DELAY_INC       equ     300                 ; Increment before retry
                        
; Ports                 
PORT_BASE       equ     570h
PORT_CMD        equ     (00h+PORT_BASE)     ; Command port
PORT_ADDR       equ     (01h+PORT_BASE)     ; Address port
PORT_STATUS     equ     (02h+PORT_BASE)     ; Status port
PORT_WRITE      equ     (03h+PORT_BASE)     ; Write data port
PORT_READ       equ     (06h+PORT_BASE)     ; Read data port

; Commands
CMD_SEQ_DI      equ     080h                ; Sequential Data Input
CMD_READ0       equ     000h                ; Read 0: 0-255
CMD_READ1       equ     001h                ; Read 1: 256-511
CMD_READ2       equ     050h                ; Read 2: 512-527
CMD_READ_ID     equ     090h                ; Read ID
CMD_RESET       equ     0ffh                ; Reset
CMD_PAGE_PRG    equ     010h                ; Page Program
CMD_BLK_ERA1    equ     060h                ; Block Erase(2 steps)
CMD_BLK_ERA2    equ     0d0h
CMD_ERA_SUSP    equ     0b0h                ; Erase suspend
CMD_ERA_RESM    equ     0d0h                ; Erase Resume
CMD_READ_STA    equ     070h                ; Read Status

; Status commands
STAT_WD         equ     00000000b           ; Write protected(disable): bit 0=0
STAT_WE         equ     00000001b           ; Write enable: bit 0=1
STAT_CE         equ     00000000b           ; Chip enable: bit 1=0
STAT_CD         equ     00000010b           ; Chip disable: bit 1=1
STAT_SE         equ     00000000b           ; Spare enable: bit 2=0
STAT_SD         equ     00000100b           ; Spare disable: bit 2=1
STAT_DOWN       equ     (STAT_CD+STAT_SD+STAT_WD)
STAT_WRITE      equ     (STAT_CE+STAT_SE+STAT_WE)

READ_MASK       equ     01000000b           ; Read state mask
WRITE_MASK      equ     01000001b           ; Write state mask
ERASE_MASK      equ     01100001b           ; Erase state mask
GOOD_STAT       equ     01000000b           ; _readstat return success code

BUG_BYTE        equ     0E0h                ; Bug byte if last written

DEF_RESV_BLK    equ     128                 ; default reserved blocks

flash_sec       dw      0                   ; flash memory sectors
                        
loop_count1     dw      DEF_DELAY_LOOP      ; Delay loop times

;----- Used in _writesec
write_size      dw      ?                   ; Write size
;                dw      ?                   ; high word
sec_count       dw      ?                   ; Sector count
wr_retry        db      ?                   ; Write retry
first_blk_no    dw      ?                   ; First block number
                                            ; Must and 0fff0h

; IN: AX=sec num
; OUT: AX=blk num, DX=blk ofs
; CX is destroied
SEC_TO_BLK      macro                       ; Calc blk num and ofs via sector
                  mov     cx, DEF_SEC_SIZE
                  mul     cx
                  mov     cx, FLASH_BLK_SIZE
                  div     cx
                endm

;----------------------------------------------------------------------------
; Read 16 blocks to tmp_buf
; IN:
; OUT:
;   Carry set if failed
; REG: ALL
;----------------------------------------------------------------------------
_read16blk      proc    near
                mov     ax, cs              ; Get buffer ptr to ES:DI
                mov     es, ax
                lea     di, tmp_buf
                mov     cx, [first_blk_no]  ; Get start block
                XOUTB2  PORT_STATUS, STAT_CE
                XOUTB2  PORT_CMD, CMD_READ0 ; Region select

                XOUTB2  PORT_ADDR, 0        ; Send addresses(from 0)
                XOUTB1  cl
                and     ch, 01fh
                XOUTB1  ch

                mov     dx, PORT_READ
;                cld
                mov     cx, TMP_BUF1_SIZE
@r16b1:
                in      al, dx              ; Read to buffer (ES:DI)
                stosb
                loop    @r16b1

                XOUTB2  PORT_STATUS, STAT_DOWN      ; Shut down chip

                call    _readstat           ; Get result
                and     al, READ_MASK
                cmp     al, GOOD_STAT
                jne     @rberr

                clc
                ret
@rberr:
                stc
                ret
_read16blk      endp

           
;----------------------------------------------------------------------------
; Write 16 blocks from tmp_buf
; IN:      
; OUT:     
;   Carry set if failed
; REG: ALL 
;----------------------------------------------------------------------------
_write16blk     proc    near
;                cld
                mov     byte ptr [wr_retry], 0      ; retry=0
@delblk:   
BREAK_HERE
                mov     ax, [first_blk_no]  ; del 16 blocks
                call    _del16blk
                jc      @writebad
           
                lea     si, tmp_buf         ; Get buffer ptr to DS:SI
                mov     cx, ax              ; Keep start block
                mov     bx, 0               ; block counter
                mov     bp, ax              ; save start block


; Can only write one block each time
@w16b0:    
                add     cx, bx              ; CX=Start block, BX=block index
           
                XOUTB2  PORT_STATUS, STAT_WRITE    ; Notify begin
           
                XOUTB2  PORT_CMD, CMD_READ0 ; Region select
                XOUTB1  CMD_SEQ_DI          ; Notify write
           
                XOUTB2  PORT_ADDR, 0        ; Send addresses(from 0)
                XOUTB1  cl
                and     ch, 01fh
                XOUTB1  ch
           
                mov     dx, PORT_WRITE
                mov     cx, FLASH_BLK_SIZE
@w16b1:
                lodsb                       ; Read from buffer
                out     dx, al              ; Write to port
                nop                         ; nop=3 clock in 186
                nop                         ; while jmp short=13
                loop    @w16b1

ifdef _BUGGY
                cmp     al, BUG_BYTE
                jne     @w16b2
DEB_PUTC CHR_BUG
; To fix the chip's bug, it should out one more byte,
                XOUTB1  0
endif           ; _BUGGY

@w16b2:
                XOUTB2  PORT_CMD, CMD_PAGE_PRG  ; Write one blk finished
                mov     cx, [loop_count1]   ; delay
@loopwrite:             
                DELAY
                loop    @loopwrite

                XOUTB2  PORT_STATUS, STAT_DOWN  ; Shut down chip
                        
                call    _readstat
                and     al, WRITE_MASK
                cmp     al, GOOD_STAT
                mov     cx, bp              ; restore CX
                je      @nextblk

@writebad:
                mov     ax, [loop_count1]   ; Inc delay loop
                cmp     ax, MAX_DELAY_LOOP
                jae     @chkretry
                add     ax, DELAY_INC
                mov     word ptr [loop_count1], ax
@chkretry:
DEB_PUTC CHR_RETRY
                inc     byte ptr [wr_retry] ; Failed, retry ?
                cmp     byte ptr [wr_retry], MAX_RETRY
                ja      @writeabort
                jmp     @delblk
@writeabort:
                stc
                ret
@nextblk:
                inc     bl
                cmp     bl, 16              ; loop 16 times
                jae     @donewrite
                jmp     @w16b0
@donewrite:
                clc
                ret

_write16blk     endp



ifndef          _COMFILE
;----------------------------------------------------------------------------
; Read sector(s)
; IN:
;   AX=start sector number
;   CX=sector count
; OUT:
;   CX=sector actually read
;   AX=error code, DER_NOERR if no error
; REG: ALL
;----------------------------------------------------------------------------
_readsec        proc    near
; In KM29xxx, you need to
; 1. calc position
; 2. send diff cmd for 3 part(0..255, 256..511, 512..527)
; 3. read to buffer
                mov     bp, ax
                call    _chksecrange        ; Assume sector range
                mov     ax, bp
                cmp     cx, 0               ; Nothing to write ?
                jne     @calc_ofs
                mov     ax, DER_MISSEC
                ret

@calc_ofs:
BREAK_HERE
                mov     di, [tbuf_ofs]      ; Get transfer ptr
                mov     si, [tbuf_seg]
                mov     es, si
                xor     si, si              ; SI = sector counter

                mov     bx, cx              ; Save to BX=sector count
                SEC_TO_BLK
                mov     bp, ax              ; AX=block number, save it
                mov     cx, dx

                XOUTB2  PORT_STATUS, STAT_CE

                cmp     cx, 256             ; determine which region
                jae     @rdreg_1
                mov     al, CMD_READ0       ; 1st part
                jmp     @rdreg_2
@rdreg_1:
                mov     al, CMD_READ1       ; 2nd part
                sub     cx, 256
                cmp     cx, 256
                jb      @rdreg_2

                sub     cx, 255             ; Calc bytes to be skipped
                mov     dx, PORT_CMD        ; Always 1 here
                out     dx, al
                XOUTB2  PORT_ADDR, 255      ; start from 511
                mov     ax, bp
                out     dx, al
                and     ah, 01fh
                XOUTB1  ah
                mov     dx, PORT_READ
@pread:
                in      al, dx              ; Skip bytes
                loop    @pread              ; always 1 if secsize=512
                jmp     @rd_sec

@rdreg_2:
                mov     dx, PORT_CMD        ; Region select
                out     dx, al

                XOUTB2  PORT_ADDR, cl       ; Send addresses
                mov     ax, bp              ; Get blk num
                out     dx, al
                and     ah, 01fh
                XOUTB1  ah

                mov     dx, PORT_READ
@rd_sec:
                cmp     bx, 0               ; BX = sector remain
                je      @done_rd1           ; No sector to read ?
                dec     bx
                mov     cx, DEF_SEC_SIZE    ; Size to read
@rd_port_1:
                in      al, dx              ; Read to buffer (ES:DI)
                stosb
                loop    @rd_port_1

                inc     si                  ; SI = Sector counter
                jmp     @rd_sec             ; LOOP until all sectors read

@done_rd1:
                XOUTB2  PORT_STATUS, STAT_DOWN
                call    _readstat
                and     al, READ_MASK
                cmp     al, GOOD_STAT
                jne     @rderr
                mov     ax, DER_NOERR       ; Return code
                mov     cx, si              ; Sector count
                ret
@rderr:
                mov     ax, DER_RDFAULT
                ret
_readsec        endp


;----------------------------------------------------------------------------
; Copy write buffer to tmp_buf
; IN:                       
;   ES:DI=destination       
;   SI=source offset        
;   CX=count in byte        
; OUT:                      
; REG: AX,CX,SI             
;----------------------------------------------------------------------------
_copytotmp      proc    near
                mov     ax, [tbuf_seg]
                mov     ds, ax
;                test    cl, 1               ; restore this piece of code
;                jz      @copyit             ; if sector/block size is odd
;                movsb                       ; odd fix
@copyit:
                shr     cx, 1               ; faster use movsw
                rep     movsw
                mov     ax, cs              ; restore DS
                mov     ds, ax
                ret         
_copytotmp      endp        


;----------------------------------------------------------------------------
; Write sector(s)
; IN:
;   AX=start sector number
;   CX=sector count
; OUT:                        
;   CX=sector actually write
;   AX=error code, DER_NOERR=no error
; REG: ALL
;----------------------------------------------------------------------------
_writesec       proc    near
; In KM29xxx, you need to
; 1. calc position
; 2. save 16 blocks
; 3. write data to saved buffer
; 4. del 16 blocks
; 5. write 16 blocks
; 6. loop 1 if needed

                mov     bp, ax
                call    _chksecrange        ; Check sector range
                mov     ax, bp
                cmp     cx, 0               ; Nothing ?
                jne     @write1
                mov     ax, DER_MISSEC
                ret

@write1:
                mov     dx, cs
;                mov     ds, dx
                mov     es, dx
                mov     si, [tbuf_ofs]      ; Get transfer addr

                xor     di, di              ; Offset=0
                mov     [sec_count], cx
                SEC_TO_BLK                  ; Sector to blk:ofs(AX:DX)
                add     di, dx              ; DX=block offset, add offset
                mov     cx, ax              ; AX=block number
                and     ax, 0fff0h          ; Get the first of 16 blk
                sub     cx, ax
                mov     [first_blk_no], ax  ; Save first block number
                mov     ax, cx
                mov     cx, FLASH_BLK_SIZE
                mul     cx
                add     di, ax              ; Add blocks size, DI=BO
                mov     ax, [sec_count]     ; Calc write size
                mov     cx, DEF_SEC_SIZE
                mul     cx
                mov     word ptr [write_size], ax    ; Save it
;                mov     word ptr [write_size+2], dx
ifdef           _DEBUG
                cmp     dx, 0               ; Check dx(rq > 64k?)
                je      @write2
DEB_PUTC CHR_OVERFLOW
endif           ;_DEBUG

; 1. Save blocks
@write2:                      
                mov     bp, di              ; DI will be destroied
                call    _read16blk
                mov     di, bp
                jc      @wrerr
; 2. Write sector to saved buffer
;      16 blk
;    |=============|
; 1.    |----|            ; write size in range
; 2.    |---------------| ; write size out of range
;
                mov     ax, word ptr [write_size]       ; L > 16blk-BO ?
;                mov     dx, word ptr [write_size+2]     ; DX:AX=L
                mov     cx, TMP_BUF1_SIZE               ; 16*FLASH_BLK_SIZE
                sub     cx, di                  ; CX=16blk-BO
                add     di, offset tmp_buf      ; Make DI the actual index
;                cmp     dx, 0                   ; DX>0, surely DX:AX>CX
;                ja      @write3
                cmp     ax, cx                  ; L > 16blk-BO ?
                ja      @write3                 ; Yes, jump
                mov     cx, ax                  ; No, WL=L
                jmp     @write4
                              
@write3:        ;  Not enough to hold the whole write buffer
BREAK_HERE
                sub     ax, cx                  ; Now CX=WL=16blk-BO
;                sbb     dx, 0                   ; L -= WL
                mov     word ptr [write_size], ax
;                mov     word ptr [write_size+2], dx      ; Save write size

                call    _copytotmp              ; SI is advanced

                push    si                      ; Write a portion of data
                call    _write16blk
                pop     si
                jc      @wrerr

                mov     ax, [first_blk_no]      ; Adv. 16 blks
                xor     di, di                  ; Offset=0
                add     ax, 16
                mov     [first_blk_no], ax      
                jmp     @write2

@write4:        ; Can hold the remain buffer
                call    _copytotmp
@write5:                      
                call    _write16blk
                jc      @wrerr
                mov     cx, [sec_count]         ; Return sector count
                mov     ax, DER_NOERR           ; and error code
                ret
@wrerr:
                xor     cx, cx
                mov     ax, DER_WRFAULT
                ret
_writesec       endp


;----------------------------------------------------------------------------
; Check and assume sector range
; IN:
;   AX=start sector
;   CX=sector count
; OUT:
;   CX=sector count
; REG: AX, CX, DX
;----------------------------------------------------------------------------
_chksecrange    proc    near

                mov     dx, word ptr [flash_sec]
                dec     dx
                cmp     dx, ax              ; Total sector-1 < start sector ?
                jb      @sec_err1           ; Yes, error!
                inc     dx
                sub     dx, ax              ; Max remain sector
                cmp     cx, dx              ; Remain secotr < sector count ?
                ja      @sec_err2           ; <, valid range
                ret
@sec_err1:
                xor     cx, cx              ; Invalid start sector
DEB_PUTC CHR_INVSEC
                ret
@sec_err2:
                mov     cx, dx              ; no, alter it
DEB_PUTC CHR_RANGE
                ret

_chksecrange    endp

endif           ;!_COMFILE


;----------------------------------------------------------------------------
; Read status (operation result)
; IN:
; OUT:
;   AL=status
; REG: AX,DX                  
;----------------------------------------------------------------------------
_readstat       proc    near
                XOUTB2  PORT_STATUS, STAT_CE    ; Select
                XOUTB2  PORT_CMD, CMD_READ_STA  ; Read status command
                XIN     PORT_READ               ; Read status
                mov     ah, al
                XOUTB2  PORT_STATUS, STAT_DOWN  ; Shut down
                mov     al, ah
                ret
_readstat       endp


;----------------------------------------------------------------------------
; Erase 16 blocks
; IN:
;   AX=Block number
; OUT:
;   Carry set if error
; REG: NONE
;----------------------------------------------------------------------------
_del16blk       proc    near
                push    ax                      ; Save registers
                push    dx
                push    cx

                mov     cx, ax
                XOUTB2  PORT_STATUS, STAT_WRITE     
                XOUTB2  PORT_CMD, CMD_BLK_ERA1  ; First step
                XOUTB2  PORT_ADDR, cl
                and     ch, 01fh
                XOUTB1  ch
                XOUTB2  PORT_CMD, CMD_BLK_ERA2  ; Second step

                mov     cx, [loop_count1]       ; Delay
@loopdel:
                DELAY
                loop    @loopdel

                XOUTB2  PORT_STATUS, STAT_DOWN  ; Shut down chip

                call    _readstat               ; Get operation result
                and     al, ERASE_MASK
                cmp     al, GOOD_STAT
                jne     @delbad
                clc
                jmp     @donedel
@delbad:
                stc
@donedel:
                pop     cx                      ; Restore registers
                pop     dx
                pop     ax

                ret
_del16blk       endp


@driver_end     =       $                   ; +tmp_buf=last part of driver code

; Initialize tmp_buf only contains 1 byte.
; After initialization, the code following will be
; overwrited for use of buffer(16 block), save 16 blocks-1
; BE SURE NOT TO CALL _read16blk/_write16blk BEFORE
; FINISHING INITIALIZATION !!!

; For non-device, the buffer locate at the end to save size
ifndef          _COMFILE
ifndef          _NEEDBUF
tmp_buf         db      0
else            ;!_NEEDBUF
tmp_buf         db      (TMP_BUF1_SIZE) dup(?)
endif           ;!_NEEDBUF
endif           ;!_COMFILE
                            
; Code below is not resident
;============================================================================

root_sec        dw      0                   ; how many sec in root dir
vol_0           dw      0                   ; to save volumn sector num
vol_1           dw      0

fat16_start     db      DRV_MEDIA, 0ffh, 0ffh, 0ffh
FAT16_START_LEN equ     4

disk_vol        db      VOL_NAME            ; 11-byte volume name
                db      000001000b          ; volume label attribute
                db      10 dup (0)          ; reserved space
                dw      953
                        ;FEDCBA9876543210b
                        ;YYYYYYYMMMMDDDDD   YYYY=year-1980
                dw      00010010010100100b  ; DATE
                db      6 dup (0)           ; more reserved space
DISK_VOL_LEN    equ     32


;----------------------------------------------------------------------------
; Reset flash memory
; IN:                   
; OUT:
; REG: AX,DX
;----------------------------------------------------------------------------
_resetflash     proc    near
                XOUTB2  PORT_STATUS, STAT_CE    ; Select
                XOUTB2  PORT_CMD, CMD_RESET     ; Reset command
                XOUTB2  PORT_STATUS, STAT_DOWN  ; Shut down
                ret
_resetflash     endp    


;----------------------------------------------------------------------------
; Read one block to tmp_buf2
; IN:
;    AX=block num
; OUT:
;    AL=FALSE: faild
; REG:
;    AX, CX, DX, DI
;----------------------------------------------------------------------------
_readblk        proc    near
;                cld
                mov     cx, ax
                XOUTB2  PORT_STATUS, STAT_CE

                XOUTB2  PORT_CMD, CMD_READ0
                XOUTB2  PORT_ADDR, 0        ; Send addresses(from 0)
                XOUTB1  cl
                and     ch, 01fh
                XOUTB1  ch

                mov     cx, cs
                mov     es, cx
                mov     di, offset tmp_buf2
                mov     word ptr es:[di], 55h
                mov     cx, TMP_BUF2_SIZE   ; Size to read
                mov     dx, PORT_READ
@rb1:
                in      al, dx              ; Read to buffer (ES:DI)
                stosb
                loop    @rb1

                call    _readstat           ; Get operation result
                and     al, READ_MASK
                cmp     al, GOOD_STAT
                mov     al, TRUE
                je      @donerb
                mov     al, FALSE
@donerb:
                ret
_readblk        endp


;----------------------------------------------------------------------------
; Write one block from tmp_buf2
; IN:
;    AX=block num
; OUT:
;    AL=FALSE: faild
; REG:
;    AX, CX, DX, DI
;----------------------------------------------------------------------------
_writeblk       proc    near
                mov     cx, ax              ; Save to CX

                XOUTB2  PORT_STATUS, STAT_WRITE
                XOUTB2  PORT_CMD, CMD_READ0 ; Region select
                XOUTB1  CMD_SEQ_DI          ; Notify write
           
                XOUTB2  PORT_ADDR, 0        ; Send addresses(from 0)
                XOUTB1  cl
                and     ch, 01fh
                XOUTB1  ch

                mov     dx, PORT_WRITE
                mov     cx, TMP_BUF2_SIZE
                lea     si, tmp_buf2
@wblk1:
                lodsb
                out     dx, al              ; Write to port
                DELAY
                loop    @wblk1              ; Loop to fill

                XOUTB2  PORT_CMD, CMD_PAGE_PRG  ; Write one blk finished
                        
                mov     cx, [loop_count1]   ; delay
@loopwblk:
                DELAY
                loop    @loopwblk

                XOUTB2  PORT_STATUS, STAT_DOWN  ; Shut down chip
                        
                call    _readstat           ; Check state/result
                and     al, WRITE_MASK
                cmp     al, GOOD_STAT
                mov     al, TRUE
                je      @donewblk
                mov     al, FALSE
@donewblk:
                ret
_writeblk       endp


;----------------------------------------------------------------------------
; memset tmp_buf2 to AL
; IN:
;   ES=CS
;   AL=char to fill
; OUT:
; REG: DI, CX
;----------------------------------------------------------------------------
_memsetbuf      proc    near
                lea     di, tmp_buf2
                mov     cx, TMP_BUF2_SIZE
                rep     stosb
                ret
_memsetbuf      endp


;----------------------------------------------------------------------------
; Write boot info
; IN:
; OUT:
;   AL=FALSE: failed
; REG: ALL
;----------------------------------------------------------------------------
_writeboot      proc    near
; 1. delete needed blocks (already done in _do_format)
; 2. write boot sector(ourboot) 0 sector
; 3. write signature to first FAT
; 4. write root dir's volumn label(not implement)

                mov     ax, cs
                mov     es, ax

                mov     al, 0
                call    _memsetbuf          ; Copy boot rec to buffer
                lea     si, ourboot
                mov     cx, OURBOOTLEN
                lea     di, tmp_buf2
                rep     movsb

; !!! here I know that FAT header is at the end of block 0 !!!
; it must be altered if not
                lea     si, fat16_start     ; Copy FAT head to buffer
                mov     cx, FAT16_START_LEN
                lea     di, tmp_buf2
                add     di, DEF_SEC_SIZE
                rep     movsb

                mov     ax, 0               ; Write block 0
                call    _writeblk
                cmp     al, FALSE
                je      @wberr

                mov     al, 0
                call    _memsetbuf          ; Zero buffer
                mov     ax, [sector_fat]
                inc     ax                  ; Root start sector
                SEC_TO_BLK
                mov     [vol_0], ax
                mov     [vol_1], ax
                lea     di, tmp_buf2
                add     di, dx              ; Calc offset in buffer
                lea     si, disk_vol        ; Write volumn label to root dir
                mov     cx, TMP_BUF2_SIZE
                sub     cx, dx
                cmp     cx, DISK_VOL_LEN
                jb      @vol2blk
                mov     cx, DISK_VOL_LEN
                rep     movsb
                call    _writeblk
                cmp     al, FALSE
                je      @wberr
                jmp     @fillzero
@wberr:
                mov     al, FALSE           ; Error
                ret
@vol2blk:                                   ; Volumn is filled in two blocks
                inc     word ptr [vol_1]
                push    ax
                push    cx
                rep     movsb               ; Write first block
                push    si
                call    _writeblk
                pop     si
                mov     al, 0
                call    _memsetbuf
                pop     ax
                mov     cx, DISK_VOL_LEN    ; Fill another block
                sub     cx, ax
                pop     ax
                inc     ax
                lea     di, tmp_buf2
                rep     movsb
                call    _writeblk
                cmp     al, FALSE
                je      @wberr

ifdef           _DEBUG
                mov     ax, [vol_0]
                call    _readblk
                mov     ax, [vol_1]
                call    _readblk
endif

@fillzero:
                mov     al, 0
                call    _memsetbuf
                mov     ax, [sector_fat]
                add     ax, [root_sec]
                inc     ax                  ; AX=sys area sector count
                SEC_TO_BLK                  ; Calc blk count to hold sys area
                cmp     dx, 0
                je      @wb1
                inc     ax

@wb1:
                mov     cx, ax
                mov     ax, 1               ; Start from 1(2nd)
@wb2:
                cmp     ax, [vol_0]
                je      @wb3
                cmp     ax, [vol_1]
                je      @wb3
                push    ax
                push    cx
                call    _writeblk           ; Fill them to zero
                cmp     al, FALSE
                pop     cx
                pop     ax
                je      @wberr
@wb3:
                inc     ax
                cmp     ax, cx
                jb      @wb2

ifdef           _DEBUG                      ; Check it
                mov     ax, 0
@wb4:
                push    cx
                push    ax
                call    _memsetbuf          ; Fill buffer with AL
                call    _readblk            ; Read from flash
                cmp     al, FALSE
                pop     ax
                pop     cx
                je      @wberr
                inc     ax
                cmp     ax, cx
                jb      @wb4

endif           ;_DEBUG

                mov     al, TRUE            ; Success
                ret
_writeboot      endp



;----------------------------------------------------------------------------
; Show progress via block num;
; IN:
;   AX=block number
; OUT:
; REG:
;----------------------------------------------------------------------------
_showprg        proc    near
                push    ax
                push    dx
                test    al, 00110000b
                jnz     @noprint            ; 1/4 chance
                mov     dl, '.'
                CALLDOS DOS_PRNCHAR         ; Show progress
@noprint:
                pop     dx
                pop     ax
                ret
_showprg        endp


;----------------------------------------------------------------------------
; Format/initialize flash memory and make it a disk
; IN:
; OUT:
;   AL=APE_NOERR: success
;   otherwise AL=error code
; REG: ALL
;----------------------------------------------------------------------------
_do_format      proc    near
; 1. Zero all data, check for bad?
; 2. Calc sys params
; 3. Call _writeboot to init sys area
                CALLDOS     DOS_FLUSH
                PRINTMSG    msg_format

                mov     ax, [root_dirs]
                mov     cx, 32
                mul     cx                  ; Root dir size
                add     ax, DEF_SEC_SIZE-1  ; Round it
                mov     cx, DEF_SEC_SIZE
                div     cx
                mov     [root_sec], ax      ; Root dir sector count

                mov     ax, DEF_SEC_SIZE    ; Update BPB
                mov     [bytes_sector], ax

                mov     ax, [flash_sec]     ; Total sector
                mov     [num_sec], ax       ;  (2(TS-y-1-RS)+FSL+DSS-1)/DSS=y
                                            ; => y = (2*(TS-RS)+DSS+FSL-3)/(DSS+2)
                sub     ax, [root_sec]      ; Sub root sectors
                shl     ax, 1               ; Every sector use 2 bytes in FAT
                add     ax, DEF_SEC_SIZE    ; TS=total sec; RS=root sec
                add     ax, FAT16_START_LEN ; FSL=FAT16_START_LEN
                sub     ax, 3               ; DSS=DEF_SEC_SIZE
                xor     dx, dx              ;
                mov     cx, DEF_SEC_SIZE    ;
                add     cx, 2               ;
                div     cx                  ;
                mov     [sector_fat], ax

                mov     di, [flash_blk]     ; Include reserved blocks
                mov     ax, 0               ; Begin with first block

@erablk:
                call    _del16blk           ; Erase 16 block
                mov     dx, offset em_erase
                jc      @makeerr

@showfmtprg:
                call    _showprg
                add     ax, 16
                cmp     ax, di
                jb      @erablk             ; Finish ?

                mov     ax, 0               ; Check boot sector

                call    _readblk            ; Erased ?
                cmp     al, FALSE
                je      @makeerr
                lea     di, tmp_buf2
                mov     cx, TMP_BUF2_SIZE

                mov     al, 0ffh
                repe    scasb
                jcxz    @dowriteboot
                jmp     @makeerr

;@chkFF:
;                lodsb                       ; Loop to check
;                cmp     al, 0ffh            ; if they are all 0xFF
;                jne     @makeerr
;                loop    @chkFF
@dowriteboot:
                call    _writeboot          ; Write boot info
                cmp     al, FALSE
                mov     dx, offset em_wrboot
                je      @makeerr

                PRINTMSG    msg_endformat   ; Success
                mov     al, APE_NOERR
                ret

@makeerr:
                CALLDOS DOS_PRNMSG
                PRINTMSG    em_format       ; Error
                mov     al, APE_FORMAT
                ret
_do_format      endp


;----- Table of flash ID and their size
LEN_SIZETBL     equ     6
sizetbl1        dw      0eca4h, 0ec6eh, 0eceah, 0ece3h, 0ece6h, 0ec73h
sizetbl2        dw      512,    1024,   2048,   4096,   8192,   16384

;----------------------------------------------------------------------------
; Get flash memory information
; IN:
; OUT:                
;   AL=0: no flash
;   AL=1: success
;   AL=2: need to be formatted
; REG: ALL
;----------------------------------------------------------------------------
_getflashinfo   proc    near
; 1. get size of flash
; 2. if flash exists, get 0th sector(1st block), else exit error
; 3. if sector 0 is valid, get info and exit
; 4. return need to be formatted

                XOUTB2  PORT_STATUS, STAT_CE

                XOUTB2  PORT_CMD, CMD_READ_ID
                XOUTB2  PORT_ADDR, 0        ; Send addresses(from 0)
                XIN     PORT_READ
                mov     ah, al
                XIN     PORT_READ
                mov     cx, ax
                XOUTB2  PORT_STATUS, STAT_DOWN
                mov     ax, cx

                mov     cx, LEN_SIZETBL     ; Search in size table
                mov     dx, 0
                lea     di, sizetbl1
                repne   scasw
                jne     @donegetsize
                mov     bx, LEN_SIZETBL
                sub     bx, cx
                add     bx, offset sizetbl2 + 2
                mov     dx, [bx]

@donegetsize:
                mov     ax, dx
                cmp     ax, 0               ; No flash ?
                je      @errflash

                mov     [flash_kb], ax
                mov     cx, 1024            ; shl 1? Get block count
                mul     cx
                mov     cx, FLASH_SEC_SIZE
                div     cx
                mov     [flash_blk], ax
                sub     ax, DEF_RESV_BLK    ; Sub reserved blocks
                mov     cx, FLASH_BLK_SIZE
                mul     cx                  ; Get total bytes
                mov     cx, DEF_SEC_SIZE
                div     cx                  ; Get sector count
                mov     [flash_sec], ax

                mov     ax, DEF_RESV_BLK    ; Fill reserved block count
                mov     [freserved], ax

                mov     ax, 0               ; Read boot sector
                call    _readblk
                cmp     al, FALSE
                je      @errflash

;                cld
                lea     si, ourboot
                lea     di, tmp_buf2
                mov     cx, (8+3+8)         ; Jump+Name+BYTE_SEC..ROOT_DIRS
                repe    cmpsb
                je      @copyboot
                mov     al, 2               ; To be formatted
                ret
@copyboot:
                lea     di, ourboot         ; Duplicat boot record & BPB
                lea     si, tmp_buf2
                mov     cx, OURBOOTLEN
                rep     movsb
                mov     ax, [num_sec]
                mov     [flash_sec], ax
                mov     al, 1               ; Success
                ret
@errflash:
                mov     al, 0               ; Error
                ret
_getflashinfo   endp    


ifdef           _COMFILE
scan_ret        db      APE_NOERR

;----------------------------------------------------------------------------
; Show scan error
; IN:
;   AL=error code
; OUT:
; REG:
;----------------------------------------------------------------------------
_scan_err       proc    near
                mov     [scan_ret], al
                call    _show_err
                ret
_scan_err       endp


;----------------------------------------------------------------------------
; Scan flash memory method 1
; IN:
; OUT:
;   AL=APE_NOERR: success
;   otherwise AL=error code
; REG: ALL
;----------------------------------------------------------------------------
_do_scan1       proc    near
; 1. Proceed level 1: read 16 blk to tmp_buf, copy to tmp_buf+TMP_BUF1_SIZE
;    read 16 blk to tmp_buf again, cmp them, loop until end
                mov     cx, [flash_blk]
                mov     ax, 0
                mov     byte ptr [scan_ret], APE_NOERR
@scan1next:
                cmp     byte ptr [ctrl_break], 1
                je      @break
                cmp     ax, cx
                jae     @done_scan1
                call    _showprg

                push    cx
                mov     [first_blk_no], ax
                call    _read16blk              ; read 16 blk
                jc      @scan1err
                mov     cx, TMP_BUF1_SIZE
                lea     si, tmp_buf
                mov     di, si
                add     di, cx
                rep     movsb                   ; copy to another buffer
                call    _read16blk              ; read again
                jc      @scan1err
                mov     cx, TMP_BUF1_SIZE
                lea     si, tmp_buf
                mov     di, si
                add     di, cx
                repe    cmpsb
                jc      @scan1err
@scan1_3:
                mov     ax, [first_blk_no]
                pop     cx
                add     ax, 16
                jmp     @scan1next
@scan1err:
                mov     al, APE_READ
                call    _scan_err
                jmp     @scan1_3

@done_scan1:
                mov     al, [scan_ret]          ; Get return code
                ret

_do_scan1       endp


@break:
                mov     al, APE_ABORT
                mov     byte ptr [scan_ret], al
                retn


;----------------------------------------------------------------------------
; Scan flash memory method 2
; IN:
; OUT:
;   AL=APE_NOERR: success
;   otherwise AL=error code
; REG: ALL
;----------------------------------------------------------------------------
_do_scan2       proc    near
; 2. Ask to procced level 2: read 16 blk, del 16 blk, chk del, write 16 blk,
;    read 16 blk, cmp
                mov     cx, [flash_blk]
                mov     ax, 0
                mov     byte ptr [scan_ret], APE_NOERR
@scan2next:
                cmp     byte ptr [ctrl_break], 1
                je      @break
                cmp     ax, cx
                jae     @done_scan2
                call    _showprg

                push    cx
                mov     [first_blk_no], ax
                mov     byte ptr [wr_retry], 0
                call    _read16blk              ; read 16 blk
                jnc     @scan2_1
                mov     al, APE_READ
                jmp     @scan2err
@scan2_1:
                mov     cx, TMP_BUF1_SIZE
                lea     si, tmp_buf
                mov     di, si
                add     di, cx
                rep     movsb                   ; copy to another buffer

@scan2del:
                mov     ax, [first_blk_no]
                call    _del16blk
                jc      @scan2retry
                call    _read16blk              ; test delete
                jnc     @scan2_2
                mov     al, APE_READ
                jmp     @scan2err
@scan2_2:
                mov     al, 0ffh
                lea     di, tmp_buf
                mov     cx, TMP_BUF1_SIZE
                repe    scasb                   ; all deleted?
                je      @scan2copy
@scan2retry:
                inc     byte ptr [wr_retry]
                cmp     byte ptr [wr_retry], MAX_RETRY
                jbe     @scan2del
                mov     al, APE_ERASE
                jmp     @scan2err
@scan2copy:
                mov     cx, TMP_BUF1_SIZE       ; copy back
                lea     di, tmp_buf
                mov     si, di
                add     si, cx
                rep     movsb
@scan2write:
                call    _write16blk             ; write back
                jnc     @scan2_3
                inc     byte ptr [wr_retry]
                cmp     byte ptr [wr_retry], MAX_RETRY
                jbe     @scan2write
                mov     al, APE_WRITE
                jmp     @scan2err
@scan2_3:
                call    _read16blk              ; read again
                jnc     @scan2_4
                mov     al, APE_READ
                jmp     @scan2err
@scan2_4:
                mov     cx, TMP_BUF1_SIZE
                lea     si, tmp_buf
                mov     di, si
                add     di, cx
                repe    cmpsb                   ; compare
                je      @scan2_5
                mov     al, APE_WRITE
                jmp     @scan2err
@scan2_5:
                mov     ax, [first_blk_no]
                pop     cx
                add     ax, 16
                jmp     @scan2next

@done_scan2:
                mov     al, [scan_ret]
                ret
@scan2err:
                call    _show_err
                jmp     @scan2_5
                ret

_do_scan2       endp


endif           ;_COMFILE


;****************************************************************************
; End of device dependent code

                        
;----- Normal message   
msg_init        db      'Initilizing...', EOM
msg_endinit     db      'Finished.', EOM
msg_error       db      'Error found!', BELL, EOM
msg_errcode     db      'Error message: ', EOS
msg_format      db      'Formatting...', EOM
msg_endformat   db      'Format finished.', EOM
msg_disk1       db      'Driver installed as drive '
msg_disknum     db      '?'
                db      ':', EOM
msg_size1       db      ' KB total flash memory.', EOM
msg_size2       db      ' blocks reserved.', EOM
msg_readonly    db      'Device is readonly', EOM
msg_writable    db      'Device is writable', EOM
;----- Error message                        
em_noflash      db      'No flash installed', EOM
em_format       db      'Error formatting flash disk', EOM
em_erase        db      'Error erasing flash memory', EOM
em_wrboot       db      'Error writing system area', EOM
                        
;----------------------------------------------------------------------------
; Driver initialization
;----------------------------------------------------------------------------
_initialize     proc    near
DEB_PUTC CHR_INIT1
                PRINTMSG    appname         ; Show copyright
                PRINTMSG    copyright
                PRINTMSG    msg_init
                mov     ax, cs
                mov     es, ax
                call    _resetflash
                call    _getflashinfo       ; Get flash info
ifdef           _DEBUG
                jmp     @formatdsk          ; Always format
else            ;_DEBUG
                cmp     al, 0
                je      @noflash
                cmp     al, 1
                jne     @formatdsk
                PRINTMSG    msg_endinit
endif           ;_DEBUG

@initgood:

ifndef          _COMFILE
;                GETRQADDR                               ; ?????
;                mov     di, DEV_RQ.init_bpb_ofs         ; Get command line
;                mov     ax, DEV_RQ.init_bpb_seg
;                mov     es, ax
;                mov     cx, 80
;                mov     al, ' '
;                repe    scasb
;                je      @initfill
;                mov     al, es:[di-1]
;                mov     dx, offset msg_writable
;                cmp     al, 'R'                         ; Readonly ?
;                jne     @initfill
;                mov     byte ptr [devstatus], DEV_READONLY
;                mov     dx, offset msg_readonly
;@initfill:
;                CALLDOS DOS_PRNMSG
                ; Fill header
                GETRQADDR
                mov     byte ptr DEV_RQ.init_num_unit, 1
                mov     ax, offset @driver_end
                add     ax, TMP_BUF1_SIZE+1
                mov     word ptr DEV_RQ.init_free1_ofs, ax  ; Last byte resident
                mov     ax, offset bpbary
                mov     word ptr DEV_RQ.init_bpb_ofs, ax
                mov     ax, cs
                mov     word ptr DEV_RQ.init_free1_seg, ax
                mov     word ptr DEV_RQ.init_bpb_seg, ax
                mov     al, DEV_RQ.init_drv_num             ; Get drive num
                add     al, 'A'
                mov     [msg_disknum], al
                mov     [disknum], al

endif           ;!_COMFILE

@initshowsize:
                mov     ax, [flash_kb]      ; Show size
                call    _dos_outnum
                PRINTMSG    msg_size1
                mov     ax, [freserved]
                call    _dos_outnum
                PRINTMSG    msg_size2

ifndef          _COMFILE
                PRINTMSG    msg_disk1       ; Show drive num
endif           ;!_COMFILE

                mov     ax, DER_NOERR
                jmp     @doneinit
@formatdsk:
                call    _do_format          ; Format disk
                cmp     al, APE_NOERR
                je      @initgood
                mov     ax, DER_NOTREADY
                jmp     @doneinit
@noflash:
                PRINTERRMSG     em_noflash  ; No flash
                mov     ax, DER_NOTREADY
@doneinit:
DEB_PUTC CHR_INIT2
                ret
_initialize     endp


;----------------------------------------------------------------------------
; Converts the number in AX to ASCII and displays it.
; IN: AX
; OUT:
; REG: AX,BX,CX,DX
;----------------------------------------------------------------------------
_dos_outnum     proc    near
                mov     bx, 10              ; Initialize BX with divisor
                sub     cx, cx              ; Initialize digit counter
@divide:        inc     cx                  ; Increment counter
                sub     dx, dx              ; Zero high word of DX:AX
                div     bx                  ; Divide AX by 10
                push    dx                  ; Save remainder on stack
                or      ax, ax              ; Loop if AX != 0
                jnz     @divide
@output:
                pop     dx                  ; Retrieve digit from stack
                add     dl, '0'             ; Convert to ASCII
                CALLDOS DOS_PRNCHAR         ; Output it
                loop    @output             ; Loop until done
                ret
_dos_outnum     endp


ifdef           _COMFILE
;============================================================================

usage           db      RL, 'Usage(case sensitive):', RL, RL
                db      '  flashdsk F [blks] : format disk with reserved blks(128)', RL
                db      '  flashdsk R        : make driver readonly', RL
                db      '  flashdsk W        : make driver writable', RL
                db      '  flashdsk S[1|2]   : scan[r|w] flash disk for error', RL, EOM


msg_RL          db      EOM
msg_askformat   db      'Really want to format flash disk ? [y/N] '
LEN_ASKFMT      equ     this byte - msg_askformat
msg_getinfo     db      'Getting information of device', RL, EOM
msg_bytepersec  db      ' bytes per sector', EOM
msg_rootdir     db      ' dir entries in root', EOM
msg_totalsec    db      ' total sectors', EOM
msg_scan1       db      'Performing read test, pls wait...', EOM
msg_scan2       db      'Performing write test, pls wait...', EOM
msg_askscan2    db      'Write test may cause data lose, pls BACKUP !!!', RL
                db      'Proceed write test now ? [y/N] '
LEN_ASKSCAN2    equ     this byte - msg_askscan2
msg_scanok      db      RL, 'Flash memory test passed', EOM

em_nodev        db      'Device not found', EOM
em_abort        db      'User abort', EOM
em_read         db      'Error reading flash memory at '
em_write        db      'Error writing flash memory at '
em_del          db      'Error deleting flash memory at '

keylist_yn      db      'YN'
KEY_YN_LEN      equ     this byte - keylist_yn
KEY_Y           equ     'Y'
KEY_N           equ     'N'

SCAN_0          equ     '0'             ; scan method
SCAN_1          equ     '1'
SCAN_2          equ     '2'
scan_mode       db      SCAN_0

ctrl_break      db      0               ; Ctrl-Break/Ctrl-C pressed flag
custreserved    dw      0               ; Customer reserved block

;----------------------------------------------------------------------------
; Simple int 23h handler
;----------------------------------------------------------------------------
@new_23:
                mov     byte ptr cs:[ctrl_break], 1
                iret

;----------------------------------------------------------------------------
; Output(use video call) string to current position
; IN:
;   ES:DX: string to be showed
;   CX: length
; OUT:
; REG: NONE
;----------------------------------------------------------------------------
_vd_outstr      proc    near
                pusha
                mov     ah, VD_GETPAGE
                int     VIDEO               ; get the current page to BH
                mov     bp, dx
                mov     ah, VD_GETCURSOR    ; get cursor position
                push    cx
                int     VIDEO
                pop     cx
                mov     ah, VD_GETATTR      ; get text attr
                int     VIDEO
                mov     bl, ah
                mov     ax, VD_PRNSTR*256+01b
                                            ; bit1: use attr; bit0: mov cursor
                int     VIDEO               ; AX/BX/DX/ES:BP
                popa
                ret
_vd_outstr      endp


;----------------------------------------------------------------------------
; Print error msg of AL
; IN:
;   AL: error code
; OUT:
; REG: NONE
;----------------------------------------------------------------------------
_show_err       proc    near
                cmp     al, APE_NOERR
                jne     @se_0
                ret
@se_0:
                push    ax
                push    dx

                cmp     al, APE_READ
                jne     @se_1
                mov     dx, offset em_read
                jmp     @done_se1
@se_1:
                cmp     al, APE_WRITE
                jne     @se_2
                mov     dx, offset em_write
                jmp     @done_se1
@se_2:
                cmp     al, APE_ERASE
                jne     @se_3
                mov     dx, offset em_del
                jmp     @done_se1
@se_3:
                cmp     al, APE_NODEV
                jne     @se_4
                mov     dx, offset em_nodev
                jmp     @done_se
@se_4:
                cmp     al, APE_FORMAT
                jne     @se_5
                mov     dx, offset em_format
                jmp     @done_se
@se_5:
                cmp     al, APE_ABORT
                jne     @se_6
                mov     dx, offset em_abort
                jmp     @done_se
@se_6:
                cmp     al, APE_NOFLASH
                jne     @se_7
                mov     dx, offset em_noflash
                jmp     @done_se
@se_7:
                pop     dx
                pop     ax
                ret
@done_se:
                CALLDOS DOS_PRNMSG
                pop     dx
                pop     ax
                ret
@done_se1:
                CALLDOS DOS_PRNMSG
                mov     ax, [first_blk_no]
                call    _dos_outnum
                pop     dx
                pop     ax
                ret

_show_err       endp


;----------------------------------------------------------------------------
; Show a msg and accept a list of keys then return
; IN:
;   DX: msg to show
;   CX: msg len
;   SI: key list(upper case)
;   BX: key list len
;   AH: default key
; OUT:
;   AL: key
; REG:
;----------------------------------------------------------------------------
_ask            proc    near
                call    _vd_outstr
                mov     dl, ah
@getakey:
                mov     ah, KB_READKEY
                int     KEYB
                cmp     al, RETURN
                je      @defkey
                cmp     al, 'a'                 ; Upcase
                jb      @chkkeylist
                cmp     al, 'z'
                ja      @chkkeylist
                sub     al, 'a'-'A'
@chkkeylist:
                mov     cx, bx
                mov     di, si
                repne   scasb
                jne     @getakey
@done_ask:
                push    ax
                mov     ah, VD_GETPAGE
                int     VIDEO                   ; get the current page
                pop     ax
                push    ax
                mov     ah, VD_PRNCHAR          ; print the character
                int     VIDEO
                mov     ah, VD_PRNCHAR          ; print the character
                mov     al, RETURN
                int     VIDEO
                mov     ah, VD_PRNCHAR          ; print RL
                mov     al, LINEFEED
                int     VIDEO
                pop     ax
                ret
@defkey:
                mov     al, dl
                jmp     @done_ask
_ask            endp


;----------------------------------------------------------------------------
; Get number from ES:DI
; IN:
;   DS:SI: chars
;   CX: count
;   BX: default
; OUT:
;   AX: result
; REG: AX, CX, DX
;----------------------------------------------------------------------------
_getnum         proc    near
                jcxz    @getnumdef              ; none ?

                mov     dx, 0                   ; DX=N=0
                mov     ah, 0
@numloop:
                lodsb
                cmp     al, '0'                 ; Digit ?
                jb      @getnumdef
                cmp     al, '9'
                ja      @getnumdef
                push    ax                      ; Save current digit
                mov     ax, 10                  ; N*10->N
                mul     dx
                pop     dx                      ; Restore current digit
                sub     dx, '0'
                add     dx, ax                  ; N+N1->N
                loop    @numloop
                mov     ax, dx
                ret
@getnumdef:
                mov     ax, bx
                ret
_getnum         endp


;----------------------------------------------------------------------------
; Get device ptr
; IN:
; OUT:
;   AL=FALSE if no device
;   ES:BX=device head location if AL=TRUE
; REG: ALL
;----------------------------------------------------------------------------
_getdevptr      proc    near
                CALLDOS DOS_GETVER
                cld
                cmp     al, 2           ; 2.x + ?
                jb      @no_dev
                mov     dx, 22h         ; first device head addr ofs
                cmp     al, 4           ; 4.x + ?
                jae     @rfind_dev
                cmp     al, 3           ; 3.x ?
                mov     dx, 17h
                jne     @rfind_dev
                mov     dx, 22h
                cmp     ah, 0           ; 3.0 ?
                jne     @rfind_dev
                mov     dx, 28h
@rfind_dev:
                CALLDOS DOS_GETLOL
                add     bx, dx
@rfind_next:
                les     bx, es:[bx]
                mov     ax, es
                cmp     ax, -1          ; NULL ?
                jne     @isdevice
                cmp     bx, -1
                je      @no_dev
@isdevice:
                mov     cx, APP_NAME_LEN        ; Check me
                mov     di, bx
                lea     si, appname
                add     di, offset appname
                sub     di, offset header
                repe    cmpsb
                jne     @rfind_next
@isme:
                mov     al, TRUE
                ret
@no_dev:
                mov     al, FALSE
                ret
_getdevptr      endp


;----------------------------------------------------------------------------
; Toggle driver readonly/writable
; IN:
;   AL=DEV_READONLY -> readonly
;   otherwise writable
; OUT:
;   AL=APE_NOERR: success
;   otherwise AL=error code
; REG: ALL
;----------------------------------------------------------------------------
_do_toggle_wr   proc    near
                push    ax
                call    _getdevptr
                cmp     al, FALSE
                pop     ax
                je      @dtwr_err
                lea     di, header
                lea     si, devstatus
                sub     si, di
                add     bx, si
                mov     byte ptr es:[bx], al        ; Set status
                mov     dx, offset msg_readonly
                cmp     al, DEV_READONLY
                je      @dtwr_show_st
                mov     dx, offset msg_writable
@dtwr_show_st:
                CALLDOS DOS_PRNMSG
                mov     al, APE_NOERR
                ret
@dtwr_err:
                PRINTMSG    em_nodev
                mov     al, APE_NODEV
                ret
_do_toggle_wr   endp


;----------------------------------------------------------------------------
; Get/show device information
; IN:
; OUT:
;   AL=APE_NOERR: success
;   otherwise AL=error code
; REG: ALL
;----------------------------------------------------------------------------
_getdeviceinfo  proc    near
                call    _getdevptr
                cmp     al, FALSE
                je      @gdi_err
                PRINTMSG    msg_getinfo
                lea     di, header          ; ES:BX->device head
                mov     si, bx
                mov     ax, es
                mov     ds, ax              ; Exchange ES & DS
                mov     ax, cs
                mov     es, ax
                mov     cx, DEV_INFO_LEN
                rep     movsb               ; Copy information data
                mov     ds, ax              ; Restore DS
                mov     al, [disknum]
                mov     [msg_disknum], al
                mov     ax, [flash_kb]      ; Show size
                call    _dos_outnum
                PRINTMSG    msg_size1
                mov     ax, [freserved]
                call    _dos_outnum
                PRINTMSG    msg_size2
                PRINTMSG    msg_disk1       ; Show drive num

                mov     ax, [bytes_sector]  ; Print usable message
                call    _dos_outnum
                PRINTMSG    msg_bytepersec
                mov     ax, [root_dirs]
                call    _dos_outnum
                PRINTMSG    msg_rootdir
                mov     ax, [num_sec]
                call    _dos_outnum
                PRINTMSG    msg_totalsec

                mov     dx, offset msg_readonly
                cmp     byte ptr [devstatus], DEV_READONLY
                je      @gdi_show_st
                mov     dx, offset msg_writable
@gdi_show_st:
                CALLDOS DOS_PRNMSG
                PRINTMSG    msg_RL
                mov     al, APE_NOERR
                ret
@gdi_err:
                PRINTMSG    em_nodev
                mov     al, APE_NODEV
                ret
_getdeviceinfo  endp


;----------------------------------------------------------------------------
; Perform scan action
; IN:
; OUT:
;   AL=APE_NOERR: success
;   otherwise AL=error code
; REG: ALL
;----------------------------------------------------------------------------
_do_scan        proc    near
                cmp     byte ptr [scan_mode], SCAN_2    ; Scan mode 2 already ?
                je      @doscan2

                PRINTMSG    msg_scan1
                call    _do_scan1                       ; Call scan 1
                cmp     al, APE_NOERR
                jne     @scan_err
                cmp     byte ptr [scan_mode], SCAN_1    ; Only scan mode 1 ?
                je      @done_scan
                PRINTMSG    msg_RL
                mov     dx, offset msg_askscan2
                mov     cx, LEN_ASKSCAN2 
                mov     si, offset keylist_yn           ; Ask to confirm
                mov     bx, KEY_YN_LEN
                mov     ah, KEY_N
                call    _ask
                cmp     al, KEY_Y
                jne     @done_scan
@doscan2:
                PRINTMSG    msg_scan2                   ; Call scan 2
                call    _do_scan2
                cmp     al, APE_NOERR
                jne     @scan_err
@done_scan:
                PRINTMSG    msg_scanok
                mov     al, APE_NOERR
                ret
@scan_err:
;                call    _show_err       ; already show
                ret
_do_scan        endp


;----------------------------------------------------------------------------
; Show error if no flash installed
; IN:
; OUT:
;   AL=APE_NOFLASH: no flash
;   AL=APE_NOERR: flash detected
; REG: ALL
;----------------------------------------------------------------------------
_flash_exist    proc    near
                call    _getflashinfo       ; Get flash info
                cmp     al, 0
                je      @no_flash
                mov     al, APE_NOERR
                ret
@no_flash:
                PRINTERRMSG     em_noflash  ; No flash
                mov     al, APE_NOFLASH
                ret
_flash_exist    endp


;----------------------------------------------------------------------------
; .com file jumps here to start execution
;----------------------------------------------------------------------------
@com_start:
                DOSSETVEC   23h, @new_23

                xor     cx, cx
                mov     cl, cs:[80h]            ; Any params ?
                cmp     cl, 0
                je      @showusage

                mov     di, 81h
                mov     al, ' '
                repe    scasb                   ; Get switch
                mov     al, es:[di-1]
                cmp     al, 'F'                 ; Format switch
                je      @do_format
                cmp     al, 'S'                 ; Scan switch
                je      @do_scan
                cmp     al, 'R'                 ; Readonly
                je      @do_toggle_wr
                cmp     al, 'W'                 ; Writable
                je      @do_toggle_wr
                cmp     al, '?'                 ; Information
                je      @showinfo
                jmp     @showusage

@do_format:

                mov     al, ' '
                repe    scasb
                je      @do_format1
                dec     di
                mov     si, di
                inc     cx
                mov     bx, DEF_RESV_BLK        ; Get reserved block count
                call    _getnum
                mov     [custreserved], ax
@do_format1:
                mov     ax, 0
                call    _del16blk
                call    _flash_exist
                cmp     al, APE_NOFLASH
                je      @com_exit

                mov     ax, [custreserved]      ; Reserved blocks
                mov     [freserved], ax

                mov     dx, offset msg_askformat
                mov     cx, LEN_ASKFMT
                mov     si, offset keylist_yn   ; Ask to confirm
                mov     bx, KEY_YN_LEN
                mov     ah, KEY_N
                call    _ask
                cmp     al, KEY_Y
                mov     al, APE_ABORT
                jne     @com_exit
                call    _do_format
                jmp     @com_exit

@do_scan:
                cmp     cl, 0                   ; S1/S2 ?
                je      @do_scan2
                mov     al, [di]
                cmp     al, SCAN_1
                je      @do_scan1
                cmp     al, SCAN_2
                jne     @do_scan2
@do_scan1:
                mov     [scan_mode], al         ; Set scan mode
@do_scan2:
                call    _flash_exist
                cmp     al, APE_NOFLASH
                je      @com_exit
                call    _getdeviceinfo          ; Show device status
                call    _do_scan                ; Scan it
                jmp     @com_exit

@do_toggle_wr:
                cmp     al, 'R'
                mov     al, DEV_WRITE
                jne     @do_toggle_wr1
                mov     al, DEV_READONLY
@do_toggle_wr1:
                call    _do_toggle_wr           ; Toggle readonly switch
                jmp     @com_exit

@showinfo:
                PRINTMSG    information
                mov     al, 0
                jmp     @com_exit

@showusage:
                PRINTMSG    appname             ; Show copyright
                PRINTMSG    copyright
                PRINTMSG    usage               ; Show usage
                call    _flash_exist
                cmp     al, APE_NOFLASH
                je      @com_exit
                call    _getdeviceinfo

@com_exit:
                CALLDOS     DOS_EXIT            ; Keep retrun code and exit

else            ;_COMFILE


;============================================================================
ifdef           _DEVTEST
;----------------------------------------------------------------------------
; device test .com file jumps here to start execution
;----------------------------------------------------------------------------
@test_start:
                mov     ax, cs                  ; Send requst addr
                mov     es, ax
                lea     bx, myreq
                call    _strategy

                xor     cx, cx
                mov     cl, cs:[80h]            ; Any params ?
                cmp     cl, 0
                je      @test

                mov     di, 81h
                mov     al, ' '
                repe    scasb
                cmp     byte ptr es:[di-1], 'I'
                jne     @test

                call    _do_format
@test:
                mov     es:[bx].init_drv_num, 4 ; 'E'
                mov     es:[bx].command, DR0_INIT
                call    _interrupt              ; Test 0: initialization

                mov     es:[bx].command, DR1_MEDIACHK
                call    _interrupt              ; Test 1: media check

                mov     es:[bx].command, DR2_BUILDBPB
                call    _interrupt              ; Test 2: build bpb

                mov     es:[bx].command, DR4_INPUT
                lea     di, tmp_buf2            ; Simulate read sys area
                mov     ax, cs
                mov     es:[bx].io_trans_ofs, di
                mov     es:[bx].io_trans_seg, ax
                mov     es:[bx].io_sec_cnt, 1
                mov     ax, 0
                mov     bp, [sector_fat]
                add     bp, [root_sec]
                inc     bp

@again:
                call    _memsetbuf
                mov     es:[bx].io_start_sec, ax
                call    _interrupt
                inc     ax
                cmp     ax, bp
                jb      @again

                mov     al, 1
                call    _memsetbuf
                mov     es:[bx].command, DR4_INPUT  ; Simulate read root
                mov     ax, [sector_fat]
                inc     ax
                mov     es:[bx].io_start_sec, ax
                call    _interrupt

                lea     di, tmp_buf2
                inc     byte ptr es:[di+10]         ; Next name

                mov     es:[bx].command, DR8_OUTPUT
                mov     ax, [sector_fat]
                inc     ax
                mov     es:[bx].io_start_sec, ax
                mov     es:[bx].io_sec_cnt, 1
                call    _interrupt

                mov     es:[bx].command, DR4_INPUT ; Simulate read root again
                mov     ax, [sector_fat]
                inc     ax
                mov     es:[bx].io_start_sec, ax
                mov     es:[bx].io_sec_cnt, 1
                call    _interrupt

                mov     ax, es:[bx].status
                CALLDOS     DOS_EXIT            ; Keep retrun code and exit

endif           ;_DEVTEST
endif           ;_COMFILE



; Note that tmp_buf2 only contain 1 byte(to save app size),
; but here I use to hold 1 block data when initialize
ifndef          _NEEDBUF
tmp_buf2        db      0
else            ;!_NEEDBUF
tmp_buf2        db      TMP_BUF2_SIZE dup (?)
endif           ;!_NEEDBUF

ifdef           _COMFILE
tmp_buf         db      0

information     db      'Just a short note: '
                db      'This is a FLASH memory disk driver for DOS,', RL
                db      'it is original written to support our PDA', RL
                db      'Q: Who are we ?', RL
                db      'A: Shenzhen G&S Co. Ltd., ', RL
                db      'Q: Who wrote this ?', RL
                db      'A: Edward G.(nbuyer@gmail.com), May 1998'
                db      EOM

endif           ;_COMFILE

@end_of_code    =       $


; Code end
;============================================================================
code            ends
                end start
;****************************************************************************;

