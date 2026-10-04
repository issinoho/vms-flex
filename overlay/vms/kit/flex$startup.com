$! FLEX$STARTUP.COM - system startup for flex on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! FLEX$ROOT, pointing at the installed [FLEX] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:FLEX$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign FLEX$ROOT instead (PCSI runs it so at removal).
$!
$! Users then define the flex command with
$!     $ @FLEX$ROOT:[000000]FLEX$SETUP.COM
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("FLEX$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode FLEX$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[FLEX].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.FLEX.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "FLEX.]"
$ if root .eqs. dir + "FLEX.]"
$ then
$   write sys$error "FLEX$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed FLEX$ROOT 'dev''root'
$ if f$search("FLEX$ROOT:[BIN]FLEX.EXE") .eqs. ""
$ then
$   write sys$error "FLEX$STARTUP: FLEX.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for flex"
$ say ""
$ say "    At system startup: to define FLEX$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:FLEX$STARTUP.COM"
$ say "    For each user: to define the flex command, add this line to LOGIN.COM:"
$ say "    $ @FLEX$ROOT:[000000]FLEX$SETUP.COM"
$ say ""
$ say "    PRODUCT REMOVE FLEX removes the product and deassigns FLEX$ROOT."
$ say ""
$ exit 1
