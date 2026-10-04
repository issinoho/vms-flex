/* regex.h - POSIX regular expressions for flex on OpenVMS.

   The VSI C run-time library has no <regex.h>.  flex's two patterns (its
   #line directive and a blank line, in src/regex.c) use PCRE2's POSIX
   layer instead: pcre2posix.h maps regcomp, regexec, regerror and regfree
   to the pcre2_ functions in PCRE2-POSIX.OLB (github.com/issinoho/vms-pcre2,
   PCRE2$ROOT), which flex links statically.

   Part of the OpenVMS port of flex (github.com/issinoho/vms-flex);
   distributed under the same terms as flex.  */

#ifndef VMS_REGEX_H
#define VMS_REGEX_H
#include <pcre2posix.h>
#endif
