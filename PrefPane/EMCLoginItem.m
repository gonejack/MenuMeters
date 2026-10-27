//
//  Copyright (c) 2014 Enrico M. Crisostomo. All rights reserved.
//
//  License: BSD 3-Clause License
//  (http://opensource.org/licenses/BSD-3-Clause)
//

#import "EMCLoginItem.h"

#import <ServiceManagement/ServiceManagement.h>

#if !__has_feature(objc_arc)
#error This class requires ARC support to be enabled.
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// LSSharedFileList is deprecated since macOS 10.11 but is the only public
// API for login items on macOS 11 and 12. SMAppService (macOS 13+) is used
// whenever it is available.
@implementation EMCLoginItem
{
    NSURL *url;
    LSSharedFileListItemRef itemBeforeInsertion;
    NSURL *itemBeforePath;
    BOOL isMainApp;
}

- (instancetype)init
{
    return [self initWithPath:NSBundle.mainBundle.bundlePath];
}

- (instancetype)initWithBundle:(NSBundle *)bundle
{
    if (!bundle)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Bundle cannot be null."
                                     userInfo:nil];
    }
    return [self initWithPath:bundle.bundlePath];
}

- (instancetype)initWithPath:(NSString *)appPath
{
    if (!appPath)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Path cannot be null."
                                     userInfo:nil];
    }

    self = [super init];
    if (self)
    {
        url = [NSURL fileURLWithPath:appPath];
        itemBeforeInsertion = kLSSharedFileListItemLast;
        isMainApp = [url.path isEqualToString:NSBundle.mainBundle.bundlePath];
    }
    return self;
}

+ (instancetype)loginItem
{
    return [[EMCLoginItem alloc] initWithBundle:[NSBundle mainBundle]];
}

+ (instancetype)loginItemWithBundle:(NSBundle *)bundle
{
    return [[EMCLoginItem alloc] initWithBundle:bundle];
}

+ (instancetype)loginItemWithPath:(NSString *)path
{
    return [[EMCLoginItem alloc] initWithPath:path];
}

- (BOOL)isLoginItem
{
    if (isMainApp)
    {
        if (@available(macOS 13.0, *))
        {
            return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
        }
    }
    return [self legacyIsLoginItem];
}

- (void)addLoginItem
{
    if (isMainApp)
    {
        if (@available(macOS 13.0, *))
        {
            NSError *error = nil;
            if (![SMAppService.mainAppService registerAndReturnError:&error])
            {
                NSLog(@"Error: cannot register login item: %@", error.localizedDescription);
            }
            return;
        }
    }
    [self legacyAddLoginItem];
}

- (void)removeLoginItem
{
    if (isMainApp)
    {
        if (@available(macOS 13.0, *))
        {
            NSError *error = nil;
            if (![SMAppService.mainAppService unregisterAndReturnError:&error])
            {
                NSLog(@"Error: cannot unregister login item: %@", error.localizedDescription);
            }
            return;
        }
    }
    [self legacyRemoveLoginItem];
}

- (void)addAfterLast
{
    itemBeforeInsertion = kLSSharedFileListItemLast;
    itemBeforePath = nil;
}

- (void)addAfterFirst
{
    itemBeforeInsertion = kLSSharedFileListItemBeforeFirst;
    itemBeforePath = nil;
}

- (void)addAfterItemWithPath:(NSString *)path
{
    if (!path)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Path cannot be null."
                                     userInfo:nil];
    }

    itemBeforeInsertion = NULL;
    itemBeforePath = [NSURL fileURLWithPath:path];
}

- (void)addAfterBundle:(NSBundle *)bundle
{
    if (!bundle)
    {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Bundle cannot be null."
                                     userInfo:nil];
    }

    itemBeforeInsertion = NULL;
    itemBeforePath = [NSURL fileURLWithPath:bundle.bundlePath];
}

#pragma mark - Legacy LSSharedFileList implementation

- (BOOL)legacyIsLoginItem
{
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems,
                                                            NULL);
    if (!loginItems)
    {
        NSLog(@"Warning: LSSharedFileListCreate failed, could not get list of login items.");
        return NO;
    }

    UInt32 seed = 0;
    NSArray *loginItemsArray = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
    for (id item in loginItemsArray)
    {
        LSSharedFileListItemRef loginItem = (__bridge LSSharedFileListItemRef)item;
        CFURLRef itemURL = NULL;
        if (LSSharedFileListItemResolve(loginItem,
                                        kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes,
                                        &itemURL,
                                        NULL) == noErr)
        {
            BOOL matches = itemURL && [(__bridge NSURL *)itemURL isEqual:url];
            if (itemURL)
            {
                CFRelease(itemURL);
            }
            if (matches)
            {
                CFRelease(loginItems);
                return YES;
            }
        }
    }
    CFRelease(loginItems);
    return NO;
}

- (void)legacyAddLoginItem
{
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems,
                                                            NULL);
    if (!loginItems)
    {
        NSLog(@"Error: LSSharedFileListCreate failed, could not get list of login items.");
        return;
    }

    LSSharedFileListItemRef insertionPoint = [self findInsertionPoint:loginItems];
    BOOL releaseInsertionPoint = (insertionPoint != kLSSharedFileListItemLast &&
                                  insertionPoint != itemBeforeInsertion);
    if (!LSSharedFileListInsertItemURL(loginItems,
                                       insertionPoint,
                                       NULL,
                                       NULL,
                                       (__bridge CFURLRef)url,
                                       NULL,
                                       NULL))
    {
        NSLog(@"Error: LSSharedFileListInsertItemURL failed, could not create login item.");
    }
    if (releaseInsertionPoint)
    {
        CFRelease(insertionPoint);
    }
    CFRelease(loginItems);
}

- (void)legacyRemoveLoginItem
{
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems,
                                                            NULL);
    if (!loginItems)
    {
        NSLog(@"Warning: could not get list of login items.");
        return;
    }

    BOOL removed = NO;
    UInt32 seed = 0;
    NSArray *loginItemsArray = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
    for (id item in loginItemsArray)
    {
        LSSharedFileListItemRef loginItem = (__bridge LSSharedFileListItemRef)item;
        CFURLRef itemURL = NULL;
        if (LSSharedFileListItemResolve(loginItem,
                                        kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes,
                                        &itemURL,
                                        NULL) == noErr)
        {
            BOOL matches = itemURL && [(__bridge NSURL *)itemURL isEqual:url];
            if (itemURL)
            {
                CFRelease(itemURL);
            }
            if (matches)
            {
                if (LSSharedFileListItemRemove(loginItems, loginItem) == noErr)
                {
                    removed = YES;
                    break;
                }
                NSLog(@"Error: Unknown error while removing login item.");
            }
        }
    }

    if (!removed)
    {
        NSLog(@"Error: could not find login item to remove.");
    }
    CFRelease(loginItems);
}

- (LSSharedFileListItemRef)findInsertionPoint:(LSSharedFileListRef)loginItems
{
    if (itemBeforeInsertion)
    {
        return itemBeforeInsertion;
    }

    const LSSharedFileListItemRef found = [self findItem:loginItems withPath:itemBeforePath];
    if (found)
    {
        // The item is owned by the shared file list snapshot; keep it alive
        // until it has been used by the caller.
        return (LSSharedFileListItemRef)CFRetain(found);
    }

    NSLog(@"Warning: Could not find item with specified path.");
    return kLSSharedFileListItemLast;
}

- (LSSharedFileListItemRef)findItem:(LSSharedFileListRef)loginItems
                           withPath:(NSURL *)path
{
    UInt32 seed = 0;
    NSArray *loginItemsArray = CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seed));
    for (id item in loginItemsArray)
    {
        LSSharedFileListItemRef loginItem = (__bridge LSSharedFileListItemRef)item;
        CFURLRef itemURL = NULL;
        if (LSSharedFileListItemResolve(loginItem,
                                        kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes,
                                        &itemURL,
                                        NULL) == noErr)
        {
            BOOL matches = itemURL && [(__bridge NSURL *)itemURL isEqual:path];
            if (itemURL)
            {
                CFRelease(itemURL);
            }
            if (matches)
            {
                return loginItem;
            }
        }
    }
    return NULL;
}

@end

#pragma clang diagnostic pop
