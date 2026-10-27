//
//  MenuMeterWorkarounds.m
//
//	Various workarounds for old OS bugs that may not be applicable
//  (or compilable) on newer OS versions. To prevent conflicts
//  everything here is __private_extern__.
//
//	Copyright (c) 2009-2014 Alex Harper
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

#import "MenuMeterWorkarounds.h"

static BOOL SystemVersionCompare(int32_t major, int32_t minor) {
    NSOperatingSystemVersion version = { major, minor, 0 };
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version];
} 

__private_extern__ BOOL OSIsJaguarOrLater(void) {
	return SystemVersionCompare(10, 2);
}

__private_extern__ BOOL OSIsPantherOrLater(void) {
	return SystemVersionCompare(10, 3);
}

__private_extern__ BOOL OSIsTigerOrLater(void) {
	return SystemVersionCompare(10, 4);
}

__private_extern__ BOOL OSIsLeopardOrLater(void) {
	return SystemVersionCompare(10, 5);
}

__private_extern__ BOOL OSIsSnowLeopardOrLater(void) {
	return SystemVersionCompare(10, 6);
}

__private_extern__ BOOL OSIsMavericksOrLater(void) {
	return SystemVersionCompare(10, 9);
}

__private_extern__ void LiveUpdateMenuItemTitle(NSMenu *menu, CFIndex index, NSString *title) {
    LiveUpdateMenuItemTitleAndVisibility(menu, index, title, NO);
}

__private_extern__ void LiveUpdateMenuItemTitleAndVisibility(NSMenu *menu, CFIndex index, NSString *title, BOOL hidden) {

	// Guard against < 1 based values (such as the output of [NSMenu indexOfItem:]
	// when the item is not found.
	if (index < 0 || index >= menu.numberOfItems) return;

    if (title)
        [[menu itemAtIndex:index] setTitle:title];
    [[menu itemAtIndex:index] setHidden:hidden];

} // LiveUpdateMenuItemTitle

__private_extern__ void LiveUpdateMenu(NSMenu *menu) {
	// Modern AppKit keeps NSMenu in sync automatically. Kept for source
	// compatibility with older call sites.
	(void)menu;
} // LiveUpdateMenu

