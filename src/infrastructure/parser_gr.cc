/*
 * parser_gr.cc — DIMACS graph parser
 *
 * This is Goldberg's original parser_gr.cc, modified only to include
 * our nodearc.h (Goldberg-compatible structs + CSR conversion). The parsing logic is identical.
 *
 * Original author: Andrew Goldberg (9th DIMACS Challenge)
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "nodearc.h"

int parse_gr( long *n_ad, long *m_ad, Node **nodes_ad, Arc **arcs_ad,
           long *node_min_ad, char *gName )
{

#define MAXLINE       100
#define ARC_FIELDS      3
#define P_FIELDS        3
#define PROBLEM_TYPE "sp"
#define DEFAULT_NAME "unknown"

long    n,
        node_min=1,
        node_max=0,
       *arc_first=NULL,
       *arc_tail=NULL,
        head, tail, i;

long    m,
        last, arc_num, arc_new_num;

Node    *nodes=NULL;
Arc     *arcs=NULL,
        *arc_current=NULL,
        *arc_new;

long long length=0;

long    no_lines=0,
        no_plines=0,
        no_alines=0;

char    in_line[MAXLINE],
        pr_type[3];

 FILE *gFile;
int        err_no;

#define EN1   0
#define EN2   1
#define EN3   2
#define EN4   3
#define EN6   4
#define EN10  5
#define EN7   6
#define EN8   7
#define EN9   8
#define EN11  9
#define EN12 10
#define EN13 11
#define EN14 12
#define EN16 13
#define EN15 14
#define EN17 15
#define EN18 16
#define EN21 17
#define EN19 18
#define EN20 19
#define EN22 20

static const char *err_message[] =
  {
/* 0*/    "more than one problem line.",
/* 1*/    "wrong number of parameters in the problem line.",
/* 2*/    "it is not a Shortest Path problem line.",
/* 3*/    "bad value of a parameter in the problem line.",
/* 4*/    "can't obtain enough memory to solve this problem.",
/* 5*/    "more than one line with the problem name.",
/* 6*/    "can't read problem name.",
/* 7*/    "problem description must preceed source/sink description.",
/* 8*/    "this parser doesn't support multiple sources/sinks.",
/* 9*/    "wrong number of parameters in the source/sink line.",
/*10*/    "wrong value of parameters in the source/sink line.",
/*11*/    "this parser doesn't support destination description.",
/*12*/    "source/sink description must be before arc descriptions.",
/*13*/    "too many arcs in the input.",
/*14*/    "wrong number of parameters in the arc line.",
/*15*/    "wrong value of parameters in the arc line.",
/*16*/    "unknown line type in the input.",
/*17*/    "reading error.",
/*18*/    "not enough arcs in the input.",
/*20*/    "can't read anything from the input file."
  };

 gFile = fopen(gName, "r");
 if (gFile == NULL) {
   fprintf(stderr, "ERROR: file %s not found\n", gName);
   exit(1);
 }

while (fgets(in_line, MAXLINE, gFile) != NULL)
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
                   { err_no = EN1 ; goto error; }

                no_plines = 1;

                if (
                    sscanf ( in_line, "%*c %2s %ld %ld", pr_type, &n, &m )
                != P_FIELDS
                   )
                    { err_no = EN2; goto error; }

                if ( strcmp ( pr_type, PROBLEM_TYPE ) )
                    { err_no = EN3; goto error; }

                if ( n <= 0  || m <= 0 )
                    { err_no = EN4; goto error; }

                nodes    = (Node*) calloc ( n+2, sizeof(Node) );
                arcs     = (Arc*)  calloc ( m+1, sizeof(Arc) );
                arc_tail = (long*) calloc ( m,   sizeof(long) );
                arc_first= (long*) calloc ( n+2, sizeof(long) );

                if ( nodes == NULL || arcs == NULL ||
                     arc_first == NULL || arc_tail == NULL )
                    {
                      printf("Need %lld bytes for data and %lld bytes temp. data\n",
                             ((long long) (n+2))*((long long) sizeof(Node))+
                             ((long long) (m+1))*((long long) sizeof(Arc)),
                             ((long long) (n+m+2))*((long long) sizeof(long)));
                      err_no = EN6; goto error;
                    }

                arc_current = arcs;
                break;

      case 'a':

                if ( no_alines >= m )
                  { err_no = EN16; goto error; }

                if (
                    sscanf ( in_line,"%*c %ld %ld %lld",
                                      &tail, &head, &length )
                    != 3
                   )
                    { err_no = EN15; goto error; }
                if ( tail < 0  ||  tail > n  ||
                     head < 0  ||  head > n
                   )
                    { err_no = EN17; goto error; }

                arc_first[tail + 1] ++;

                arc_tail[no_alines] = tail;
                arc_current -> head = nodes + head;
                arc_current -> len  = length;

                if ( head < node_min ) node_min = head;
                if ( tail < node_min ) node_min = tail;
                if ( head > node_max ) node_max = head;
                if ( tail > node_max ) node_max = tail;

                no_alines ++;
                arc_current ++;
                break;

        default:
                err_no = EN18; goto error;
                break;

    }
}

if ( feof (gFile) == 0 )
  { err_no=EN21; goto error; }

if ( no_lines == 0 )
  { err_no = EN22; goto error; }

if ( no_alines < m )
  { err_no = EN19; goto error; }


/********** ordering arcs - linear time algorithm ***********/

( nodes + node_min ) -> first = arcs;

for ( i = node_min + 1; i <= node_max + 1; i ++ )
  {
    arc_first[i]          += arc_first[i-1];
    ( nodes + i ) -> first = arcs + arc_first[i];
  }


for ( i = node_min; i < node_max; i ++ )
  {

    last = ( ( nodes + i + 1 ) -> first ) - arcs;

    for ( arc_num = arc_first[i]; arc_num < last; arc_num ++ )
      { tail = arc_tail[arc_num];

        while ( tail != i )
          { Arc arc_tmp;
            arc_new_num  = arc_first[tail];
            arc_current  = arcs + arc_num;
            arc_new      = arcs + arc_new_num;

            arc_tmp.head         = arc_new -> head;
            arc_new -> head      = arc_current -> head;
            arc_current -> head = arc_tmp.head;

            arc_tmp.len         = arc_new -> len;
            arc_new -> len      = arc_current -> len;
            arc_current -> len = arc_tmp.len;

            arc_tail[arc_num] = arc_tail[arc_new_num];

            arc_tail[arc_new_num] = tail;
            arc_first[tail] ++ ;

            tail = arc_tail[arc_num];
          }
      }
  }

*m_ad = m;
*n_ad = node_max - node_min + 1;
*node_min_ad = node_min;
*nodes_ad = nodes + node_min;
*arcs_ad = arcs;

free ( arc_first ); free ( arc_tail );

 fclose(gFile);

return (0);

 error:

printf ( "\nPrs%d: line %ld of input - %s\n",
         err_no, no_lines, err_message[err_no] );

exit (1);

}
