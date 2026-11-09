//
//  pathleak_roots.m
//  WorseFiles
//
//  Derived from pathleak.m by Taj C (forcequit), part of worse_query,
//  GPL-3.0. This file is part of WorseFiles, GPL-3.0. See LICENSE.
//
//  The original scans one parent prefix. WorseFiles has several container
//  parents on the same volume, so this walks the inode range once and checks
//  each returned path against all prefixes.
//

#import <Foundation/Foundation.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>
#include <string.h>
#include <limits.h>
#include "pathleak.h"

NSDictionary<NSString *, NSArray<NSString *> *> *pathleak_roots(NSArray<NSString *> *roots,
                                                               uint64_t from_inode,
                                                               uint64_t to_inode) {
    if (roots.count == 0 || to_inode < 1 || from_inode > to_inode) return @{};
    if (roots.count > 8) return @{};
    if (from_inode < 1) from_inode = 1;
    if (to_inode == UINT64_MAX) to_inode = UINT64_MAX - 1;

    char prefixes[8][PATH_MAX];
    size_t lengths[8];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    struct statfs firstStat;
    fsid_t fsid;
    BOOL haveStat = NO;

    for (NSString *raw in roots) {
        if (![raw isKindOfClass:NSString.class]) continue;
        NSString *dir = raw;
        while (dir.length > 1 && [dir hasSuffix: @"/"]) {
            dir = [dir substringToIndex: dir.length - 1];
        }
        if (dir.length == 0) continue;

        struct statfs current;
        if (statfs(dir.fileSystemRepresentation, &current) != 0) continue;
        if (!haveStat) {
            firstStat = current;
            fsid = current.f_fsid;
            haveStat = YES;
        } else if (memcmp(&current.f_fsid, &firstStat.f_fsid, sizeof(fsid_t)) != 0) {
            continue;
        }

        NSUInteger slot = keys.count;
        if (![dir getFileSystemRepresentation: prefixes[slot] maxLength: sizeof(prefixes[slot])]) {
            continue;
        }
        lengths[slot] = strlen(prefixes[slot]);
        [keys addObject: dir];
    }

    NSUInteger count = keys.count;
    if (count == 0 || !haveStat) return @{};

    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *found =
        [NSMutableDictionary dictionaryWithCapacity: count];
    for (NSString *key in keys) {
        found[key] = [NSMutableArray array];
    }

    char buffer[PATH_MAX];
    for (uint64_t inode = from_inode; inode <= to_inode; inode++) {
        ssize_t n = fsgetpath(buffer, sizeof(buffer), &fsid, inode);
        if (n <= 0) continue;

        for (NSUInteger index = 0; index < count; index++) {
            size_t prefixLength = lengths[index];
            if (strncmp(buffer, prefixes[index], prefixLength) != 0) continue;
            if (buffer[prefixLength] != '/') continue;
            if (strchr(buffer + prefixLength + 1, '/')) continue;

            NSString *path = [[NSString alloc] initWithBytes: buffer
                                                      length: strlen(buffer)
                                                    encoding: NSUTF8StringEncoding];
            if (path) [found[keys[index]] addObject: path];
            break;
        }
    }

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *result =
        [NSMutableDictionary dictionaryWithCapacity: count];
    for (NSString *key in keys) {
        result[key] = [found[key] copy];
    }
    return [result copy];
}
