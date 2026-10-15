// Geist2Shim — makes the original, unmodified FXpansion Geist2 AU visible on
// macOS 27+, which no longer registers legacy .rsrc (Component Manager) AUs.
//
// This bundle registers itself the modern way (AudioComponents in Info.plist)
// under the legacy plug-in's own ID, so old projects find it. At open time it
// loads the genuine plug-in binary from its installed location, registers its
// legacy entry point with the in-process Component Manager, and forwards every
// AU call to it as Component Manager parameter blocks. The plug-in's own code,
// signature and authorization are left untouched.
//
// Everything plug-in specific lives in Info.plist: the AudioComponents entry
// (type/subtype/manufacturer/name) plus LegacyAUBinary and LegacyAUEntry.
// The instance-handle fix-up below assumes a Symbiosis-wrapped plug-in.
//
// x86_64 only: Geist2 is Intel-only, so native hosts run this out-of-process
// under Rosetta (as they did for the original before macOS 27).

#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AUCocoaUIView.h>
#include <CoreServices/CoreServices.h>
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Objective-C class names are process-global; forks for other plug-ins should
// pass a unique -DSHIM_VIEW_FACTORY=... (build.sh derives it from the bundle name).
#ifndef SHIM_VIEW_FACTORY
#define SHIM_VIEW_FACTORY Geist2ShimViewFactory
#endif
#define SHIM_STR2(x) #x
#define SHIM_STR(x) SHIM_STR2(x)

typedef ComponentResult (*LegacyEntryFn)(ComponentParameters*, Handle);

static LegacyEntryFn gEntry = nullptr;
static Component gComponent = nullptr;
static std::mutex gLock;
// Symbiosis derives saved-state IDs via GetComponentInfo, which needs the legacy
// handle; Apple's AUBase SDK uses AudioComponentGetDescription, which needs the
// host's. Overridable with LegacyAUStateUsesLegacyInstance in Info.plist.
static bool gStateUsesLegacyInstance = true;

// This shim's own bundle (not the host's main bundle).
static NSBundle* shimBundle() {
    Dl_info info;
    dladdr((void*)&shimBundle, &info);
    NSString* bin = [NSString stringWithUTF8String:info.dli_fname];
    return [NSBundle bundleWithPath:[[[bin stringByDeletingLastPathComponent]
                                       stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]];
}

// Load the genuine plug-in and register its legacy entry point (once per process).
static bool ensureRegistered(const AudioComponentDescription& desc) {
    std::lock_guard<std::mutex> g(gLock);
    if (gComponent) return true;
    NSDictionary* plist = [shimBundle() infoDictionary];
    NSString* binary = plist[@"LegacyAUBinary"];
    NSString* entryName = plist[@"LegacyAUEntry"] ?: @"SymbiosisEntry";
    NSNumber* stateLegacy = plist[@"LegacyAUStateUsesLegacyInstance"];
    gStateUsesLegacyInstance = stateLegacy ? stateLegacy.boolValue : [entryName isEqualToString:@"SymbiosisEntry"];
    NSString* name = [plist[@"AudioComponents"] firstObject][@"name"] ?: @"Legacy AU";
    if (!binary) { NSLog(@"AUShim: LegacyAUBinary missing from Info.plist"); return false; }

    void* h = dlopen(binary.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!h) { NSLog(@"AUShim: dlopen failed: %s", dlerror()); return false; }
    gEntry = (LegacyEntryFn)dlsym(h, entryName.UTF8String);
    if (!gEntry) { NSLog(@"AUShim: %@ not found in %@", entryName, binary); return false; }

    ComponentDescription d = { desc.componentType, desc.componentSubType, desc.componentManufacturer, 0, 0 };
    const char* cname = name.UTF8String;
    size_t len = std::min<size_t>(strlen(cname), 255);
    Handle nameH = NewHandleClear(256);
    ((unsigned char*)*nameH)[0] = (unsigned char)len;
    memcpy(*nameH + 1, cname, len);
    // Registered locally (not globally), so only this process sees it.
    gComponent = RegisterComponent(&d, (ComponentRoutineUPP)gEntry, 0, nameH, 0, 0);
    if (!gComponent) NSLog(@"AUShim: RegisterComponent failed");
    return gComponent != nullptr;
}

struct Shim;

struct Listener {
    Shim* shim;
    AudioUnitPropertyID id;
    AudioUnitPropertyListenerProc proc;
    void* refCon;
};

struct Shim {
    AudioComponentPlugInInterface iface;   // must stay first
    AudioComponentDescription desc = {};
    AudioComponentInstance host = nullptr;
    ComponentInstance cm = nullptr;
    Handle storage = nullptr;           // the plug-in's SymbiosisComponent object
    bool instanceSwapped = false;
    std::vector<std::unique_ptr<Listener>> listeners;
    std::mutex listenerLock;
};

static std::map<AudioUnit, Shim*> gShims;   // host instance -> shim (for the editor)
static std::mutex gShimsLock;

// ---- Component Manager call marshalling (LP64: params[0] = instance, then args in order)

struct CMCall {
    ComponentParameters p;
    long extra[8];
};

template <typename T> static long slot(T v) {
    long s = 0;
    static_assert(sizeof(T) <= sizeof(long), "arg too large");
    memcpy(&s, &v, sizeof(T));
    return s;
}

static OSStatus dispatch(Shim* s, SInt16 what, std::initializer_list<long> args) {
    CMCall c;
    memset(&c, 0, sizeof c);
    c.p.what = what;
    c.p.paramSize = (UInt8)(args.size() * sizeof(long));
    long* params = c.p.params;
    params[0] = (long)s->cm;
    int i = 1;
    for (long a : args) params[i++] = a;
    return (OSStatus)gEntry(&c.p, s->storage);
}

// ---- AU methods

static OSStatus Initialize(void* self) {
    return dispatch((Shim*)self, kAudioUnitInitializeSelect, {});
}

static OSStatus Uninitialize(void* self) {
    return dispatch((Shim*)self, kAudioUnitUninitializeSelect, {});
}

// Saving/restoring state (ClassInfo) makes Symbiosis call GetComponentInfo on its
// stored instance, which only works with the Component Manager handle. Swap the
// original handle back in for the duration of those calls (Symbiosis only).
struct ScopedOriginalInstance {
    Shim* s;
    bool active;
    ScopedOriginalInstance(Shim* sh, AudioUnitPropertyID id)
        : s(sh), active(gStateUsesLegacyInstance && sh->instanceSwapped && id == kAudioUnitProperty_ClassInfo) {
        if (active) *(ComponentInstance*)((char*)s->storage + 8) = s->cm;
    }
    ~ScopedOriginalInstance() {
        if (active) *(ComponentInstance*)((char*)s->storage + 8) = (ComponentInstance)s->host;
    }
};

static OSStatus GetPropertyInfo(void* self, AudioUnitPropertyID id, AudioUnitScope sc,
                                AudioUnitElement el, UInt32* outSize, Boolean* outWritable) {
    return dispatch((Shim*)self, kAudioUnitGetPropertyInfoSelect,
                    { slot(id), slot(sc), slot(el), slot(outSize), slot(outWritable) });
}

static OSStatus GetProperty(void* self, AudioUnitPropertyID id, AudioUnitScope sc,
                            AudioUnitElement el, void* outData, UInt32* ioSize) {
    if (id == kAudioUnitProperty_CocoaUI && outData && ioSize
        && *ioSize >= sizeof(AudioUnitCocoaViewInfo)) {
        // Point the host at our editor factory, which hands the plug-in its own instance.
        AudioUnitCocoaViewInfo* v = (AudioUnitCocoaViewInfo*)outData;
        v->mCocoaAUViewBundleLocation = (CFURLRef)[[shimBundle() bundleURL] retain];
        v->mCocoaAUViewClass[0] = CFStringCreateWithCString(nullptr, SHIM_STR(SHIM_VIEW_FACTORY),
                                                            kCFStringEncodingUTF8);
        *ioSize = sizeof(AudioUnitCocoaViewInfo);
        return noErr;
    }
    ScopedOriginalInstance orig((Shim*)self, id);
    return dispatch((Shim*)self, kAudioUnitGetPropertySelect,
                    { slot(id), slot(sc), slot(el), slot(outData), slot(ioSize) });
}

static OSStatus SetProperty(void* self, AudioUnitPropertyID id, AudioUnitScope sc,
                            AudioUnitElement el, const void* inData, UInt32 inSize) {
    ScopedOriginalInstance orig((Shim*)self, id);
    return dispatch((Shim*)self, kAudioUnitSetPropertySelect,
                    { slot(id), slot(sc), slot(el), slot(inData), slot(inSize) });
}

// Geist2 reports its own (Component Manager) instance to listeners; translate
// it back to the host's instance.
static void ListenerTrampoline(void* refCon, AudioUnit, AudioUnitPropertyID id,
                               AudioUnitScope sc, AudioUnitElement el) {
    Listener* l = (Listener*)refCon;
    l->proc(l->refCon, l->shim->host, id, sc, el);
}

static OSStatus AddPropertyListener(void* self, AudioUnitPropertyID id,
                                    AudioUnitPropertyListenerProc proc, void* refCon) {
    Shim* s = (Shim*)self;
    auto l = std::make_unique<Listener>(Listener{ s, id, proc, refCon });
    OSStatus r = dispatch(s, kAudioUnitAddPropertyListenerSelect,
                          { slot(id), slot((AudioUnitPropertyListenerProc)ListenerTrampoline), slot(l.get()) });
    if (r == noErr) {
        std::lock_guard<std::mutex> g(s->listenerLock);
        s->listeners.push_back(std::move(l));
    }
    return r;
}

static OSStatus RemovePropertyListenerWithUserData(void* self, AudioUnitPropertyID id,
                                                   AudioUnitPropertyListenerProc proc, void* refCon) {
    Shim* s = (Shim*)self;
    std::lock_guard<std::mutex> g(s->listenerLock);
    for (auto it = s->listeners.begin(); it != s->listeners.end(); ++it) {
        Listener* l = it->get();
        if (l->id == id && l->proc == proc && l->refCon == refCon) {
            OSStatus r = dispatch(s, kAudioUnitRemovePropertyListenerWithUserDataSelect,
                                  { slot(id), slot((AudioUnitPropertyListenerProc)ListenerTrampoline), slot(l) });
            s->listeners.erase(it);
            return r;
        }
    }
    return noErr;
}

static OSStatus GetParameter(void* self, AudioUnitParameterID id, AudioUnitScope sc,
                             AudioUnitElement el, AudioUnitParameterValue* outValue) {
    return dispatch((Shim*)self, kAudioUnitGetParameterSelect,
                    { slot(id), slot(sc), slot(el), slot(outValue) });
}

static OSStatus SetParameter(void* self, AudioUnitParameterID id, AudioUnitScope sc,
                             AudioUnitElement el, AudioUnitParameterValue value, UInt32 offset) {
    return dispatch((Shim*)self, kAudioUnitSetParameterSelect,
                    { slot(id), slot(sc), slot(el), slot(value), slot(offset) });
}

static OSStatus ScheduleParameters(void* self, const AudioUnitParameterEvent* events, UInt32 n) {
    return dispatch((Shim*)self, kAudioUnitScheduleParametersSelect, { slot(events), slot(n) });
}

static OSStatus Reset(void* self, AudioUnitScope sc, AudioUnitElement el) {
    return dispatch((Shim*)self, kAudioUnitResetSelect, { slot(sc), slot(el) });
}

static OSStatus AddRenderNotify(void* self, AURenderCallback proc, void* refCon) {
    return dispatch((Shim*)self, kAudioUnitAddRenderNotifySelect, { slot(proc), slot(refCon) });
}

static OSStatus RemoveRenderNotify(void* self, AURenderCallback proc, void* refCon) {
    return dispatch((Shim*)self, kAudioUnitRemoveRenderNotifySelect, { slot(proc), slot(refCon) });
}

static OSStatus Render(void* self, AudioUnitRenderActionFlags* flags, const AudioTimeStamp* ts,
                       UInt32 bus, UInt32 frames, AudioBufferList* data) {
    return dispatch((Shim*)self, kAudioUnitRenderSelect,
                    { slot(flags), slot(ts), slot(bus), slot(frames), slot(data) });
}

static OSStatus MIDIEvent(void* self, UInt32 status, UInt32 d1, UInt32 d2, UInt32 offset) {
    return dispatch((Shim*)self, kMusicDeviceMIDIEventSelect,
                    { slot(status), slot(d1), slot(d2), slot(offset) });
}

static AudioComponentMethod Lookup(SInt16 sel) {
    switch (sel) {
        case kAudioUnitInitializeSelect: return (AudioComponentMethod)Initialize;
        case kAudioUnitUninitializeSelect: return (AudioComponentMethod)Uninitialize;
        case kAudioUnitGetPropertyInfoSelect: return (AudioComponentMethod)GetPropertyInfo;
        case kAudioUnitGetPropertySelect: return (AudioComponentMethod)GetProperty;
        case kAudioUnitSetPropertySelect: return (AudioComponentMethod)SetProperty;
        case kAudioUnitAddPropertyListenerSelect: return (AudioComponentMethod)AddPropertyListener;
        case kAudioUnitRemovePropertyListenerWithUserDataSelect:
            return (AudioComponentMethod)RemovePropertyListenerWithUserData;
        case kAudioUnitGetParameterSelect: return (AudioComponentMethod)GetParameter;
        case kAudioUnitSetParameterSelect: return (AudioComponentMethod)SetParameter;
        case kAudioUnitScheduleParametersSelect: return (AudioComponentMethod)ScheduleParameters;
        case kAudioUnitResetSelect: return (AudioComponentMethod)Reset;
        case kAudioUnitAddRenderNotifySelect: return (AudioComponentMethod)AddRenderNotify;
        case kAudioUnitRemoveRenderNotifySelect: return (AudioComponentMethod)RemoveRenderNotify;
        case kAudioUnitRenderSelect: return (AudioComponentMethod)Render;
        case kMusicDeviceMIDIEventSelect: return (AudioComponentMethod)MIDIEvent;
        default: return nullptr;
    }
}

static OSStatus Open(void* self, AudioComponentInstance inst) {
    Shim* s = (Shim*)self;
    s->host = inst;
    if (!ensureRegistered(s->desc)) return kAudioUnitErr_FailedInitialization;
    OSErr e = OpenAComponent(gComponent, &s->cm);
    if (e != noErr || !s->cm) {
        NSLog(@"AUShim: OpenAComponent failed (%d)", e);
        return e ? e : kAudioUnitErr_FailedInitialization;
    }
    s->storage = GetComponentInstanceStorage(s->cm);
    // Symbiosis keeps the instance it was opened with (offset 8) and passes it to
    // AUParameterListenerNotify; with host listeners attached, AudioToolbox rejects
    // the private Component Manager handle and Geist2 aborts. Point it at the
    // host's instance instead — only if the field holds exactly what we expect.
    ComponentInstance* field = s->storage ? (ComponentInstance*)((char*)s->storage + 8) : nullptr;
    if (field && *field == s->cm) {
        *field = (ComponentInstance)inst;
        s->instanceSwapped = true;
    } else {
        NSLog(@"AUShim: unexpected Symbiosis layout; parameter notifications may fail");
    }
    std::lock_guard<std::mutex> g(gShimsLock);
    gShims[(AudioUnit)inst] = s;
    return noErr;
}

static OSStatus Close(void* self) {
    Shim* s = (Shim*)self;
    {
        std::lock_guard<std::mutex> g(gShimsLock);
        gShims.erase((AudioUnit)s->host);
    }
    if (s->instanceSwapped)   // restore so Symbiosis tears down with its own handle
        *(ComponentInstance*)((char*)s->storage + 8) = s->cm;
    if (s->cm) CloseComponent(s->cm);
    delete s;
    return noErr;
}

extern "C" __attribute__((visibility("default")))
void* AUShimFactory(const AudioComponentDescription* desc) {
    Shim* s = new Shim();
    if (desc) s->desc = *desc;
    s->iface.Open = Open;
    s->iface.Close = Close;
    s->iface.Lookup = Lookup;
    s->iface.reserved = nullptr;
    return s;
}

// ---- Editor: ask the plug-in for its own Cocoa view factory and give it its own instance.

@interface SHIM_VIEW_FACTORY : NSObject <AUCocoaUIBase>
@end

@implementation SHIM_VIEW_FACTORY
- (unsigned)interfaceVersion { return 0; }
- (NSString*)description { return @"Editor"; }
- (NSView*)uiViewForAudioUnit:(AudioUnit)au withSize:(NSSize)size {
    Shim* s = nullptr;
    {
        std::lock_guard<std::mutex> g(gShimsLock);
        auto it = gShims.find(au);
        if (it != gShims.end()) s = it->second;
    }
    if (!s) return nil;
    AudioUnitCocoaViewInfo info = {};
    UInt32 sz = sizeof info;
    OSStatus r = dispatch(s, kAudioUnitGetPropertySelect,
                          { slot((AudioUnitPropertyID)kAudioUnitProperty_CocoaUI),
                            slot((AudioUnitScope)kAudioUnitScope_Global), slot((AudioUnitElement)0),
                            slot((void*)&info), slot(&sz) });
    if (r != noErr || !info.mCocoaAUViewClass[0]) return nil;
    Class cls = NSClassFromString((NSString*)info.mCocoaAUViewClass[0]);
    if (!cls) {
        NSBundle* b = [NSBundle bundleWithURL:(NSURL*)info.mCocoaAUViewBundleLocation];
        [b load];
        cls = [b classNamed:(NSString*)info.mCocoaAUViewClass[0]];
    }
    CFRelease(info.mCocoaAUViewClass[0]);
    if (info.mCocoaAUViewBundleLocation) CFRelease(info.mCocoaAUViewBundleLocation);
    if (!cls) return nil;
    id<AUCocoaUIBase> factory = [[cls alloc] init];
    NSView* v = [factory uiViewForAudioUnit:(AudioUnit)s->cm withSize:size];
    [(id)factory release];
    return v;
}
@end
