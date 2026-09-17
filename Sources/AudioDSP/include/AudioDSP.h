#ifndef EVENTONE_DSP_H
#define EVENTONE_DSP_H
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>

typedef struct ETProcessor ETProcessor;
typedef struct {
    float inputDB;
    float outputDB;
    float automaticGainDB;
    float reductionDB;
    unsigned callbacks;
    bool formatFault;
} ETMeters;

ETProcessor *et_create(double sampleRate, unsigned channels, unsigned inputStartChannel);
void et_destroy(ETProcessor *processor);
void et_configure(ETProcessor *processor, bool automatic, float volume, float trimDB);
ETMeters et_meters(const ETProcessor *processor);
// Interleaved test/offline entry; storage must contain frames * configured channels.
void et_process(ETProcessor *processor, const float *input, float *output, unsigned frames);
OSStatus et_io_proc(AudioObjectID device, const AudioTimeStamp *now,
                    const AudioBufferList *input, const AudioTimeStamp *inputTime,
                    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context);
// Called before starting IO. Disables physical microphone streams; only tap is enabled.
OSStatus et_enable_tap_input(AudioObjectID device, AudioDeviceIOProcID proc,
                             unsigned streamCount, unsigned tapStreamIndex);
OSStatus et_install_callback(AudioObjectID device, ETProcessor *processor, AudioDeviceIOProcID *proc);
#endif
