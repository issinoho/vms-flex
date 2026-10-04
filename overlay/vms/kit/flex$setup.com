$! FLEX$SETUP.COM - define the flex command for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @FLEX$ROOT:[000000]FLEX$SETUP.COM
$!
$! Upper-case options (-B, -Cf, -F, -I, -L, -P, -S, -T, -V, ...) need
$! SET PROCESS/PARSE_STYLE=EXTENDED, or double quotes, because traditional
$! DCL parsing changes their case; batch jobs use the traditional style.
$!
$ if f$trnlnm("FLEX$ROOT") .eqs. ""
$ then
$   write sys$error "FLEX$SETUP: FLEX$ROOT is not defined; run FLEX$STARTUP.COM first"
$   exit 44
$ endif
$ flex :== $FLEX$ROOT:[BIN]FLEX.EXE
$ exit 1
