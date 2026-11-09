//
//  WFAppGroups.m
//  WorseFiles
//
//  This file is part of WorseFiles, GPL-3.0. See LICENSE.
//

#import "WFAppGroups.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

typedef CFTypeRef (*WFCreateTaskFn)(CFAllocatorRef);
typedef CFTypeRef (*WFCopyEntitlementFn)(CFTypeRef, CFStringRef, CFErrorRef *);

NSArray<NSString *> *WFCurrentAppGroups(void) {
    void *handle = dlopen("/System/Library/Frameworks/Security.framework/Security",
                          RTLD_LAZY | RTLD_LOCAL);
    if (!handle) return @[];

    WFCreateTaskFn createTask = (WFCreateTaskFn)dlsym(handle, "SecTaskCreateFromSelf");
    WFCopyEntitlementFn copyEntitlement =
        (WFCopyEntitlementFn)dlsym(handle, "SecTaskCopyValueForEntitlement");

    NSArray<NSString *> *groups = @[];
    if (createTask && copyEntitlement) {
        CFTypeRef task = createTask(kCFAllocatorDefault);
        if (task) {
            CFTypeRef value = copyEntitlement(task,
                                              CFSTR("com.apple.security.application-groups"),
                                              NULL);
            if (value) {
                if (CFGetTypeID(value) == CFArrayGetTypeID()) {
                    groups = (NSArray<NSString *> *)CFBridgingRelease(value);
                } else {
                    CFRelease(value);
                }
            }
            CFRelease(task);
        }
    }

    dlclose(handle);
    return groups ?: @[];
}
