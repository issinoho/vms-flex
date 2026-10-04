$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the M4 kit, verify it, run
$! m4 from it, then remove it.  Changes the system while it runs (PCSI
$! database, SYS$COMMON:[M4], system logical M4$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ here = f$environment("DEFAULT")
$ tree = here - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install M4 /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product M4 /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:M4$STARTUP.COM"), "]"
$ show logical M4$ROOT
$ directory/nohead/notrail M4$ROOT:[000000...]*.*
$ write sys$output "=== M4 FROM THE INSTALLED KIT"
$ @M4$ROOT:[000000]M4$SETUP.COM
$ set process/parse_style=extended
$ if f$search("M4IC.DIR") .eqs. "" then create/directory [.M4IC]
$ set default [.M4IC]
$ define/user sys$output out.txt
$ m4 --version
$ search/nooutput out.txt "GNU M4"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "M4_VERSION: PASS"
$ if sev .ne. 1 then write sys$output "M4_VERSION: FAIL"
$ create in.m4
define(`node', `esyscmd(`write sys$output f$getsyi("NODENAME")')')dnl
define(`sq', `eval($1 * $1)')dnl
sq(12) on node
$ define/user sys$output out.txt
$ m4 in.m4
$ type out.txt
$ search/nooutput out.txt "144 on"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "M4_EXPAND: PASS"
$ if sev .ne. 1 then write sys$output "M4_EXPAND: FAIL"
$ nn = f$getsyi("NODENAME")
$ search/nooutput out.txt "144 on ''nn'"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "M4_ESYSCMD: PASS"
$ if sev .ne. 1 then write sys$output "M4_ESYSCMD: FAIL"
$ delete/nolog *.*;*
$ set default [-]
$ set file/protection=o:rwed M4IC.DIR
$ delete/nolog M4IC.DIR;
$! A failed run has error severity under DCL (capture $STATUS once: any
$! assignment resets $STATUS and $SEVERITY)
$ define/user sys$error nla0:
$ m4 nonexistent.m4
$ st = $status
$ sev = st .and. 7
$ write sys$output "failed run status ", st, " severity ", sev
$ if sev .eq. 2 .or. sev .eq. 4 then write sys$output "M4_ERROR_SEVERITY: PASS"
$ if sev .ne. 2 .and. sev .ne. 4 then write sys$output "M4_ERROR_SEVERITY: FAIL"
$ delete/symbol/global m4
$ write sys$output "=== REMOVE"
$ product remove M4 /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "M4$ROOT after removal: [", f$trnlnm("M4$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[M4...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:M4$STARTUP.COM"), "]"
$ product show product M4 /producer=ISSINOHO
