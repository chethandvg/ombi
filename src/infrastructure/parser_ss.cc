/*
 * parser_ss.cc — DIMACS single-source auxiliary file parser
 *
 * This is Goldberg's original parser_ss.cc, unmodified.
 * It does not depend on nodearc.h.
 *
 * Original author: Andrew Goldberg (9th DIMACS Challenge)
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

int parse_ss(long *sN_ad, long **source_array, char *aName)
{

#define MAXLINE       100
#define P_FIELDS        4
#define AUX_TYPE "aux"
#define PROBLEM_TYPE "sp"
#define PROBLEM_VAR "ss"

  long    n;
  long    k;
  long   *sources=NULL;
  long source;
  char prA_type[4], pr_type[3], pr_var[3], in_line[MAXLINE];
  long no_lines= 0, no_plines=0, no_slines=0;
  FILE *aFile;

 aFile = fopen(aName, "r");
 if (aFile == NULL) {
   fprintf(stderr, "ERROR: file %s not found\n", aName);
   exit(1);
 }

while (fgets(in_line, MAXLINE, aFile) != NULL)
  {
  no_lines ++;

  switch (in_line[0])
    {
    case 'c':
    case '\n':
    case '\0':
      break;

    case 'p':
      if ( no_plines > 0 )
        { goto error; }

      no_plines = 1;

      if (
          sscanf( in_line, "%*c %s %s %s %ld",
                  prA_type, pr_type, pr_var, &n )
          != P_FIELDS
          )
        {goto error; }

      if ( strcmp ( prA_type, AUX_TYPE ) )
        {goto error; }

      if ( strcmp ( pr_type, PROBLEM_TYPE ) )
        {goto error; }

      if ( strcmp ( pr_var, PROBLEM_VAR ) )
        {goto error; }

      sources  = (long *) calloc(n+1, sizeof(long));

      break;
    case 's':
      no_slines++;
      if ( no_plines == 0 )
        { goto error; }

      k = sscanf ( in_line,"%*c %ld", &source );

      if ( k < 1 )
        { goto error; }

      sources[no_slines-1] = source;

      break;
    default:
      goto error;
      break;

    }
}

if ( feof (aFile) == 0 )
  { goto error; }

if ( no_lines == 0 )
  { goto error; }

 *sN_ad = n;
 *source_array = sources;

 fclose(aFile);

 return (0);

 error:

 fprintf ( stderr, "Error parsing auxiliary file: line %ld: %s\n",
           no_lines, in_line);

exit (1);

}
