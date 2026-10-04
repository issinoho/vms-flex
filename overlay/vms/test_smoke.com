$! TEST_SMOKE.COM - smoke test for the built flex ([.BIN_<arch>]FLEX.EXE)
$!
$! Usage:  @[.VMS]TEST_SMOKE [m4-image]
$! P1: the GNU m4 image flex runs (default M4$ROOT:[BIN]M4.EXE, the M4
$!     kit); tools/test.sh passes the node's vms-m4 build.
$!
$ set noon
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ flex = "$" + f$parse("[.BIN_''arch']FLEX.EXE")
$ libfl = f$parse("[.OBJ_''arch']LIBFL.OLB")
$ libfl_as_is = f$parse("[.OBJ_''arch']LIBFL_AS_IS.OLB")
$ if p1 .nes. "" then define/process M4 'p1'
$ pass = 0
$ fail = 0
$ if f$search("SMOKE.DIR") .eqs. "" then create/directory [.SMOKE]
$ copy/nolog [.VMS]WC.L [.SMOKE]
$ set default [.SMOKE]
$ set process/parse_style=extended
$ pid = f$getjpi("", "PID")
$!
$! 1. version
$ define/user sys$output out.txt
$ flex --version
$ search/nooutput out.txt "flex 2.6"
$ sev = $severity
$ name = "version"
$ gosub check_success
$!
$! 2. generate a scanner (flex runs m4 and its filters)
$ flex -o wc.c --header-file=wc.h wc.l
$ sev = $severity
$ if sev .eq. 1 .and. f$search("wc.c") .eqs. "" then sev = 2
$ name = "generate wc.c from wc.l (runs m4)"
$ gosub check_success
$ search/nooutput wc.c "yylex"
$ sev = $severity
$ name = "wc.c contains yylex"
$ gosub check_success
$ search/nooutput wc.h "yylex"
$ sev = $severity
$ name = "--header-file writes wc.h"
$ gosub check_success
$ search/nooutput wc.c "#line","""wc.c"""/match=and
$ sev = $severity
$ name = "#line directives name wc.c (fix_linedirs ran)"
$ gosub check_success
$!
$! 3. the scanner compiles, links with LIBFL (yywrap) and counts
$ cc/nolist/object=wc.obj wc.c
$ link/nomap/executable=wc.exe wc.obj, 'libfl'/library
$ create data.txt
hello world
flex on vms
$ define/user sys$input data.txt
$ define/user sys$output out.txt
$ run wc.exe
$ search/nooutput/exact out.txt "2 5 24"
$ sev = $severity
$ name = "scanner compiles, links with LIBFL.OLB and counts 2 5 24"
$ gosub check_success
$ cc/nolist/names=(as_is,shortened)/object=wca.obj wc.c
$ link/nomap/executable=wca.exe wca.obj, 'libfl_as_is'/library
$ define/user sys$input data.txt
$ define/user sys$output out.txt
$ run wca.exe
$ search/nooutput/exact out.txt "2 5 24"
$ sev = $severity
$ name = "compiled /NAMES=AS_IS, links with LIBFL_AS_IS.OLB and counts 2 5 24"
$ gosub check_success
$!
$! 4. -t writes the scanner to standard output
$ define/user sys$output out.txt
$ flex -t wc.l
$ search/nooutput out.txt "yylex"
$ sev = $severity
$ name = "-t writes the scanner to stdout"
$ gosub check_success
$!
$! 5. errors give an error status
$ create bad.l
%%
"unterminated
$ define/user sys$error nla0:
$ flex -o bad.c bad.l
$ sev = $severity
$ name = "scanner syntax error gives an error status"
$ gosub check_failure
$ define/process M4 "SYS$SCRATCH:NO_SUCH_M4.EXE"
$ define/user sys$error nla0:
$ flex -o wc2.c wc.l
$ sev = $severity
$ if p1 .nes. "" then define/process M4 'p1'
$ if p1 .eqs. "" then deassign/process M4
$ name = "missing m4 gives an error status"
$ gosub check_failure
$!
$! 6. no temporary files left behind
$ sev = 1
$ if f$search("SYS$SCRATCH:FLEX_''pid'_*.TMP") .nes. "" then sev = 2
$ name = "no temporary files left in SYS$SCRATCH"
$ gosub check_success
$!
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed"
$! The compiler leaves a [.CXX_REPOSITORY] (read-only) behind.
$ if f$search("CXX_REPOSITORY.DIR") .nes. ""
$ then
$   if f$search("[.CXX_REPOSITORY]*.*") .nes. "" then -
        delete/nolog [.CXX_REPOSITORY]*.*;*
$   set file/protection=o:rwed CXX_REPOSITORY.DIR
$ endif
$ delete/nolog *.*;*
$ set default [-]
$ set file/protection=o:rwed SMOKE.DIR
$ delete/nolog SMOKE.DIR;
$ if f$trnlnm("M4", "LNM$PROCESS") .nes. "" then deassign/process M4
$ set default 'saved_default'
$ if fail .eq. 0 then exit 1
$ exit 44
$!
$! The callers save $SEVERITY in sev straight after the command: any
$! assignment (name = ...) resets it.
$check_success:
$ if sev .eq. 1
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ")"
$   if f$search("out.txt") .nes. ""
$   then
$     write sys$output "   output was:"
$     type out.txt;0
$   endif
$ endif
$ return
$!
$check_failure:
$ if sev .eq. 2 .or. sev .eq. 4
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ", expected an error)"
$ endif
$ return
