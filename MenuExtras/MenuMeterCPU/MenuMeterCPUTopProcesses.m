//
//  MenuMeterCPUTopProcesses.m
//
// 	Reader object for top CPU hogging process list
//
//  Copyright (c) 2018 Hofi
//
// 	This file is part of MenuMeters.
//
// 	MenuMeters is free software; you can redistribute it and/or modify
// 	it under the terms of the GNU General Public License version 2 as
//  published by the Free Software Foundation.
//
// 	MenuMeters is distributed in the hope that it will be useful,
// 	but WITHOUT ANY WARRANTY; without even the implied warranty of
// 	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// 	GNU General Public License for more details.
//
// 	You should have received a copy of the GNU General Public License
// 	along with MenuMeters; if not, write to the Free Software
// 	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//

#import "MenuMeterCPUTopProcesses.h"
#import "MenuMeterCPU.h"

#import <libproc.h>
#import <sys/proc_info.h>
#import <sys/types.h>
#import <pwd.h>
#import <mach/mach_time.h>
#import <string.h>

///////////////////////////////////////////////////////////////
//
//    Process info item key strings
//
///////////////////////////////////////////////////////////////

NSString* const kProcessListItemPIDKey           = @"processID";
NSString* const kProcessListItemProcessNameKey   = @"processName";
NSString* const kProcessListItemProcessPathKey   = @"processPath";
NSString* const kProcessListItemUserIDKey        = @"userID";
NSString* const kProcessListItemUserNameKey      = @"userName";
NSString* const kProcessListItemCPUKey           = @"cpuPercent";

///////////////////////////////////////////////////////////////
//
//    libproc snapshot helpers
//
///////////////////////////////////////////////////////////////

typedef struct {
    pid_t pid;
    uid_t uid;
    uint64_t cpuTime;
    char name[2 * MAXCOMLEN];
} MMProcessSample;

// The per-process CPU counters returned by PROC_PIDTASKINFO are in mach
// absolute-time units, the same units as mach_absolute_time(). This means a
// percentage can be computed without converting through the timebase:
// deltaCPU / deltaWall * 100.
static int MMCollectProcessSamples(MMProcessSample **outSamples) {
    *outSamples = NULL;

    int capacity = proc_listallpids(NULL, 0);
    if (capacity <= 0) {
        return 0;
    }

    pid_t *pids = calloc((size_t)capacity, sizeof(pid_t));
    if (!pids) {
        return 0;
    }

    int count = proc_listallpids(pids, capacity * (int)sizeof(pid_t));
    if (count <= 0) {
        free(pids);
        return 0;
    }

    MMProcessSample *samples = calloc((size_t)count, sizeof(MMProcessSample));
    if (!samples) {
        free(pids);
        return 0;
    }

    int used = 0;
    for (int i = 0; i < count; i++) {
        struct proc_taskinfo taskInfo;
        if (proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &taskInfo, sizeof(taskInfo)) != sizeof(taskInfo)) {
            continue;
        }

        struct proc_bsdinfo bsdInfo;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &bsdInfo, sizeof(bsdInfo)) != sizeof(bsdInfo)) {
            continue;
        }

        MMProcessSample *sample = &samples[used++];
        sample->pid = pids[i];
        sample->uid = bsdInfo.pbi_uid;
        sample->cpuTime = taskInfo.pti_total_user + taskInfo.pti_total_system;
        if (bsdInfo.pbi_name[0] != '\0') {
            strlcpy(sample->name, bsdInfo.pbi_name, sizeof(sample->name));
        } else {
            strlcpy(sample->name, bsdInfo.pbi_comm, sizeof(sample->name));
        }
    }

    free(pids);
    *outSamples = samples;
    return used;
}

static NSString *MMUserNameForUID(uid_t uid, NSMutableDictionary<NSNumber *, NSString *> *cache) {
    NSNumber *key = @(uid);
    NSString *name = cache[key];
    if (name) {
        return name;
    }

    struct passwd *pw = getpwuid(uid);
    if (pw && pw->pw_name) {
        name = [NSString stringWithUTF8String:pw->pw_name];
    }
    if (!name) {
        name = key.stringValue;
    }
    cache[key] = name;
    return name;
}

///////////////////////////////////////////////////////////////
//
//	init/dealloc
//
///////////////////////////////////////////////////////////////

@implementation MenuMeterCPUTopProcesses
{
    NSArray *processes;
}

-(instancetype)init
{
    self=[super init];
    return self;
}

-(void)dealloc
{
    [self stopUpdateProcessList];
}

- (void)startUpdateProcessList {
    MMProcessSample *first = NULL;
    int firstCount = MMCollectProcessSamples(&first);

    uint64_t start = mach_absolute_time();
    // A short interval gives a current reading rather than an average over the
    // lifetime of each process. This replaces the one-second sample that the
    // old /usr/bin/top subprocess took.
    usleep(100 * 1000);
    uint64_t end = mach_absolute_time();

    MMProcessSample *second = NULL;
    int secondCount = MMCollectProcessSamples(&second);

    if (!first || !second || firstCount <= 0 || secondCount <= 0 || end <= start) {
        free(first);
        free(second);
        return;
    }

    NSMutableDictionary<NSNumber *, NSNumber *> *previousTimes =
        [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)firstCount];
    for (int i = 0; i < firstCount; i++) {
        previousTimes[@(first[i].pid)] = @(first[i].cpuTime);
    }

    NSMutableDictionary<NSNumber *, NSString *> *userNameCache = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:(NSUInteger)secondCount];
    double wall = (double)(end - start);

    for (int i = 0; i < secondCount; i++) {
        MMProcessSample *sample = &second[i];
        NSNumber *previous = previousTimes[@(sample->pid)];
        double percent = 0.0;
        if (previous && sample->cpuTime >= previous.unsignedLongLongValue) {
            uint64_t delta = sample->cpuTime - previous.unsignedLongLongValue;
            percent = ((double)delta / wall) * 100.0;
        }

        NSString *name = [NSString stringWithUTF8String:sample->name] ?: @"";
        [entries addObject:@{
            kProcessListItemPIDKey: @(sample->pid),
            kProcessListItemCPUKey: @(percent),
            kProcessListItemUserIDKey: @(sample->uid),
            kProcessListItemUserNameKey: MMUserNameForUID(sample->uid, userNameCache),
            kProcessListItemProcessNameKey: [self normalizedCommand:name]
        }];
    }

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double aCPU = [a[kProcessListItemCPUKey] doubleValue];
        double bCPU = [b[kProcessListItemCPUKey] doubleValue];
        if (aCPU > bCPU) {
            return NSOrderedAscending;
        }
        if (aCPU < bCPU) {
            return NSOrderedDescending;
        }
        return [a[kProcessListItemProcessNameKey] compare:b[kProcessListItemProcessNameKey]];
    }];

    processes = entries;

    free(first);
    free(second);
} // startUpdateProcessList

- (void)stopUpdateProcessList {
    // Sampling is synchronous now, so there is no subprocess or timer to tear
    // down. Keep the last result so a menu that is being rebuilt does not lose
    // its rows.
} // stopUpdateProcessList

- (NSArray *)runningProcessesByCPUUsage:(NSUInteger)maxItem
{
    if (!processes) {
        return @[];
    }
    return [processes subarrayWithRange:NSMakeRange(0, MIN(maxItem, processes.count))];
}

- (NSString *)normalizedCommand:(NSString *)name
{
    NSString* result = name;

    // remove leading/trailing whitespaces
    result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // remove login shell prefixes
    for (int i = 0; i < 2; ++i) {
        if (result.length > 0) {
            result = [result stringByReplacingOccurrencesOfString:@"-" withString:@"" options:0 range:NSMakeRange(0, 1)];
        }
    }

    // continue other clean up here

    return result;

} // normalizedCommand:

@end
