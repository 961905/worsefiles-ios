//
//  pathleak_first_match.m
//  WorseFiles
//
//  Derived from pathleak.m by Taj C (forcequit), part of worse_query,
//  GPL-3.0. This file is part of WorseFiles, GPL-3.0. See LICENSE.
//
//  Single-target lookup: stop at the first direct child whose name contains
//  needle. Callers pass bounded ranges so early exit really saves work.
//

#import <Foundation/Foundation.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>
#include <string.h>
#include <limits.h>
#include "pathleak.h"

NSArray<NSString *> *pathleak_first_match(NSString *root,
                                          NSString *needle,
                                          uint64_t from_inode,
                                          uint64_t to_inode) {
    if (root.length == 0 || needle.length == 0) return nil;
    if (to_inode < 1 || from_inode > to_inode) return nil;
    if (from_inode < 1) from_inode = 1;
    if (to_inode == UINT64_MAX) to_inode = UINT64_MAX - 1;

    NSString *dir = root;
    while (dir.length > 1 && [dir hasSuffix: @"/"]) {
        dir = [dir substringToIndex: dir.length - 1];
    }

    struct statfs sfs;
    if (statfs(dir.fileSystemRepresentation, &sfs) != 0) return nil;
    fsid_t fsid = sfs.f_fsid;

    char prefix[PATH_MAX];
    if (![dir getFileSystemRepresentation: prefix maxLength: sizeof(prefix)]) return nil;
    size_t prefix_length = strlen(prefix);
    if (prefix_length == 1 && prefix[0] == '/') prefix_length = 0;

    const char *needle_bytes = needle.UTF8String;
    if (!needle_bytes) return nil;
    size_t needle_length = strlen(needle_bytes);

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    char buffer[PATH_MAX];
    for (uint64_t inode = from_inode; inode <= to_inode; inode++) {
        ssize_t n = fsgetpath(buffer, sizeof(buffer), &fsid, inode);
        if (n <= 0) continue;

        if (strncmp(buffer, prefix, prefix_length) != 0) continue;
        if (buffer[prefix_length] != '/') continue;
        const char *name = buffer + prefix_length + 1;
        if (strchr(name, '/')) continue;
        if (strlen(name) < needle_length) continue;
        if (!strstr(name, needle_bytes)) continue;

        NSString *string = [[NSString alloc] initWithBytes: buffer
                                                    length: strlen(buffer)
                                                  encoding: NSUTF8StringEncoding];
        if (string) [result addObject: string];
#if !__has_feature(objc_arc)
        [string release];
#endif
        break;
    }
    return result;
}

