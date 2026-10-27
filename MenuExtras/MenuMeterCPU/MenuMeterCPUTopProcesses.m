//
//  MenuMeterCPUTopProcesses.mm
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
//    Private categories
//
///////////////////////////////////////////////////////////////


///////////////////////////////////////////////////////////////
//
//	init/dealloc
//
///////////////////////////////////////////////////////////////

@implementation MenuMeterCPUTopProcesses
{
    NSArray*processes;
    NSTask*task;
    NSPipe*pipe;
    NSString*buffer;
    int parseState; //0 is before the first PID, COMMAND ... ; 1 is just after it saw PID, ...
    NSMutableArray*tempArray;
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

-(void)consumeData:(NSData *)data
{
    if (!pipe || !data.length) {
        return;
    }
    NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!chunk) {
        return;
    }
    buffer = [buffer ?: @"" stringByAppendingString:chunk];
    while ([buffer containsString:@"\n"]) {
        NSUInteger i = [buffer rangeOfString:@"\n"].location;
        NSString *line = [buffer substringToIndex:i];
        [self dealWithLine:line];
        buffer = [buffer substringFromIndex:i+1];
    }
}

- (void)startUpdateProcessList {
    [self stopUpdateProcessList];

    parseState = 0;
    buffer = @"";
    processes = nil;

    task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/top"];
    task.arguments = @[@"-s", @"1", @"-l", @"0",
                       @"-stats", @"pid,cpu,uid,user,command",
                       @"-o", @"cpu",
                       @"-n", [@(kCPUrocessCountMax) stringValue]];

    pipe = [NSPipe pipe];
    task.standardOutput = pipe;

    __weak typeof(self) weakSelf = self;
    pipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *fh) {
        NSData *data = [fh availableData];
        if (!data.length) {
            fh.readabilityHandler = nil;
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf consumeData:data];
        });
    };

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"MenuMeterCPU unable to launch top: %@", error.localizedDescription);
        pipe.fileHandleForReading.readabilityHandler = nil;
        task = nil;
        pipe = nil;
    }
} // startUpdateProcessList
    
- (void)stopUpdateProcessList {
    pipe.fileHandleForReading.readabilityHandler = nil;
    if (task.isRunning) {
        [task terminate];
    }
    task = nil;
    pipe = nil;
    buffer = nil;
} // stopUpdateProcessList
    
- (NSArray *)runningProcessesByCPUUsage:(NSUInteger)maxItem
{
    if (!processes) {
        return @[];
    }
    return [processes subarrayWithRange:NSMakeRange(0, MIN(maxItem, processes.count))];
}
-(void)dealWithLine:(NSString*)s
{
    if(parseState==0){
        if([s hasPrefix:@"PID"]){
            parseState=1;
            tempArray=[NSMutableArray array];
        }
        return;
    }
    if([s hasPrefix:@"Processes:"]){
        parseState=0;
        // one sample completed
        processes=tempArray;
        return;
    }
    
    NSArray*a=[s componentsSeparatedByString:@" "];
    NSMutableArray*x=[NSMutableArray array];
    for(NSString*i in a){
        if(![i isEqualToString:@""]){
            [x addObject:i];
        }
    }
    if (x.count < 5 || !tempArray) {
        return;
    }
    NSArray*commandName=[x subarrayWithRange:NSMakeRange(4,x.count-4)];
    NSDictionary* entry = @{ kProcessListItemPIDKey:x[0],
                             kProcessListItemCPUKey:x[1],
                             kProcessListItemUserIDKey:x[2],
                             kProcessListItemUserNameKey:x[3],
                             kProcessListItemProcessNameKey:[self normalizedCommand:[commandName componentsJoinedByString:@" "]]
                             };
    [tempArray addObject:entry];
}




- (NSString *)normalizedCommand:(NSString *)name
{
    NSString* result = name;
    
    // remove leading/trailing whitespaces
    result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // remove login shell prefixes
    for (int i = 0; i < 2; ++i) {
        if (name.length > 0) {
            result = [result stringByReplacingOccurrencesOfString:@"-" withString:@"" options:0 range:NSMakeRange(0, 1)];
        }
    }
    
    // continue other clean up here
    
    return result;
    
} // normalizedCommand:

    
@end
