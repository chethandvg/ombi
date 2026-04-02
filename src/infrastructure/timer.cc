/*
 * timer.cc — User-time measurement using getrusage
 *
 * This is Goldberg's original timer.cc, unmodified.
 * Returns user CPU time in seconds (double precision).
 *
 * Original author: Andrew Goldberg (9th DIMACS Challenge)
 */

#include <sys/time.h>
#include <sys/resource.h>
#include <unistd.h>

double timer()
{
    struct rusage r;
    getrusage(0, &r);
    return (double)(r.ru_utime.tv_sec +
                    r.ru_utime.tv_usec / (double)1000000);
}
