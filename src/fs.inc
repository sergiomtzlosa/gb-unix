; fs.inc — filesystem node/SRAM layout + error codes (shared)

def N_TYPE       equ 0
def N_PARENT     equ 12
def N_CHILD      equ 13
def N_SIBLING    equ 14
def N_ATTRS      equ 15
def N_DATA       equ 16
def N_SIZE       equ 18

def N_FILE       equ 1
def N_DIR        equ 2

; error codes
def FS_E_NOENT   equ 1
def FS_E_NOTDIR  equ 2
def FS_E_ISDIR   equ 3
def FS_E_NOTEMPTY equ 4
def FS_E_EXISTS  equ 5
def FS_E_FULL    equ 6
def FS_E_NAMETOOLONG equ 7
def FS_E_EPERM   equ 8
def FS_E_TOOBIG  equ 9

; SRAM filesystem layout (shared by sram.asm, fs.asm, and top.asm)
def SRAM_MAGIC    equ $A000
def SRAM_VER      equ $A004
def SRAM_HEAP_PTR equ $A006
def SRAM_NODES    equ $A010
def NODE_SIZE     equ 20
def NODE_COUNT    equ 96
def NODE_HEAP     equ $A010 + NODE_COUNT * NODE_SIZE ; $A790
def HEAP_END      equ $BFF0

def FS_VERSION   equ 5
