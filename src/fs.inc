; fs.inc — filesystem node layout + error codes (shared)

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

def FS_VERSION   equ 4
