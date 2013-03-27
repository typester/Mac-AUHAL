#import <Foundation/Foundation.h>
#import <AudioUnit/AudioUnit.h>
#undef Move /* This macro defined at Quartz conflicts with perl */

#define PERL_NO_GET_CONTEXT /* we want efficiency */
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#define NEED_newSVpvn_flags
#include "ppport.h"

typedef AudioComponentInstance* Mac__AUHAL;

MODULE = Mac::AUHAL  PACKAGE = Mac::AUHAL

PROTOTYPES: DISABLE

Mac::AUHAL
new(SV* class)
CODE:
{
    AudioComponent comp;
    AudioComponentDescription desc;
    AudioComponentInstance* au;

    PERL_UNUSED_VAR(class);

    desc.componentType         = kAudioUnitType_Output;
    desc.componentSubType      = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = desc.componentFlagsMask = 0;

    comp = AudioComponentFindNext(NULL, &desc);
    if (comp == NULL) {
        croak("audio component not found");
    }

    Newx(au, 1, AudioComponentInstance);
    AudioComponentInstanceNew(comp, au);
    RETVAL = au;
}
OUTPUT:
    RETVAL

void
DESTROY(Mac::AUHAL au)
CODE:
{
    AudioComponentInstanceDispose(*au);
    Safefree(au);
}

void
_set_format(Mac::AUHAL au, double sample_rate, U32 channels, U32 bits, bool is_float, bool is_signed_integer)
CODE:
{
    AudioStreamBasicDescription desc;
    UInt32 size = sizeof(AudioStreamBasicDescription);
    OSStatus status;

    desc.mSampleRate = sample_rate;
    desc.mFormatID = kAudioFormatLinearPCM;

    desc.mFormatFlags = kAudioFormatFlagIsPacked;
    if (is_float)
        desc.mFormatFlags |= kAudioFormatFlagIsFloat;
    if (is_signed_integer)
        desc.mFormatFlags |= kAudioFormatFlagIsSignedInteger;

    desc.mChannelsPerFrame = channels;
    desc.mBitsPerChannel = bits;

    desc.mFramesPerPacket = 1;
    desc.mBytesPerFrame   = bits/8 * channels;
    desc.mBytesPerPacket  = desc.mBytesPerFrame * desc.mFramesPerPacket;
    desc.mReserved = 0;

    status = AudioUnitSetProperty(*au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &desc, size);

    if (status) {
        croak("failed to set_format: %c%c%c%c, %d",
            status >> 3 & 0xf,
            status >> 2 & 0xf,
            status >> 1 & 0xf,
            status & 0xf,
            status);
    }

    status = AudioUnitSetProperty(*au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &desc, size);
    if (status) {
        croak("failed to set_format: %c%c%c%c, %d",
            status >> 3 & 0xf,
            status >> 2 & 0xf,
            status >> 1 & 0xf,
            status & 0xf,
            status);
    }
}


