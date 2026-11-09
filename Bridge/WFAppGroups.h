//
//  WFAppGroups.h
//  WorseFiles
//

#ifndef WFAppGroups_h
#define WFAppGroups_h

#import <Foundation/Foundation.h>

// Reads com.apple.security.application-groups from this process's effective
// code signature. Returns an empty array when the signature cannot be read.
NSArray<NSString *> *WFCurrentAppGroups(void);

#endif /* WFAppGroups_h */
