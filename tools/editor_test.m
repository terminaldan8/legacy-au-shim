// editor_test.m — loads an AU like a host would, initializes it and opens its
// Cocoa editor. Usage: editor_test [type subtype manufacturer]  (default: aumu FxG2 FXPN)
// Build: clang -arch x86_64 -Wno-deprecated-declarations editor_test.m \
//          -framework Cocoa -framework AudioToolbox -framework AudioUnit -o editor_test
#import <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AUCocoaUIView.h>

static void listener(void* ref, AudioUnit au, AudioUnitPropertyID id, AudioUnitScope s, AudioUnitElement e) {
    fprintf(stderr, "listener: prop %u from %p\n", id, au);
}

static void evproc(void* a, void* b, const AudioUnitEvent* e, UInt64 t, AudioUnitParameterValue v) {}

static OSType fourcc(const char* s) {
    return ((OSType)s[0] << 24) | ((OSType)s[1] << 16) | ((OSType)s[2] << 8) | (OSType)s[3];
}

int main(int argc, char** argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        AudioComponentDescription d = { 'aumu', 'FxG2', 'FXPN', 0, 0 };
        if (argc == 4) { d.componentType = fourcc(argv[1]); d.componentSubType = fourcc(argv[2]); d.componentManufacturer = fourcc(argv[3]); }
        AudioComponent c = AudioComponentFindNext(0, &d);
        if (!c) { fprintf(stderr, "component not found\n"); return 1; }
        AudioComponentInstance au = 0;
        fprintf(stderr, "new -> %d\n", (int)AudioComponentInstanceNew(c, &au));
        AudioUnitAddPropertyListener(au, kAudioUnitProperty_ParameterList, listener, 0);
        AudioUnitAddPropertyListener(au, kAudioUnitProperty_PresentPreset, listener, 0);
        fprintf(stderr, "init -> %d\n", (int)AudioUnitInitialize(au));
        AUEventListenerRef el = 0;
        AUEventListenerCreate(evproc,
                              0, CFRunLoopGetMain(), kCFRunLoopDefaultMode, 0.05, 0.05, &el);
        AudioUnitEvent ev = {0};
        ev.mEventType = kAudioUnitEvent_ParameterValueChange;
        ev.mArgument.mParameter.mAudioUnit = au;
        ev.mArgument.mParameter.mParameterID = 0;
        AUEventListenerAddEventType(el, 0, &ev);

        AudioUnitCocoaViewInfo info; UInt32 sz = sizeof info;
        OSStatus r = AudioUnitGetProperty(au, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &info, &sz);
        fprintf(stderr, "CocoaUI -> %d\n", (int)r);
        NSBundle* b = [NSBundle bundleWithURL:(NSURL*)info.mCocoaAUViewBundleLocation];
        Class cls = [b classNamed:(NSString*)info.mCocoaAUViewClass[0]];
        fprintf(stderr, "factory class %p\n", cls);
        id<AUCocoaUIBase> f = [[cls alloc] init];
        NSView* v = [f uiViewForAudioUnit:au withSize:NSMakeSize(800, 600)];
        fprintf(stderr, "view %p frame %.0fx%.0f\n", v, v.frame.size.width, v.frame.size.height);
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
        AudioUnitUninitialize(au);
        AudioComponentInstanceDispose(au);
        fprintf(stderr, "done\n");
    }
    return 0;
}
