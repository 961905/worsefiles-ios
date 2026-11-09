//
//  pathleak_range.m
//  WorseFiles
//
//  pathleak_range is derived from pathleak.m by Taj C (forcequit),
//  part of worse_query, GPL-3.0.
//
//  This file is part of WorseFiles, which is free software under the
//  GNU General Public License v3. See LICENSE.
//

#import <Foundation/Foundation.h>
#include <sys/fsgetpath.h>
#include <sys/mount.h>
#include <string.h>
#include <limits.h>
#include "pathleak.h"

// Same inode brute force as pathleak(), bounded to [from_inode, to_inode].
// Splitting the range across threads is what makes a cold scan bearable.
NSArray<NSString *> *pathleak_range(NSString *path, uint64_t from_inode, uint64_t to_inode) {
    if (path.length == 0 || to_inode < 1 || from_inode > to_inode) return @[];
    if (from_inode < 1) from_inode = 1;
    if (to_inode == UINT64_MAX) to_inode = UINT64_MAX - 1;

    NSString *dir = path;
    while (dir.length > 1 && [dir hasSuffix: @"/"]) {
        dir = [dir substringToIndex: dir.length - 1];
    }

    struct statfs sfs;
    if (statfs(dir.fileSystemRepresentation, &sfs) != 0) return @[];
    fsid_t fsid = sfs.f_fsid;

    char prefix[PATH_MAX];
    if (![dir getFileSystemRepresentation: prefix maxLength: sizeof(prefix)]) return @[];
    size_t prefix_length = strlen(prefix);
    if (prefix_length == 1 && prefix[0] == '/') prefix_length = 0;

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    char buffer[PATH_MAX];

    for (uint64_t inode = from_inode; inode <= to_inode; inode++) {
        ssize_t n = fsgetpath(buffer, sizeof(buffer), &fsid, inode);
        if (n <= 0) continue;

        if (strncmp(buffer, prefix, prefix_length) != 0) continue;
        if (buffer[prefix_length] != '/') continue;
        if (strchr(buffer + prefix_length + 1, '/')) continue;

        NSString *string = [[NSString alloc] initWithBytes: buffer
                                                    length: strlen(buffer)
                                                  encoding: NSUTF8StringEncoding];
        if (string) [result addObject: string];
        #if !__has_feature(objc_arc)
        [string release];
        #endif
    }
    return result;
}
