/* wc.l - a small word counter for the OpenVMS smoke test.  It uses
   yywrap() from libfl (no %option noyywrap).  */
%{
#include <stdio.h>
int chars = 0, words = 0, lines = 0;
%}
%%
[a-zA-Z]+  { words++; chars += yyleng; }
\n         { chars++; lines++; }
.          { chars++; }
%%
int
main (void)
{
  yylex ();
  printf ("%d %d %d\n", lines, words, chars);
  return 0;
}
