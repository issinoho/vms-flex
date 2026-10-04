$! VMS_INSTALLCHECK.COM <tree-dir-name> <m4-tree-dir-name> - install the FLEX
$! kit (and the M4 kit it requires, from the node's vms-m4 tree, if M4 is not
$! installed), verify it, generate, link and run a scanner with it, then remove
$! what it installed.  Changes the system while it runs (PCSI database,
$! SYS$COMMON:[FLEX] and [M4], FLEX$ROOT, M4$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ here = f$environment("DEFAULT")
$ tree = here - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ m4kitdir = here - "]" + "." + p2 + ".KIT_''arch']"
$ m4_installed_here = 0
$ if f$trnlnm("M4$ROOT") .eqs. ""
$ then
$   write sys$output "=== INSTALL M4 (prerequisite) from ", m4kitdir
$   product install M4 /producer=ISSINOHO /base_system='base' /source='m4kitdir' /options=noconfirm /log
$   write sys$output "=== M4 install status ", $status
$   m4_installed_here = 1
$ endif
$ write sys$output "=== INSTALL from ", kitdir
$ product install FLEX /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product FLEX /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:FLEX$STARTUP.COM"), "]"
$ show logical FLEX$ROOT
$ write sys$output "libfl: [", f$search("FLEX$ROOT:[LIB]LIBFL.OLB"), "]"
$ write sys$output "libfl as_is: [", f$search("FLEX$ROOT:[LIB]LIBFL_AS_IS.OLB"), "]"
$ write sys$output "header: [", f$search("FLEX$ROOT:[INCLUDE]FLEXLEXER.H"), "]"
$ write sys$output "=== FLEX FROM THE INSTALLED KIT"
$ @FLEX$ROOT:[000000]FLEX$SETUP.COM
$ if f$search("FIC.DIR") .eqs. "" then create/directory [.FIC]
$ set default [.FIC]
$ define/user sys$output out.txt
$ flex --version
$ search/nooutput out.txt "flex 2"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "FLEX_VERSION: PASS"
$ if sev .ne. 1 then write sys$output "FLEX_VERSION: FAIL"
$ copy/nolog FLEX$ROOT:[DOC]WC.L []
$ flex -o wc.c wc.l
$ sev = $severity
$ if sev .eq. 1 .and. f$search("wc.c") .nes. "" then write sys$output "FLEX_GENERATE: PASS"
$ if sev .ne. 1 .or. f$search("wc.c") .eqs. "" then write sys$output "FLEX_GENERATE: FAIL"
$ create data.txt
hello world
flex on vms
$ cc/nolist wc.c
$ link/nomap wc, FLEX$ROOT:[LIB]LIBFL/library
$ define/user sys$input data.txt
$ define/user sys$output out.txt
$ run wc
$ type out.txt
$ search/nooutput/exact out.txt "2 5 24"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "FLEX_SCANNER_RUNS: PASS"
$ if sev .ne. 1 then write sys$output "FLEX_SCANNER_RUNS: FAIL"
$ cc/nolist/names=(as_is,shortened)/object=wca.obj wc.c
$ link/nomap/executable=wca.exe wca.obj, FLEX$ROOT:[LIB]LIBFL_AS_IS/library
$ define/user sys$input data.txt
$ define/user sys$output out.txt
$ run wca
$ search/nooutput/exact out.txt "2 5 24"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "FLEX_AS_IS_RUNS: PASS"
$ if sev .ne. 1 then write sys$output "FLEX_AS_IS_RUNS: FAIL"
$! A failed run has error severity under DCL (capture $STATUS once: any
$! assignment resets $STATUS and $SEVERITY)
$ define/user sys$error nla0:
$ flex nonexistent.l
$ st = $status
$ sev = st .and. 7
$ write sys$output "failed run status ", st, " severity ", sev
$ if sev .eq. 2 .or. sev .eq. 4 then write sys$output "FLEX_ERROR_SEVERITY: PASS"
$ if sev .ne. 2 .and. sev .ne. 4 then write sys$output "FLEX_ERROR_SEVERITY: FAIL"
$ if f$search("CXX_REPOSITORY.DIR") .nes. ""
$ then
$   if f$search("[.CXX_REPOSITORY]*.*") .nes. "" then -
        delete/nolog [.CXX_REPOSITORY]*.*;*
$   set file/protection=o:rwed CXX_REPOSITORY.DIR
$ endif
$ delete/nolog *.*;*
$ set default [-]
$ set file/protection=o:rwed FIC.DIR
$ delete/nolog FIC.DIR;
$ delete/symbol/global flex
$ write sys$output "=== REMOVE"
$ product remove FLEX /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "FLEX$ROOT after removal: [", f$trnlnm("FLEX$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[FLEX...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:FLEX$STARTUP.COM"), "]"
$ if m4_installed_here
$ then
$   product remove M4 /producer=ISSINOHO /options=noconfirm /log
$   write sys$output "M4$ROOT after removal: [", f$trnlnm("M4$ROOT"), "]"
$ endif
$ product show product FLEX /producer=ISSINOHO
