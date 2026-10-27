//
//  MenuMeterWorkspaceCompat.h
//
//  Helpers around NSWorkspace application launching. -launchApplication: was
//  deprecated in macOS 11; the block-based API works on every supported OS.
//
//  This file is part of MenuMeters.
//

#ifndef MenuMeterWorkspaceCompat_h
#define MenuMeterWorkspaceCompat_h

#import <AppKit/AppKit.h>

static inline BOOL MenuMetersOpenApplication(NSString *bundleIdentifier,
                                             NSString *fallbackPath,
                                             NSString *displayName) {
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSURL *url = [workspace URLForApplicationWithBundleIdentifier:bundleIdentifier];
    if (!url && fallbackPath.length &&
        [[NSFileManager defaultManager] fileExistsAtPath:fallbackPath]) {
        url = [NSURL fileURLWithPath:fallbackPath];
    }
    if (!url) {
        NSLog(@"MenuMeters unable to locate %@.", displayName ?: bundleIdentifier);
        return NO;
    }

    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    [workspace openApplicationAtURL:url
                      configuration:configuration
                  completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (error) {
            NSLog(@"MenuMeters unable to launch %@: %@", displayName ?: bundleIdentifier, error.localizedDescription);
        }
    }];
    return YES;
}

#endif /* MenuMeterWorkspaceCompat_h */
