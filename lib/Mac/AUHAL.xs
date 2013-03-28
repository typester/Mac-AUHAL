#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioUnit/AudioUnit.h>
#undef Move /* This macro defined at Quartz conflicts with perl */

#define PERL_NO_GET_CONTEXT /* we want efficiency */
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#define NEED_newSVpvn_flags
#include "ppport.h"

typedef struct Mac__AUHAL_s Mac__AUHAL_t;
typedef Mac__AUHAL_t* Mac__AUHAL;

struct Mac__AUHAL_s {
    AudioUnit outputUnit;
    SV* render_cb;
    AudioUnit inputUnit;
    SV* input_cb;
};

static OSStatus render_callback(
   void                        *inRefCon,
   AudioUnitRenderActionFlags  *ioActionFlags,
   const AudioTimeStamp        *inTimeStamp,
   UInt32                      inBusNumber,
   UInt32                      inNumberFrames,
   AudioBufferList             *ioData
) {
    Mac__AUHAL self = (Mac__AUHAL)inRefCon;
    SV* data    = sv_2mortal(newSV(0));
    SV* dataref = sv_2mortal(newRV_inc(data));
    STRLEN len;
    char* bytes;

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSViv(inNumberFrames)));
    XPUSHs(dataref);
    PUTBACK;

    call_sv(self->render_cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    AudioBuffer b = ioData->mBuffers[0];
    if (!SvPOK(SvRV(dataref))) {
        memset(b.mData, 0, b.mDataByteSize);
    }
    else {
        bytes = SvPV(SvRV(dataref), len);

        if (len) {
            memcpy(b.mData, bytes, len <= b.mDataByteSize ? len : b.mDataByteSize);
        }
        if (len < b.mDataByteSize) {
            memset(b.mData + len, 0, b.mDataByteSize - len);
        }
    }

    return 0;
}

static OSStatus input_callback(
   void                        *inRefCon,
   AudioUnitRenderActionFlags  *ioActionFlags,
   const AudioTimeStamp        *inTimeStamp,
   UInt32                      inBusNumber,
   UInt32                      inNumberFrames,
   AudioBufferList             *ioData
) {
    fprintf(stderr, "in\n");

    return 0;
}

static void set_format(Mac__AUHAL self, double sample_rate, U32 channels, U32 bits, bool is_float, bool is_signed_integer) {
    OSStatus status;
    AudioStreamBasicDescription asbd;
    UInt32 size;

    asbd.mSampleRate       = sample_rate;
    asbd.mFormatID         = kAudioFormatLinearPCM;
    asbd.mFormatFlags      = kAudioFormatFlagIsPacked;
    if (is_float) {
        asbd.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsFloat;
    }
    else if (is_signed_integer) {
        asbd.mFormatFlags = kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    }
    asbd.mChannelsPerFrame = channels;
    asbd.mBitsPerChannel   = bits;

    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame   = asbd.mBitsPerChannel/8 * asbd.mChannelsPerFrame;
    asbd.mBytesPerPacket  = asbd.mBytesPerFrame * asbd.mFramesPerPacket;

    size = sizeof(AudioStreamBasicDescription);
    status = AudioUnitSetProperty(
        self->outputUnit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input,
        0,
        &asbd,
        size
    );
    if (status) {
        croak("failed to set output format: %d", status);
    }

    size = sizeof(AudioStreamBasicDescription);
    status = AudioUnitSetProperty(
        self->inputUnit,
        kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output,
        1,
        &asbd,
        size
    );
    if (status) {
        croak("failed to set output format: %d", status);
    }
}

static void init_output_unit(Mac__AUHAL self) {
    OSStatus status;
    AudioComponent comp;
    AudioComponentDescription desc;
    UInt32 size;
    AudioDeviceID outputDevice;
    AudioObjectPropertyAddress address;

    desc.componentType         = kAudioUnitType_Output;
    desc.componentSubType      = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = desc.componentFlagsMask = 0;

    comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) {
        croak("failed to find HAL audio component");
    }
    AudioComponentInstanceNew(comp, &self->outputUnit);

        
    address.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    address.mScope    = kAudioObjectPropertyScopeGlobal;
    address.mElement  = kAudioObjectPropertyElementMaster;

    size = sizeof(outputDevice);
    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address, 0, NULL, &size, &outputDevice
    );
    if (status) {
        croak("failed to get default output device: %d", status);
    }

    status = AudioUnitSetProperty(
        self->outputUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &outputDevice,
        sizeof(outputDevice)
    );
    if (status) {
        croak("failed to set output device");
    }
}

static void init_input_unit(Mac__AUHAL self) {
    OSStatus status;
    AudioComponent comp;
    AudioComponentDescription desc;
    UInt32 enableIO;
    UInt32 size;
    AudioDeviceID inputDevice;
    AudioObjectPropertyAddress address;

    desc.componentType         = kAudioUnitType_Output;
    desc.componentSubType      = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = desc.componentFlagsMask = 0;

    comp = AudioComponentFindNext(NULL, &desc);
    if (!comp) {
        croak("failed to find HAL audio component");
    }
    AudioComponentInstanceNew(comp, &self->inputUnit);

    enableIO = 1;
    status = AudioUnitSetProperty(
        self->inputUnit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Input,
        1,
        &enableIO,
        sizeof(enableIO)
    );
    if (status) {
        croak("failed to enable input io: %d", status);
    }

    enableIO = 0;
    status = AudioUnitSetProperty(
        self->inputUnit,
        kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output,
        0,
        &enableIO,
        sizeof(enableIO)
    );
    if (status) {
        croak("failed to close output io for input unit: %d", status);
    }


    address.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    address.mScope    = kAudioObjectPropertyScopeGlobal;
    address.mElement  = kAudioObjectPropertyElementMaster;

    size = sizeof(inputDevice);
    status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject,
        &address, 0, NULL, &size, &inputDevice
    );
    if (status) {
        croak("failed to get default input device: %d", status);
    }


    size = sizeof(AudioDeviceID);
    status = AudioUnitSetProperty(
        self->inputUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        1,
        &inputDevice,
        size
    );
    if (status) {
        croak("failed to set input device");
    }

}

MODULE = Mac::AUHAL  PACKAGE = Mac::AUHAL

PROTOTYPES: DISABLE

Mac::AUHAL
new(SV* class)
CODE:
{
    PERL_UNUSED_VAR(class);

    Newx(RETVAL, 1, Mac__AUHAL_t);
    init_output_unit(RETVAL);
    init_input_unit(RETVAL);
    RETVAL->render_cb = NULL;
    RETVAL->input_cb  = NULL;

    /* set default format */
    set_format(RETVAL, 44100.f, 2, 32, 1, 0);
}
OUTPUT:
    RETVAL

void
DESTROY(Mac::AUHAL self)
CODE:
{
    AudioComponentInstanceDispose(self->outputUnit);
    AudioComponentInstanceDispose(self->inputUnit);
    if (self->render_cb)
        SvREFCNT_dec(self->render_cb);
    if (self->input_cb)
        SvREFCNT_dec(self->input_cb);
    Safefree(self);
}

void
start(Mac::AUHAL self)
CODE:
{
    OSStatus status;

    status = AudioUnitInitialize(self->outputUnit);
    if (status) croak("failed to initialize output unit: %d", status);
    status = AudioUnitInitialize(self->inputUnit);
    if (status) croak("failed to initialize input unit: %d", status);

    status = AudioOutputUnitStart(self->outputUnit);
    if (status) croak("failed to start output unit: %d", status);

    status = AudioOutputUnitStart(self->inputUnit);
    if (status) croak("failed to start input unit: %d", status);
}

void
set_render_cb(Mac::AUHAL self, CV* cb)
CODE:
{
    OSStatus status;
    AURenderCallbackStruct cbstruct;

    if (self->render_cb)
        SvREFCNT_dec(self->render_cb);
    self->render_cb = SvREFCNT_inc(cb);

    cbstruct.inputProc = render_callback;
    cbstruct.inputProcRefCon = self;
    status = AudioUnitSetProperty(
        self->outputUnit,
        kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input,
        0,
        &cbstruct,
        sizeof(cbstruct)
    );
    if (status) {
        croak("failed to set render callback: %d", status);
    }
}

void
set_input_cb(Mac::AUHAL self, CV* cb)
CODE:
{
    OSStatus status;
    AURenderCallbackStruct cbstruct;

    cbstruct.inputProc = input_callback;
    cbstruct.inputProcRefCon = NULL;

    status = AudioUnitSetProperty(
        self->inputUnit,
        kAudioOutputUnitProperty_SetInputCallback, 
        kAudioUnitScope_Global,
        1,
        &cbstruct,
        sizeof(cbstruct)
    );
    if (status) {
        croak("failed to set input_callback: %d", status);
    }
}

void
_set_format(Mac::AUHAL self, double sample_rate, U32 channels, U32 bits, bool is_float, bool is_signed_integer)
CODE:
{
    set_format(self, sample_rate, channels, bits, is_float, is_signed_integer);
}

