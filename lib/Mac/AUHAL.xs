#import <Foundation/Foundation.h>
#import <AudioUnit/AudioUnit.h>
#undef Move /* This macro defined at Quartz conflicts with perl */

#define PERL_NO_GET_CONTEXT /* we want efficiency */
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#define NEED_newSVpvn_flags
#include "ppport.h"

MODULE = Mac::AUHAL  PACKAGE = Mac::AUHAL

PROTOTYPES: DISABLE

void
hello()
CODE:
{
    ST(0) = newSVpvs_flags("Hello, world!", SVs_TEMP);
}
