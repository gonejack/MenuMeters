//
//  MenuMetersPrefWindow.h
//
//  Programmatic replacement for MenuMetersPref.xib
//
//  This file is part of MenuMeters.
//

#import "MenuMetersPref.h"

@interface MenuMetersPref (PreferenceWindow)

// Builds the preference window and connects every control outlet. The caller
// owns the returned window through -[NSWindowController setWindow:].
- (NSWindow *)buildPreferenceWindow;

@end
