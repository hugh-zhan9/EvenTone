#include "AudioDSP.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Realtime counters must be lock-free");
struct ETProcessor {
    double rate;
    unsigned channels, inputStart, windowFrames, windowCount;
    double windowEnergy, outputEnergy;
    float slowEnergy, autoDB, wantedDB, manualGain, limiterGain, ramp;
    float manualCoefficient, limiterRelease, rampStep;
    _Atomic bool automatic;
    _Atomic float volume, trimDB;
    _Atomic float inputDB, outputDB, automaticGainDB, reductionDB;
    _Atomic unsigned callbacks;
    _Atomic bool formatFault;
};

static float bound(float x, float lo, float hi) { return fminf(hi, fmaxf(lo, x)); }
static float db(float energy) { return 10.f * log10f(fmaxf(energy, 1e-12f)); }

ETProcessor *et_create(double rate, unsigned channels, unsigned inputStart) {
    if (!isfinite(rate) || rate < 8000 || rate > 192000 || channels < 1 || channels > 2) return NULL;
    ETProcessor *p = calloc(1, sizeof(*p));
    if (!p) return NULL;
    p->rate = rate; p->channels = channels; p->inputStart = inputStart;
    p->windowFrames = (unsigned)(rate * .02);
    p->limiterGain = 1;
    p->manualCoefficient = 1.f - expf(-1.f / (float)(rate * .05));
    p->limiterRelease = 1.f - expf(-1.f / (float)(rate * .08));
    p->rampStep = 1.f / (float)(rate * .03);
    atomic_init(&p->automatic, true); atomic_init(&p->volume, .8f); atomic_init(&p->trimDB, 0);
    atomic_init(&p->inputDB, -120); atomic_init(&p->outputDB, -120);
    atomic_init(&p->automaticGainDB, 0); atomic_init(&p->reductionDB, 0);
    atomic_init(&p->callbacks, 0); atomic_init(&p->formatFault, false);
    if (!atomic_is_lock_free(&p->volume)) { free(p); return NULL; }
    return p;
}

void et_destroy(ETProcessor *p) { free(p); }
void et_configure(ETProcessor *p, bool automatic, float volume, float trimDB) {
    if (!p) return;
    atomic_store_explicit(&p->automatic, automatic, memory_order_relaxed);
    atomic_store_explicit(&p->volume, isfinite(volume) ? bound(volume, 0, 1) : .8f, memory_order_relaxed);
    atomic_store_explicit(&p->trimDB, isfinite(trimDB) ? bound(trimDB, -12, 12) : 0, memory_order_relaxed);
}

ETMeters et_meters(const ETProcessor *p) {
    if (!p) return (ETMeters){-120, -120, 0, 0, 0, false};
    return (ETMeters){atomic_load(&p->inputDB), atomic_load(&p->outputDB),
        atomic_load(&p->automaticGainDB), atomic_load(&p->reductionDB),
        atomic_load(&p->callbacks), atomic_load(&p->formatFault)};
}

// Only the audio callback touches non-atomic processing history.
static void frame(ETProcessor *p, const float *input, float *output, bool automatic, float manual) {
    float clean[2] = {0, 0}, energy = 0;
    for (unsigned c = 0; c < p->channels; c++) {
        clean[c] = isfinite(input[c]) ? bound(input[c], -16, 16) : 0;
        energy += clean[c] * clean[c] / p->channels;
    }
    p->windowEnergy += energy;
    if (!automatic) p->wantedDB = 0;
    float step = (p->wantedDB < p->autoDB ? 36.f : 3.f) / (float)p->rate;
    p->autoDB += bound(p->wantedDB - p->autoDB, -step, step);
    p->manualGain += p->manualCoefficient * (manual - p->manualGain);
    p->ramp = fminf(1, p->ramp + p->rampStep);
    float gain = powf(10.f, p->autoDB / 20.f) * p->manualGain * p->ramp;
    float peak = 0;
    for (unsigned c = 0; c < p->channels; c++) peak = fmaxf(peak, fabsf(clean[c] * gain));
    const float ceiling = .89125094f; // -1 dBFS sample peak (not true-peak certification).
    float needed = peak > ceiling ? ceiling / peak : 1;
    if (needed < p->limiterGain) p->limiterGain = needed;
    else p->limiterGain += p->limiterRelease * (needed - p->limiterGain);
    for (unsigned c = 0; c < p->channels; c++) {
        output[c] = clean[c] * gain * p->limiterGain;
        p->outputEnergy += output[c] * output[c] / p->channels;
    }
    if (++p->windowCount >= p->windowFrames) {
        float rmsEnergy = (float)(p->windowEnergy / p->windowCount);
        float level = db(rmsEnergy);
        // Gate on the fresh window, not the long tail of the averaged detector.
        if (level > -55) {
            p->slowEnergy = p->slowEnergy == 0 ? rmsEnergy : .94f * p->slowEnergy + .06f * rmsEnergy;
            p->wantedDB = automatic ? bound(-22.f - db(p->slowEnergy), -18, 12) : 0;
        } else {
            // Quiet pauses neither build extra gain nor keep a previous ramp running.
            p->wantedDB = automatic ? p->autoDB : 0;
            p->slowEnergy = 0;
        }
        atomic_store_explicit(&p->inputDB, level, memory_order_relaxed);
        atomic_store_explicit(&p->outputDB, db((float)(p->outputEnergy / p->windowCount)), memory_order_relaxed);
        atomic_store_explicit(&p->automaticGainDB, p->autoDB, memory_order_relaxed);
        atomic_store_explicit(&p->reductionDB, -20.f * log10f(fmaxf(p->limiterGain, 1e-6f)), memory_order_relaxed);
        p->windowEnergy = 0; p->outputEnergy = 0; p->windowCount = 0;
    }
}

void et_process(ETProcessor *p, const float *input, float *output, unsigned frames) {
    if (!p || !input || !output || !frames) return;
    bool automatic = atomic_load_explicit(&p->automatic, memory_order_relaxed);
    float manual = atomic_load_explicit(&p->volume, memory_order_relaxed) *
        powf(10.f, atomic_load_explicit(&p->trimDB, memory_order_relaxed) / 20.f);
    for (unsigned f = 0; f < frames; f++) frame(p, input + f * p->channels, output + f * p->channels, automatic, manual);
    atomic_fetch_add_explicit(&p->callbacks, 1, memory_order_relaxed);
}

static bool channel(const AudioBufferList *list, unsigned index, float **data, unsigned *stride, unsigned *frames) {
    for (unsigned b = 0; b < list->mNumberBuffers; b++) {
        const AudioBuffer *buffer = &list->mBuffers[b];
        if (index < buffer->mNumberChannels) {
            if (!buffer->mData || !buffer->mNumberChannels || buffer->mDataByteSize % (sizeof(float) * buffer->mNumberChannels)) return false;
            *data = (float *)buffer->mData + index;
            *stride = buffer->mNumberChannels;
            *frames = buffer->mDataByteSize / (sizeof(float) * buffer->mNumberChannels);
            return true;
        }
        index -= buffer->mNumberChannels;
    }
    return false;
}

OSStatus et_io_proc(AudioObjectID device, const AudioTimeStamp *now,
                    const AudioBufferList *input, const AudioTimeStamp *inputTime,
                    AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    ETProcessor *p = context;
    if (output) for (unsigned b = 0; b < output->mNumberBuffers; b++)
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    if (!p || !input || !output) return noErr;
    float *in[2], *out[2]; unsigned is[2], os[2], count = 0;
    for (unsigned c = 0; c < p->channels; c++) {
        unsigned ni = 0, no = 0;
        if (!channel(input, p->inputStart + c, &in[c], &is[c], &ni) ||
            !channel(output, c, &out[c], &os[c], &no) || ni != no || (c && ni != count)) {
            atomic_store_explicit(&p->formatFault, true, memory_order_relaxed);
            return noErr;
        }
        count = ni;
    }
    bool automatic = atomic_load_explicit(&p->automatic, memory_order_relaxed);
    float manual = atomic_load_explicit(&p->volume, memory_order_relaxed) *
        powf(10.f, atomic_load_explicit(&p->trimDB, memory_order_relaxed) / 20.f);
    for (unsigned f = 0; f < count; f++) {
        float src[2] = {0, 0}, dst[2] = {0, 0};
        for (unsigned c = 0; c < p->channels; c++) src[c] = in[c][f * is[c]];
        frame(p, src, dst, automatic, manual);
        for (unsigned c = 0; c < p->channels; c++) out[c][f * os[c]] = dst[c];
    }
    atomic_fetch_add_explicit(&p->callbacks, 1, memory_order_relaxed);
    return noErr;
}

OSStatus et_enable_tap_input(AudioObjectID device, AudioDeviceIOProcID proc, unsigned count, unsigned index) {
    if (!count || index >= count) return kAudioHardwareIllegalOperationError;
    size_t size = offsetof(AudioHardwareIOProcStreamUsage, mStreamIsOn) + count * sizeof(UInt32);
    AudioHardwareIOProcStreamUsage *usage = calloc(1, size);
    if (!usage) return kAudioHardwareUnspecifiedError;
    usage->mIOProc = (void *)proc; usage->mNumberStreams = count; usage->mStreamIsOn[index] = 1;
    AudioObjectPropertyAddress address = {kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementMain};
    OSStatus result = AudioObjectSetPropertyData(device, &address, 0, NULL, (UInt32)size, usage);
    free(usage);
    return result;
}

OSStatus et_install_callback(AudioObjectID device, ETProcessor *p, AudioDeviceIOProcID *proc) {
    return AudioDeviceCreateIOProcID(device, et_io_proc, p, proc);
}
