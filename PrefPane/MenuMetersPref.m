//
//  MenuMetersPrefPane.m
//
//	MenuMeters pref panel
//
//	Copyright (c) 2002-2014 Alex Harper
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

#import "MenuMetersPref.h"
#import "MenuMetersPrefWindow.h"
#import "EMCLoginItem.h"
#import "MenuMeterCPUExtra.h"
#import "MenuMeterDiskExtra.h"
#import "MenuMeterMemExtra.h"
#import "MenuMeterNetExtra.h"
#import "TemperatureReader.h"
#import <ApplicationServices/ApplicationServices.h>
///////////////////////////////////////////////////////////////
//
//	Private methods and constants
//
///////////////////////////////////////////////////////////////

@interface MenuMetersPref (PrivateMethods)
// Notifications
- (void)menuExtraUnloaded:(NSNotification *)notification;
- (void)menuExtraChangedPrefs:(NSNotification *)notification;

// Menu extra manipulations
- (void)loadExtraAtURL:(NSURL *)extraURL withID:(NSString *)bundleID;
- (BOOL)isExtraWithBundleIDLoaded:(NSString *)bundleID;
- (void)removeExtraWithBundleID:(NSString *)bundleID;
- (void)showMenuExtraErrorSheet;

// Net configuration update
- (void)updateNetInterfaceMenu;

// CPU info
- (BOOL)isMultiProcessor;

// System config framework
- (void)connectSystemConfig;
- (void)disconnectSystemConfig;
- (NSDictionary *)sysconfigValueForKey:(NSString *)key;

@end

// MenuCracker
#define kMenuCrackerURL				[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuCracker" ofType:@"menu" inDirectory:@""]]

// Paths to the menu extras
#ifdef ELCAPITAN
#define kCPUMenuURL nil
#define kDiskMenuURL nil
#define kMemMenuURL nil
#define kNetMenuURL nil
#else
#define kCPUMenuURL					[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuMeterCPU" ofType:@"menu" inDirectory:@""]]
#define kDiskMenuURL				[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuMeterDisk" ofType:@"menu" inDirectory:@""]]
#define kMemMenuURL					[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuMeterMem" ofType:@"menu" inDirectory:@""]]
#define kNetMenuURL					[NSURL fileURLWithPath:[[self bundle] pathForResource:@"MenuMeterNet" ofType:@"menu" inDirectory:@""]]
#endif

// How long to wait for Extras to add once CoreMenuExtraAddMenuExtra returns?
#define kWaitForExtraLoadMicroSec		10000000
#define kWaitForExtraLoadStepMicroSec	250000

// Mem panel hidden tabs for color controls
enum {
	kMemActiveWiredInactiveColorTab = 0,
	kMemUsedFreeColorTab
};

///////////////////////////////////////////////////////////////
//
//	SystemConfiguration notification callbacks
//
///////////////////////////////////////////////////////////////

static void scChangeCallback(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info) {

	if (info) [(__bridge MenuMetersPref *)info updateNetInterfaceMenu];

} // scChangeCallback

@implementation MenuMetersPref
{
#ifdef SPARKLE
    SPUUpdater *updater;
#endif
}
-(IBAction)showAlertConcerningSystemEventsEtc:(id)sender
{
    NSButton *button = sender;
    BOOL enabled = (button.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"activityMonitorOpenSpecificPanes"];
    if (enabled) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"MenuMeters needs Accessibility permission";
        [alert addButtonWithTitle:@"OK"];
        alert.informativeText = @"To switch to a specific Activity Monitor pane, MenuMeters simulates a click on the pane's toolbar button. macOS will ask you to allow MenuMeters to control your computer using Accessibility features. You can change this later in System Settings > Privacy & Security > Accessibility.";
        [alert runModal];

        // Ask for Accessibility access the first time the feature is enabled.
        // The call is harmless when access has already been granted.
        NSDictionary *options = @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES };
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }
}
-(IBAction)openAbout:(id)sender
{
    [prefTabs selectTabViewItemAtIndex:4];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:self];
}
-(void)openPrefPane:(NSNotification*)notification
{
    id obj=notification.object;
    if([obj isKindOfClass:[MenuMeterCPUExtra class]]){
        [prefTabs selectTabViewItemAtIndex:0];
    }
    if([obj isKindOfClass:[MenuMeterDiskExtra class]]){
        [prefTabs selectTabViewItemAtIndex:1];
    }
    if([obj isKindOfClass:[MenuMeterMemExtra class]]){
        [prefTabs selectTabViewItemAtIndex:2];
    }
    if([obj isKindOfClass:[MenuMeterNetExtra class]]){
        [prefTabs selectTabViewItemAtIndex:3];
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:self];
}
-(BOOL)noMenuMeterLoaded
{
    return ![self isExtraWithBundleIDLoaded:kCPUMenuBundleID] &&
    ![self isExtraWithBundleIDLoaded:kDiskMenuBundleID] &&
    ![self isExtraWithBundleIDLoaded:kMemMenuBundleID] &&
    ![self isExtraWithBundleIDLoaded:kNetMenuBundleID];
}
-(void)setupAboutTab:(NSString*)about
{
    NSString*pathToRTF=[[NSBundle mainBundle] pathForResource:about ofType:@"rtf"];
    NSMutableAttributedString*x=[[NSMutableAttributedString alloc] initWithURL:[NSURL fileURLWithPath:pathToRTF] options:@{} documentAttributes:nil error:nil];
    [x addAttribute:NSForegroundColorAttributeName value:[NSColor textColor] range:NSMakeRange(0, x.length)];
    [aboutView.textStorage appendAttributedString:x];
	aboutView.textContainerInset = NSMakeSize(12, 8);
}
-(void)initCommon:(NSString*)about
{
    [self mainViewDidLoad];
    [self willSelect];
    [self setupAboutTab:about];
    if([self noMenuMeterLoaded]){
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [self.window makeKeyAndOrderFront:self];
    }
    [self setupSparkleUI];

#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101600)
	if (@available(macOS 10.16, *)) {
		NSToolbar *toolbar = [NSToolbar new];
		toolbar.delegate = self;
		self.window.toolbar = toolbar;
		self.window.toolbarStyle = NSWindowToolbarStylePreference;

		prefTabs.tabViewType = NSNoTabsNoBorder;
		NSString *selectedIdentifier = prefTabs.selectedTabViewItem.identifier;
		[self.window.toolbar setSelectedItemIdentifier:selectedIdentifier];
		prefTabs.delegate = self;
	}
#endif
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
	NSMutableArray *items = [NSMutableArray new];
	for (NSTabViewItem *tabItem in prefTabs.tabViewItems) {
		NSString *identifier = tabItem.identifier;
		[items addObject:identifier];
	}
	return items;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
	return [self toolbarDefaultItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdent willBeInsertedIntoToolbar:(BOOL)willBeInserted {
	NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdent];
	NSUInteger tabIdx = [prefTabs indexOfTabViewItemWithIdentifier:itemIdent];
	NSTabViewItem *tabItem = [prefTabs tabViewItemAtIndex:tabIdx];
	item.paletteLabel = tabItem.label;
	item.label = tabItem.label;
	item.action = @selector(toolbarSelection:);
#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 101600)
	if (@available(macOS 10.16, *)) {
		item.image = [NSImage imageWithSystemSymbolName:itemIdent accessibilityDescription:@""];
	}
#endif
	return item;
}

- (IBAction)toolbarSelection:(id)sender {
	NSString *itemIdent = [(NSToolbarItem*)sender itemIdentifier];
	NSUInteger tabIdx = [prefTabs indexOfTabViewItemWithIdentifier:itemIdent];
	NSTabViewItem *tabItem = [prefTabs tabViewItemAtIndex:tabIdx];
	[prefTabs selectTabViewItem:tabItem];
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	NSString *itemIdent = [tabViewItem identifier];
	[self.window.toolbar setSelectedItemIdentifier:itemIdent];
}
-(void)hiddenBySystem:(NSNotification*)notification
{
    NSRunningApplication*app=[[NSWorkspace sharedWorkspace] frontmostApplication];
    if([app.bundleIdentifier isEqualToString:[NSBundle mainBundle].bundleIdentifier])
        return;
    NSArray*array=[[NSUserDefaults standardUserDefaults] objectForKey:@"hiddenArray"];
    if(!array){
        array=[NSArray array];
    }
    if([array containsObject:app.bundleIdentifier]){
        return;
    }
    if(!hiddenAlertIsShown && !(self.window.visible)){
        NSAlert*hiddenAlert=[[NSAlert alloc] init];
        hiddenAlert.alertStyle=NSAlertStyleCritical;
        hiddenAlert.messageText=@"MenuMeters is hidden due to lack of space";
        NSString*frontAppName=app.localizedName;
        hiddenAlert.informativeText=[NSString stringWithFormat:@"It might be hidden because %@ has a long list of menus, or your MacBook has a notch.\nTry reducing the number of CPU cores shown, etc.",frontAppName];
        [hiddenAlert addButtonWithTitle:NSLocalizedString(kOpenMenuMetersPref, kOpenMenuMetersPref)];
        [hiddenAlert addButtonWithTitle:[NSString stringWithFormat:@"Ignore this issue when the frontmost app is %@",frontAppName]];
        hiddenAlertIsShown=YES;
        NSModalResponse response=[hiddenAlert runModal];
        if(response==NSAlertFirstButtonReturn){
            [self.window makeKeyAndOrderFront:self];
        }else{
            NSMutableArray*m=[array mutableCopy];
            [m addObject:app.bundleIdentifier];
            [[NSUserDefaults standardUserDefaults] setObject:m forKey:@"hiddenArray"];
        }
        hiddenAlertIsShown=NO;
    }
    
}
- (instancetype)initWithAboutFileName:(NSString *)about updater:(id)updater_
{
    self = [super initWithWindow:nil];
    if (self) {
#ifdef SPARKLE
        updater = updater_;
#endif
        [self buildPreferenceWindow];
        [self initCommon:about];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(openPrefPane:) name:@"openPref" object:nil];
#ifdef SPARKLE
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hiddenBySystem:) name:@"hiddenBySystem" object:nil];
#endif
    }
    return self;
}

#ifdef SPARKLE
-(instancetype)initWithAboutFileName:(NSString*)about andUpdater:(SPUUpdater*)updater_
{
    return [self initWithAboutFileName:about updater:updater_];
}
#else
-(instancetype)initWithAboutFileName:(NSString*)about
{
    return [self initWithAboutFileName:about updater:nil];
}
#endif
-(NSView*)mainView{
    return self.window.contentView;
}
-(NSBundle*)bundle{
    return [NSBundle mainBundle];
}
-(void)windowWillClose:(NSNotification *)notification
{
    if(![self noMenuMeterLoaded]){
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }
}
-(void)setupSparkleUI
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    tintPercentageSlider.floatValue = [defaults floatForKey:@"tintPercentage"];
    activityMonitorPaneCheckbox.state = [defaults boolForKey:@"activityMonitorOpenSpecificPanes"] ? NSControlStateValueOn : NSControlStateValueOff;

    // This is hacky, but if we're a Sparkle build this sets up the updater UI bits,
    // and if we're not, just hide them. The colour tint and Activity Monitor
    // controls are not Sparkle-specific, so they stay visible in both builds.
#ifdef SPARKLE
    if(updater.automaticallyChecksForUpdates){
        NSTimeInterval updateInterval=updater.updateCheckInterval;
        if(updateInterval<3600*24+1){
            [updateIntervalButton selectItemAtIndex:1];
        }else if(updateInterval<7*3600*24+1){
            [updateIntervalButton selectItemAtIndex:2];
        }else if(updateInterval<30*3600*24+1){
            [updateIntervalButton selectItemAtIndex:3];
        }else{
            [updateIntervalButton selectItemAtIndex:1];
        }
    }else{
        [updateIntervalButton selectItemAtIndex:0];
    }
#else
    updateIntervalLabel.hidden = YES;
    updateIntervalButton.hidden = YES;
    checkUpdatesButton.hidden = YES;
#endif
}
-(IBAction)updateInterval:(id)sender
{
#ifdef SPARKLE
    NSPopUpButton*button=sender;
    NSInteger intervalInDays=1;
    switch(button.indexOfSelectedItem){
        case 0:
            intervalInDays=-1;
            break;
        case 1:
            intervalInDays=1;
            break;
        case 2:
            intervalInDays=7;
            break;
        case 3:
            intervalInDays=30;
            break;
        default:
            intervalInDays=1;
            break;
    }
    if(intervalInDays<=0){
        [updater setAutomaticallyChecksForUpdates:NO];
    }else{
        [updater setAutomaticallyChecksForUpdates:YES];
        [updater setUpdateCheckInterval:intervalInDays*3600*24];
    }
#endif
}
-(IBAction)tintPercentageChanged:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setFloat:tintPercentageSlider.floatValue
                                             forKey:@"tintPercentage"];
}
///////////////////////////////////////////////////////////////
//
//    Pref pane standard methods
//
///////////////////////////////////////////////////////////////
- (void)mainViewDidLoad {
	// On first load switch to the first tab
	[prefTabs selectFirstTabViewItem:self];

	// On first load populate the image set menu
	NSEnumerator *diskImageSetEnum = [kDiskImageSets objectEnumerator];
	[diskImageSet removeAllItems];
	NSString *imageSetName = nil;
	while ((imageSetName = [diskImageSetEnum nextObject])) {
		[diskImageSet addItemWithTitle:[[NSBundle bundleForClass:[self class]]
										   localizedStringForKey:imageSetName
														   value:nil
														   table:@"DiskImageSet"]];
	}

	// Set up a NSFormatter for use printing timers
	NSNumberFormatter *intervalFormatter = [[NSNumberFormatter alloc] init];
	intervalFormatter.localizesFormat = YES;
	intervalFormatter.format = @"###0.0\u2009s";
	// Now set the formatters
	[cpuIntervalDisplay setFormatter:intervalFormatter];
	[diskIntervalDisplay setFormatter:intervalFormatter];
	[netIntervalDisplay setFormatter:intervalFormatter];

	// The scale menu used to have images but they have been long gone
    // when the app is moved outside of System Preferences
    // because I forgot to include the image files in the new target.
    // Now they are eliminated from the code too ...
    
    {
    NSString*oldAppPath=[@"~/Library/PreferencePanes/MenuMeters.prefPane/Contents/Resources/MenuMetersApp.app" stringByExpandingTildeInPath];
        EMCLoginItem*oldItem=[EMCLoginItem loginItemWithPath:oldAppPath];
        if(oldItem.isLoginItem){
            [oldItem removeLoginItem];
        }
    }
    {
        NSString*oldAppPath=@"/Library/PreferencePanes/MenuMeters.prefPane/Contents/Resources/MenuMetersApp.app";
            EMCLoginItem*oldItem=[EMCLoginItem loginItemWithPath:oldAppPath];
            if(oldItem.isLoginItem){
                [oldItem removeLoginItem];
            }
    }
    system("killall MenuMetersApp");
    {
        EMCLoginItem*thisItem=[EMCLoginItem loginItemWithBundle:[NSBundle mainBundle]];
        if(!thisItem.isLoginItem){
            [thisItem addLoginItem];
        }
    }
} // mainViewDidLoad

- (void)updateTemperatureSensors
{
    NSArray*sensorNames=[TemperatureReader sensorNames];
    if(!sensorNames){
        cpuTemperatureSensor.enabled=NO;
        return;
    }
    NSMenu*menu=[cpuTemperatureSensor menu];
    for(NSString*name in sensorNames){
        NSString*displayName=[TemperatureReader displayNameForSensor:name];
        NSMenuItem*item=[menu addItemWithTitle:displayName action:nil keyEquivalent:@""];
        item.toolTip=name;
    }
    NSString*sensor=[ourPrefs cpuTemperatureSensor];
    if([sensor isEqualTo:kCPUTemperatureSensorDefault]){
        sensor=[TemperatureReader defaultSensor];
    }
    NSMenuItem*item=[menu itemWithTitle:[TemperatureReader displayNameForSensor:sensor]];
    if(!item){
        // This means that it is the first launch after migrating to a new Mac with a different set of sensors.
        [ourPrefs saveCpuTemperatureSensor:kCPUTemperatureSensorDefault];
        sensor=[TemperatureReader defaultSensor];
        item=[menu itemWithTitle:[TemperatureReader displayNameForSensor:sensor]];
    }
    [cpuTemperatureSensor selectItem:item];
}
- (void)willSelect {

	// Reread prefs on each load
	ourPrefs = [[MenuMeterDefaults alloc] init];

	// On machines without powermate disable the controls
	if ([MenuMeterPowerMate powermateAttached]) {
		[cpuPowerMate setEnabled:YES];
		[cpuPowerMateMode setEnabled:YES];
	} else {
		[cpuPowerMate setEnabled:NO];
		[cpuPowerMateMode setEnabled:NO];
	}

	// Hook up to SystemConfig Framework
	[self connectSystemConfig];

	// Set the switches on each menu toggle
	[cpuMeterToggle setState:([self isExtraWithBundleIDLoaded:kCPUMenuBundleID] ? NSControlStateValueOn : NSControlStateValueOff)];
	[diskMeterToggle setState:([self isExtraWithBundleIDLoaded:kDiskMenuBundleID] ? NSControlStateValueOn : NSControlStateValueOff)];
	[memMeterToggle setState:([self isExtraWithBundleIDLoaded:kMemMenuBundleID] ? NSControlStateValueOn : NSControlStateValueOff)];
	[netMeterToggle setState:([self isExtraWithBundleIDLoaded:kNetMenuBundleID] ? NSControlStateValueOn : NSControlStateValueOff)];

	// Build the preferred interface menu and select (this actually updates the net prefs too)
	[self updateNetInterfaceMenu];
    
    [self updateTemperatureSensors];
	// Reset the controls to match the prefs
	[self menuExtraChangedPrefs:nil];

	// Register for pref change notifications from the extras
	[[NSNotificationCenter defaultCenter] addObserver:self
														selector:@selector(menuExtraChangedPrefs:)
															name:kPrefPaneBundleID
														  object:kPrefChangeNotification];

	// Register for notifications from the extras when they unload
	[[NSNotificationCenter defaultCenter] addObserver:self
														selector:@selector(menuExtraUnloaded:)
															name:@"menuExtraUnloaded"
														  object:nil];
} // willSelect

- (void)didUnselect {

	// Unregister all notifications
	[[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:nil];

	// Unhook from SystemConfig Framework
	[self disconnectSystemConfig];

	// Release prefs so it can reconnect next load
	ourPrefs = nil;

} // didUnselect

///////////////////////////////////////////////////////////////
//
//	Notifications
//
///////////////////////////////////////////////////////////////

- (void)menuExtraUnloaded:(NSNotification *)notification {

	NSString *bundleID = [notification object];
	if (bundleID) {
		if ([bundleID isEqualToString:kCPUMenuBundleID]) {
			[cpuMeterToggle setState:NSControlStateValueOff];
		} else if ([bundleID isEqualToString:kDiskMenuBundleID]) {
			[diskMeterToggle setState:NSControlStateValueOff];
		} else if ([bundleID isEqualToString:kMemMenuBundleID]) {
			[memMeterToggle setState:NSControlStateValueOff];
		} else if ([bundleID isEqualToString:kNetMenuBundleID]) {
			[netMeterToggle setState:NSControlStateValueOff];
		}
	}
    [self removeExtraWithBundleID:bundleID];
} // menuExtraUnloaded

- (void)menuExtraChangedPrefs:(NSNotification *)notification {

	if (ourPrefs) {
		[self cpuPrefChange:nil];
		[self diskPrefChange:nil];
		[self memPrefChange:nil];
		[self netPrefChange:nil];
	}

} // menuExtraChangedDefaults

///////////////////////////////////////////////////////////////
//
//	IB Targets
//
///////////////////////////////////////////////////////////////

- (IBAction)liveUpdateInterval:(id)sender {

	// Clever solution to live updating by exploiting the difference between
	// UI tracking and default runloop mode. See
	// http://www.cocoabuilder.com/archive/message/cocoa/2008/10/17/220399
	if (sender == cpuInterval) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(cpuPrefChange:)
													object:cpuInterval];
		[self performSelector:@selector(cpuPrefChange:)
				   withObject:cpuInterval
				   afterDelay:0.0];
		[cpuIntervalDisplay takeDoubleValueFrom:cpuInterval];
	} else if (sender == diskInterval) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(diskPrefChange:)
												   object:diskInterval];
		[self performSelector:@selector(diskPrefChange:)
				   withObject:diskInterval
				   afterDelay:0.0];
		[diskIntervalDisplay takeDoubleValueFrom:diskInterval];
	} else if (sender == memInterval) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(memPrefChange:)
												   object:memInterval];
		[self performSelector:@selector(memPrefChange:)
				   withObject:memInterval
				   afterDelay:0.0];
		[memIntervalDisplay takeDoubleValueFrom:memInterval];
	} else if (sender == netInterval) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
												 selector:@selector(netPrefChange:)
												   object:netInterval];
		[self performSelector:@selector(netPrefChange:)
				   withObject:netInterval
				   afterDelay:0.0];
		[netIntervalDisplay takeDoubleValueFrom:netInterval];
	}

} // liveUpdateInterval:

-(int)cpuDisplayMode
{
    int r=0;
    if([cpuPercentage state]==NSControlStateValueOn)
        r|=kCPUDisplayPercent;
    if([cpuGraph state]==NSControlStateValueOn)
        r|=kCPUDisplayGraph;
    if([cpuThermometer state]==NSControlStateValueOn)
        r|=kCPUDisplayThermometer;
    if([cpuHorizontalThermometer state]==NSControlStateValueOn)
        r|=kCPUDisplayHorizontalThermometer;
    return r;
}
- (IBAction)cpuPrefChange:(id)sender {

	// Extra load handler
	if (([cpuMeterToggle state] == NSControlStateValueOn) && ![self isExtraWithBundleIDLoaded:kCPUMenuBundleID]) {
		[self loadExtraAtURL:kCPUMenuURL withID:kCPUMenuBundleID];
	} else if (([cpuMeterToggle state] == NSControlStateValueOff) && [self isExtraWithBundleIDLoaded:kCPUMenuBundleID]) {
		[self removeExtraWithBundleID:kCPUMenuBundleID];
	}
	[cpuMeterToggle setState:([self isExtraWithBundleIDLoaded:kCPUMenuBundleID] ? NSControlStateValueOn : NSControlStateValueOff)];

	// Save changes
    if (sender == cpuPercentage
        || sender == cpuGraph
        || sender == cpuThermometer
        || sender == cpuHorizontalThermometer) {
		[ourPrefs saveCpuDisplayMode:[self cpuDisplayMode]];
    } else if (sender == cpuTemperatureToggle) {
        bool show = ([cpuTemperatureToggle state] == NSControlStateValueOn) ? YES : NO;
        [ourPrefs saveCpuTemperature:show];
   } else if (sender == cpuTemperatureUnit) {
       [ourPrefs saveCpuTemperatureUnit:(int)[cpuTemperatureUnit indexOfSelectedItem]];
   } else if (sender==cpuTemperatureSensor){
       NSString*sensor=[cpuTemperatureSensor selectedItem].toolTip;
       if([sensor isEqualToString:[TemperatureReader defaultSensor]]){
           sensor=kCPUTemperatureSensorDefault;
       }
       [ourPrefs saveCpuTemperatureSensor:sensor];
    } else if (sender == cpuInterval) {
		[ourPrefs saveCpuInterval:[cpuInterval doubleValue]];
	} else if (sender == cpuPercentMode) {
		[ourPrefs saveCpuPercentDisplay:(int)[cpuPercentMode indexOfSelectedItem]];
    } else if (sender == cpuMaxProcessCount) {
        [ourPrefs saveCpuMaxProcessCount:(int)[cpuMaxProcessCount intValue]];
	} else if (sender == cpuGraphWidth) {
		[ourPrefs saveCpuGraphLength:[cpuGraphWidth intValue]];
    } else if (sender == cpuHorizontalRows) {
        [ourPrefs saveCpuHorizontalRows:[cpuHorizontalRows intValue]];
    } else if (sender == cpuMenuWidth) {
        [ourPrefs saveCpuMenuWidth:[cpuMenuWidth intValue]];
    } else if (sender == cpuMultipleCPU) {
        switch([cpuMultipleCPU indexOfSelectedItem]){
            case 0:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:NO];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            case 1:
                [ourPrefs saveCpuAvgLowerHalfProcs:YES];
                [ourPrefs saveCpuAvgAllProcs:NO];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            case 2:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:YES];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            case 3:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:YES];
                [ourPrefs saveCpuSumAllProcsPercent:YES];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            case 4:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:NO];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:YES];
                break;
            default:
                [ourPrefs saveCpuAvgLowerHalfProcs:NO];
                [ourPrefs saveCpuAvgAllProcs:NO];
                [ourPrefs saveCpuSumAllProcsPercent:NO];
                [ourPrefs saveCpuSortByUsage:NO];
                break;
            }
	} else if (sender == cpuPowerMate) {
		[ourPrefs saveCpuPowerMate:(([cpuPowerMate state] == NSControlStateValueOn) ? YES : NO)];
	} else if (sender == cpuPowerMateMode) {
		[ourPrefs saveCpuPowerMateMode:(int)[cpuPowerMateMode indexOfSelectedItem]];
	} else if (sender == cpuUserColor) {
		[ourPrefs saveCpuUserColor:[cpuUserColor color]];
	} else if (sender == cpuSystemColor) {
		[ourPrefs saveCpuSystemColor:[cpuSystemColor color]];
        } else if (sender == cpuTemperatureColor) {
                [ourPrefs saveCpuTemperatureColor:[cpuTemperatureColor color]];
	} else if (!sender) {
		// On first load handle multiprocs options
		if (![self isMultiProcessor]) {
			[ourPrefs saveCpuAvgAllProcs:NO];
			[ourPrefs saveCpuSumAllProcsPercent:NO];
		}
	}

	// Update controls
        [cpuPercentage setState:([ourPrefs cpuDisplayMode]&kCPUDisplayPercent)?NSControlStateValueOn:NSControlStateValueOff];
        [cpuGraph setState:([ourPrefs cpuDisplayMode]&kCPUDisplayGraph)?NSControlStateValueOn:NSControlStateValueOff];
        [cpuThermometer setState:([ourPrefs cpuDisplayMode]&kCPUDisplayThermometer)?NSControlStateValueOn:NSControlStateValueOff];
        [cpuHorizontalThermometer setState:([ourPrefs cpuDisplayMode]&kCPUDisplayHorizontalThermometer)?NSControlStateValueOn:NSControlStateValueOff];
    if([cpuHorizontalThermometer state]==NSControlStateValueOn){
        [cpuPercentage setEnabled:NO];
        [cpuGraph setEnabled:NO];
        [cpuThermometer setEnabled:NO];
    }else{
        [cpuPercentage setEnabled:YES];
        [cpuGraph setEnabled:YES];
        [cpuThermometer setEnabled:YES];
    }
    [cpuTemperatureToggle setState:[ourPrefs cpuShowTemperature]];
        [cpuTemperatureUnit selectItemAtIndex:[ourPrefs cpuTemperatureUnit]];
	[cpuInterval setDoubleValue:[ourPrefs cpuInterval]];
	[cpuPercentMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[cpuPercentMode selectItemAtIndex:[ourPrefs cpuPercentDisplay]];
    [cpuMaxProcessCount setIntValue:[ourPrefs cpuMaxProcessCount]];
    [cpuMaxProcessCountCountLabel setStringValue:[NSString stringWithFormat:NSLocalizedString(@"(%d)", @"DO NOT LOCALIZE!!!"),
                                                  (short)[ourPrefs cpuMaxProcessCount]]];
	[cpuGraphWidth setIntValue:[ourPrefs cpuGraphLength]];
    [cpuHorizontalRows setIntValue:[ourPrefs cpuHorizontalRows]];
    [cpuMenuWidth setIntValue:[ourPrefs cpuMenuWidth]];
    if([ourPrefs cpuSortByUsage]){
        [cpuMultipleCPU selectItemAtIndex:4];
    }else if([ourPrefs cpuSumAllProcsPercent]){
        [cpuMultipleCPU selectItemAtIndex:3];
    }else if([ourPrefs cpuAvgAllProcs]){
        [cpuMultipleCPU selectItemAtIndex:2];
    }else if([ourPrefs cpuAvgLowerHalfProcs]){
        [cpuMultipleCPU selectItemAtIndex:1];
    }else{
        [cpuMultipleCPU selectItemAtIndex:0];
    }
	[cpuPowerMate setState:([ourPrefs cpuPowerMate] ? NSControlStateValueOn : NSControlStateValueOff)];
	[cpuPowerMateMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[cpuPowerMateMode selectItemAtIndex:[ourPrefs cpuPowerMateMode]];
	[cpuUserColor setColor:[ourPrefs cpuUserColor]];
	[cpuSystemColor setColor:[ourPrefs cpuSystemColor]];
        [cpuTemperatureColor setColor:[ourPrefs cpuTemperatureColor]];
	[cpuIntervalDisplay takeDoubleValueFrom:cpuInterval];

/*	if ([cpuPercentage state]==NSControlStateValueOn) {
		[cpuPercentMode setEnabled:YES];
		[cpuPercentModeLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[cpuPercentMode setEnabled:NO];
        [cpuPercentModeLabel setTextColor:[NSColor disabledControlTextColor]];
	}
 */
	if ([cpuGraph state]==NSControlStateValueOn) {
		[cpuGraphWidth setEnabled:YES];
		[cpuGraphWidthLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[cpuGraphWidth setEnabled:NO];
		[cpuGraphWidthLabel setTextColor:[NSColor disabledControlTextColor]];
	}
    if ([cpuHorizontalThermometer state]==NSControlStateValueOn) {
		[cpuHorizontalRows setEnabled:YES];
		[cpuHorizontalRowsLabel setTextColor:[NSColor controlTextColor]];
        [cpuMenuWidth setEnabled:YES];
        [cpuMenuWidthLabel setTextColor:[NSColor controlTextColor]];
    }
    else {
		[cpuHorizontalRows setEnabled:NO];
		[cpuHorizontalRowsLabel setTextColor:[NSColor disabledControlTextColor]];
		[cpuMenuWidth setEnabled:NO];
		[cpuMenuWidthLabel setTextColor:[NSColor disabledControlTextColor]];
    }
/*	if ((([cpuDisplayMode indexOfSelectedItem] + 1) & (kCPUDisplayGraph | kCPUDisplayThermometer | kCPUDisplayHorizontalThermometer)) ||
		((([cpuDisplayMode indexOfSelectedItem] + 1) & kCPUDisplayPercent) &&
			([cpuPercentMode indexOfSelectedItem] == kCPUPercentDisplaySplit))) {*/
		[cpuUserColor setEnabled:YES];
		[cpuSystemColor setEnabled:YES];
		[cpuUserColorLabel setTextColor:[NSColor controlTextColor]];
		[cpuSystemColorLabel setTextColor:[NSColor controlTextColor]];
/*	} else {
		[cpuUserColor setEnabled:NO];
		[cpuSystemColor setEnabled:NO];
		[cpuUserColorLabel setTextColor:[NSColor disabledControlTextColor]];
		[cpuSystemColorLabel setTextColor:[NSColor disabledControlTextColor]];
	}*/

	// Notify
	if ([self isExtraWithBundleIDLoaded:kCPUMenuBundleID]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kCPUMenuBundleID
																	   object:kPrefChangeNotification
                 userInfo:nil];
	}

} // cpuPrefChange

- (IBAction)diskPrefChange:(id)sender {

	// Extra load
	if (([diskMeterToggle state] == NSControlStateValueOn) && ![self isExtraWithBundleIDLoaded:kDiskMenuBundleID]) {
		[self loadExtraAtURL:kDiskMenuURL withID:kDiskMenuBundleID];
	} else if (([diskMeterToggle state] == NSControlStateValueOff) && [self isExtraWithBundleIDLoaded:kDiskMenuBundleID]) {
		[self removeExtraWithBundleID:kDiskMenuBundleID];
	}
	[diskMeterToggle setState:([self isExtraWithBundleIDLoaded:kDiskMenuBundleID] ? NSControlStateValueOn : NSControlStateValueOff)];

	// Save changes
	if (sender == diskImageSet) {
		[ourPrefs saveDiskImageset:(int)[diskImageSet indexOfSelectedItem]];
	} else if (sender == diskInterval) {
		[ourPrefs saveDiskInterval:[diskInterval doubleValue]];
	} else if (sender == diskSelectMode) {
		[ourPrefs saveDiskSelectMode:(int)[diskSelectMode indexOfSelectedItem]];
	}

	// Update controls
	[diskImageSet selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[diskImageSet selectItemAtIndex:[ourPrefs diskImageset]];
	[diskInterval setDoubleValue:[ourPrefs diskInterval]];
	[diskIntervalDisplay takeDoubleValueFrom:diskInterval];
	[diskSelectMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[diskSelectMode selectItemAtIndex:[ourPrefs diskSelectMode]];

	// Notify
	if ([self isExtraWithBundleIDLoaded:kDiskMenuBundleID]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kDiskMenuBundleID
																	   object:kPrefChangeNotification
                 userInfo:nil];
	}

} // diskPrefChange

- (IBAction)memPrefChange:(id)sender {

	// Extra load
	if (([memMeterToggle state] == NSControlStateValueOn) && ![self isExtraWithBundleIDLoaded:kMemMenuBundleID]) {
		[self loadExtraAtURL:kMemMenuURL withID:kMemMenuBundleID];
	} else if (([memMeterToggle state] == NSControlStateValueOff) && [self isExtraWithBundleIDLoaded:kMemMenuBundleID]) {
		[self removeExtraWithBundleID:kMemMenuBundleID];
	}
	[memMeterToggle setState:([self isExtraWithBundleIDLoaded:kMemMenuBundleID] ? NSControlStateValueOn : NSControlStateValueOff)];

	// Save changes
	if (sender == memDisplayMode) {
		[ourPrefs saveMemDisplayMode:(int)[memDisplayMode indexOfSelectedItem] + 1];
	} else if (sender == memInterval) {
		[ourPrefs saveMemInterval:[memInterval doubleValue]];
	} else if (sender == memFreeUsedLabeling) {
		[ourPrefs saveMemUsedFreeLabel:(([memFreeUsedLabeling state] == NSControlStateValueOn) ? YES : NO)];
	} else if (sender == memPageIndicator) {
		[ourPrefs saveMemPageIndicator:(([memPageIndicator state] == NSControlStateValueOn) ? YES : NO)];
    } else if (sender == memPressureMode) {
        [ourPrefs saveMemPressure:(([memPressureMode state] == NSControlStateValueOn) ? YES : NO)];
	} else if (sender == memGraphWidth) {
		[ourPrefs saveMemGraphLength:[memGraphWidth intValue]];
	} else if (sender == memActiveColor) {
		[ourPrefs saveMemActiveColor:[memActiveColor color]];
	} else if (sender == memInactiveColor) {
		[ourPrefs saveMemInactiveColor:[memInactiveColor color]];
	} else if (sender == memWiredColor) {
		[ourPrefs saveMemWireColor:[memWiredColor color]];
	} else if (sender == memCompressedColor) {
		[ourPrefs saveMemCompressedColor:[memCompressedColor color]];
	} else if (sender == memFreeColor) {
		[ourPrefs saveMemFreeColor:[memFreeColor color]];
	} else if (sender == memUsedColor) {
		[ourPrefs saveMemUsedColor:[memUsedColor color]];
	} else if (sender == memPageinColor) {
		[ourPrefs saveMemPageInColor:[memPageinColor color]];
	} else if (sender == memPageoutColor) {
		[ourPrefs saveMemPageOutColor:[memPageoutColor color]];
	}
	
	// Update controls
	[memDisplayMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[memDisplayMode selectItemAtIndex:[ourPrefs memDisplayMode] - 1];
	[memInterval setDoubleValue:[ourPrefs memInterval]];
	[memFreeUsedLabeling setState:([ourPrefs memUsedFreeLabel] ? NSControlStateValueOn : NSControlStateValueOff)];
	[memPageIndicator setState:([ourPrefs memPageIndicator] ? NSControlStateValueOn : NSControlStateValueOff)];
    [memPressureMode setState:([ourPrefs memPressure] ? NSControlStateValueOn : NSControlStateValueOff)];
	[memGraphWidth setIntValue:[ourPrefs memGraphLength]];
	[memActiveColor setColor:[ourPrefs memActiveColor]];
	[memInactiveColor setColor:[ourPrefs memInactiveColor]];
	[memWiredColor setColor:[ourPrefs memWireColor]];
	[memCompressedColor setColor:[ourPrefs memCompressedColor]];
	[memFreeColor setColor:[ourPrefs memFreeColor]];
	[memUsedColor setColor:[ourPrefs memUsedColor]];
	[memPageinColor setColor:[ourPrefs memPageInColor]];
	[memPageoutColor setColor:[ourPrefs memPageOutColor]];
	[memIntervalDisplay takeIntValueFrom:memInterval];

	// Disable controls as needed
	if ((([memDisplayMode indexOfSelectedItem] + 1) == kMemDisplayPie) ||
		(([memDisplayMode indexOfSelectedItem] + 1) == kMemDisplayBar) ||
		(([memDisplayMode indexOfSelectedItem] + 1) == kMemDisplayGraph)) {
		[memFreeUsedLabeling setEnabled:NO];
	} else {
		[memFreeUsedLabeling setEnabled:YES];
	}
	if (([memDisplayMode indexOfSelectedItem] + 1) == kMemDisplayGraph) {
		[memGraphWidth setEnabled:YES];
		[memGraphWidthLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[memGraphWidth setEnabled:NO];
		[memGraphWidthLabel setTextColor:[NSColor disabledControlTextColor]];
	}
	if ([memPageIndicator state] == NSControlStateValueOn) {
		[memPageinColorLabel setTextColor:[NSColor controlTextColor]];
		[memPageoutColorLabel setTextColor:[NSColor controlTextColor]];
		[memPageinColor setEnabled:YES];
		[memPageoutColor setEnabled:YES];
	} else {
		[memPageinColorLabel setTextColor:[NSColor disabledControlTextColor]];
		[memPageoutColorLabel setTextColor:[NSColor disabledControlTextColor]];
		[memPageinColor setEnabled:NO];
		[memPageoutColor setEnabled:NO];
	}
/*    if (([memDisplayMode indexOfSelectedItem] +1) == kMemDisplayBar) {
        [memPressureMode setEnabled:YES];
    }
    else {
        [memPressureMode setEnabled:NO];
    }*/

	// Notify
	if ([self isExtraWithBundleIDLoaded:kMemMenuBundleID]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kMemMenuBundleID
																	   object:kPrefChangeNotification
                 userInfo:nil];
	}

} // memPrefChange

- (IBAction)netPrefChange:(id)sender {

	// Extra load
	if (([netMeterToggle state] == NSControlStateValueOn) && ![self isExtraWithBundleIDLoaded:kNetMenuBundleID]) {
		[self loadExtraAtURL:kNetMenuURL withID:kNetMenuBundleID];
	}
	else if (([netMeterToggle state] == NSControlStateValueOff) && [self isExtraWithBundleIDLoaded:kNetMenuBundleID]) {
		[self removeExtraWithBundleID:kNetMenuBundleID];
	}
	[netMeterToggle setState:([self isExtraWithBundleIDLoaded:kNetMenuBundleID] ? NSControlStateValueOn : NSControlStateValueOff)];

	// Save changes
	if (sender == netDisplayMode) {
		[ourPrefs saveNetDisplayMode:(int)[netDisplayMode indexOfSelectedItem] + 1];
	} else if (sender == netDisplayOrientation) {
		[ourPrefs saveNetDisplayOrientation:(int)[netDisplayOrientation indexOfSelectedItem]];
	} else if (sender == netScaleMode) {
		[ourPrefs saveNetScaleMode:(int)[netScaleMode indexOfSelectedItem]];
	} else if (sender == netScaleCalc) {
		[ourPrefs saveNetScaleCalc:(int)[netScaleCalc indexOfSelectedItem]];
	} else if (sender == netInterval) {
		[ourPrefs saveNetInterval:[netInterval doubleValue]];
	} else if (sender == netThroughputLabeling) {
		[ourPrefs saveNetThroughputLabel:(([netThroughputLabeling state] == NSControlStateValueOn) ? YES : NO)];
	} else if (sender == netThroughput1KBound) {
		[ourPrefs saveNetThroughput1KBound:(([netThroughput1KBound state] == NSControlStateValueOn) ? YES : NO)];
	} else if (sender == netThroughputBits) {
		[ourPrefs saveNetThroughputBits:(([netThroughputBits state] == NSControlStateValueOn) ? YES : NO)];
	} else if (sender == netGraphStyle) {
		[ourPrefs saveNetGraphStyle:(int)[netGraphStyle indexOfSelectedItem]];
	} else if (sender == netGraphWidth) {
		[ourPrefs saveNetGraphLength:[netGraphWidth intValue]];
	} else if (sender == netTxColor) {
		[ourPrefs saveNetTransmitColor:[netTxColor color]];
	} else if (sender == netRxColor) {
		[ourPrefs saveNetReceiveColor:[netRxColor color]];
	} else if (sender == netInactiveColor) {
		[ourPrefs saveNetInactiveColor:[netInactiveColor color]];
	} else if (sender == netPreferInterface) {
		NSMenuItem *menuItem = (NSMenuItem *)[netPreferInterface selectedItem];
		if (menuItem) {
			if (([netPreferInterface indexOfSelectedItem] == 0) || ![menuItem representedObject]) {
				[ourPrefs saveNetPreferInterface:kNetPrimaryInterface];
			} else {
				[ourPrefs saveNetPreferInterface:[menuItem representedObject]];
			}
		}
	}

	// Update controls
	[netDisplayMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netDisplayMode selectItemAtIndex:[ourPrefs netDisplayMode] - 1];
	[netDisplayOrientation selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netDisplayOrientation selectItemAtIndex:[ourPrefs netDisplayOrientation]];
	[netScaleMode selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netScaleMode selectItemAtIndex:[ourPrefs netScaleMode]];
	[netScaleCalc selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netScaleCalc selectItemAtIndex:[ourPrefs netScaleCalc]];
	[netInterval setDoubleValue:[ourPrefs netInterval]];
	[netThroughputLabeling setState:([ourPrefs netThroughputLabel] ? NSControlStateValueOn : NSControlStateValueOff)];
	[netThroughput1KBound setState:([ourPrefs netThroughput1KBound] ? NSControlStateValueOn : NSControlStateValueOff)];
	[netThroughputBits setState:([ourPrefs netThroughputBits] ? NSControlStateValueOn : NSControlStateValueOff)];
	[netGraphStyle selectItemAtIndex:-1]; // Work around multiselects. AppKit problem?
	[netGraphStyle selectItemAtIndex:[ourPrefs netGraphStyle]];
	[netGraphWidth setIntValue:[ourPrefs netGraphLength]];
	[netTxColor setColor:[ourPrefs netTransmitColor]];
	[netRxColor setColor:[ourPrefs netReceiveColor]];
	[netInactiveColor setColor:[ourPrefs netInactiveColor]];
	[netIntervalDisplay takeDoubleValueFrom:netInterval];
	if ([[ourPrefs netPreferInterface] isEqualToString:kNetPrimaryInterface]) {
		[netPreferInterface selectItemAtIndex:0];
	} else {
		BOOL foundBetterItem = NO;
		NSArray *itemsArray = [netPreferInterface itemArray];
		if (itemsArray) {
			NSEnumerator *itemsEnum = [itemsArray objectEnumerator];
			NSMenuItem *menuItem = nil;
			while ((menuItem = [itemsEnum nextObject])) {
				if ([menuItem representedObject]) {
					if ([[ourPrefs netPreferInterface] isEqualToString:[menuItem representedObject]]) {
						[netPreferInterface selectItem:menuItem];
						foundBetterItem = YES;
					}
				}
			}
		}
		if (!foundBetterItem) {
			[netPreferInterface selectItemAtIndex:0];
			[ourPrefs saveNetPreferInterface:kNetPrimaryInterface];
		}
	}

	// Disable controls as needed
	if (([netDisplayMode indexOfSelectedItem] + 1) & kNetDisplayThroughput) {
		[netThroughputLabeling setEnabled:YES];
		[netThroughput1KBound setEnabled:YES];
		[netThroughputBits setEnabled:YES];
	} else {
		[netThroughputLabeling setEnabled:NO];
		[netThroughput1KBound setEnabled:NO];
		[netThroughputBits setEnabled:NO];
	}
	if (([netDisplayMode indexOfSelectedItem] + 1) & kNetDisplayGraph) {
		[netGraphStyle setEnabled:YES];
		[netGraphStyleLabel setTextColor:[NSColor controlTextColor]];
		[netGraphWidth setEnabled:YES];
		[netGraphWidthLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[netGraphStyle setEnabled:NO];
		[netGraphStyleLabel setTextColor:[NSColor disabledControlTextColor]];
		[netGraphWidth setEnabled:NO];
		[netGraphWidthLabel setTextColor:[NSColor disabledControlTextColor]];
	}
	if ((([netDisplayMode indexOfSelectedItem] + 1) & kNetDisplayArrows) ||
		(([netDisplayMode indexOfSelectedItem] + 1) & kNetDisplayGraph)) {
		[netScaleMode setEnabled:YES];
		[netScaleModeLabel setTextColor:[NSColor controlTextColor]];
		[netScaleCalc setEnabled:YES];
		[netScaleCalcLabel setTextColor:[NSColor controlTextColor]];
	} else {
		[netScaleMode setEnabled:NO];
		[netScaleModeLabel setTextColor:[NSColor disabledControlTextColor]];
		[netScaleCalc setEnabled:NO];
		[netScaleCalcLabel setTextColor:[NSColor disabledControlTextColor]];
	}

	// Notify
	if ([self isExtraWithBundleIDLoaded:kNetMenuBundleID]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kNetMenuBundleID
																	   object:kPrefChangeNotification
                 userInfo:nil];
	}

} // netPrefChange

///////////////////////////////////////////////////////////////
//
//	Menu extra manipulations
//
///////////////////////////////////////////////////////////////

- (void)loadExtraAtURL:(NSURL *)extraURL withID:(NSString *)bundleID {
#ifdef ELCAPITAN
    [ourPrefs saveBoolPref:bundleID value:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:bundleID
                                                                   object:kPrefChangeNotification
                                                                 userInfo:nil];
    return;
#else
	// Load the crack. With MenuCracker 2.x multiple loads are allowed, so
	// we don't care if someone else has the MenuCracker 2.x bundle loaded.
	// Plus, since MC 2.x does dodgy things with the load we can't actually
	// find out if its loaded.
	CoreMenuExtraAddMenuExtra((CFURLRef)kMenuCrackerURL, 0, 0, 0, 0, 0);

	// Load actual request
	CoreMenuExtraAddMenuExtra((CFURLRef)extraURL, 0, 0, 0, 0, 0);

	// Wait for the item to load
	int microSlept = 0;
	while (![self isExtraWithBundleIDLoaded:bundleID] && (microSlept < kWaitForExtraLoadMicroSec)) {
		microSlept += kWaitForExtraLoadStepMicroSec;
		usleep(kWaitForExtraLoadStepMicroSec);
	}

	// Try again if needed
	if (![self isExtraWithBundleIDLoaded:bundleID]) {
		microSlept = 0;
		CoreMenuExtraAddMenuExtra((CFURLRef)extraURL, 0, 0, 0, 0, 0);
		while (![self isExtraWithBundleIDLoaded:bundleID] && (microSlept < kWaitForExtraLoadMicroSec)) {
			microSlept += kWaitForExtraLoadStepMicroSec;
			usleep(kWaitForExtraLoadStepMicroSec);
		}
	}

	// Give up
	if (![self isExtraWithBundleIDLoaded:bundleID]) {
		[self showMenuExtraErrorSheet];
	}
#endif
} // loadExtraAtURL:withID:

- (BOOL)isExtraWithBundleIDLoaded:(NSString *)bundleID {
    return [ourPrefs loadBoolPref:bundleID defaultValue:YES];
} // isExtraWithBundleIDLoaded

- (void)removeExtraWithBundleID:(NSString *)bundleID {
    [ourPrefs saveBoolPref:bundleID value:NO];
    [[NSNotificationCenter defaultCenter] postNotificationName:bundleID
                                                                   object:kPrefChangeNotification
     userInfo:nil];
    if([self noMenuMeterLoaded]){
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [self.window makeKeyAndOrderFront:self];
    }
    return;
} // removeExtraWithBundleID

- (void)showMenuExtraErrorSheet {

	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = [[NSBundle bundleForClass:[self class]] localizedStringForKey:@"Menu Extra Could Not Load"
																				value:nil
																				table:nil];
	alert.informativeText = [[NSBundle bundleForClass:[self class]]
		localizedStringForKey:@"For instructions on enabling third-party menu extras please see the documentation."
						value:nil
						table:nil];
	[alert addButtonWithTitle:@"OK"];

	NSWindow *window = [[self mainView] window];
	if (window) {
		[alert beginSheetModalForWindow:window completionHandler:nil];
	} else {
		[alert runModal];
	}

} // showMenuExtraErrorSheet

///////////////////////////////////////////////////////////////
//
//	Net prefs update
//
///////////////////////////////////////////////////////////////

- (void)updateNetInterfaceMenu {

	// Start by removing all items but the first
	while ([netPreferInterface numberOfItems] > 1) {
		[netPreferInterface removeItemAtIndex:[netPreferInterface numberOfItems] - 1];
	}

	// Now populate
	NSMenu *popupMenu = [netPreferInterface menu];
	if (!popupMenu) {
		[netPreferInterface selectItemAtIndex:0];
		[self netPrefChange:netPreferInterface];
		return;
	}

	// Get the dict block for services
	NSDictionary *ipDict = [self sysconfigValueForKey:@"Setup:/Network/Global/IPv4"];
	if (!ipDict) {
		[netPreferInterface selectItemAtIndex:0];
		[self netPrefChange:netPreferInterface];
		return;
	}
	// Get the array of services
	NSArray *serviceArray = [ipDict objectForKey:@"ServiceOrder"];
	if (!serviceArray) {
		[netPreferInterface selectItemAtIndex:0];
		[self netPrefChange:netPreferInterface];
		return;
	}

	NSEnumerator *serviceEnum = [serviceArray objectEnumerator];
	NSString *serviceID = nil;
	int	selectIndex = 0;
	while ((serviceID = [serviceEnum nextObject])) {
		NSString *longName = nil, *shortName = nil, *pppName = nil;
		// Get interface details
		NSDictionary *interfaceDict = [self sysconfigValueForKey:
										[NSString stringWithFormat:@"Setup:/Network/Service/%@/Interface", serviceID]];
		if (!interfaceDict) continue;
		// This code is a quasi-clone of the code in MenuMeterNetConfig.
		// Look there to see what all this means
		if ([interfaceDict objectForKey:@"UserDefinedName"]) {
			longName = [interfaceDict objectForKey:@"UserDefinedName"];
		} else if ([interfaceDict objectForKey:@"Hardware"]) {
			longName = [interfaceDict objectForKey:@"Hardware"];
		}
		if ([interfaceDict objectForKey:@"DeviceName"]) {
			shortName = [interfaceDict objectForKey:@"DeviceName"];
		}
		NSDictionary *pppDict = [self sysconfigValueForKey:
									[NSString stringWithFormat:@"State:/Network/Service/%@/PPP", serviceID]];
		if (pppDict && [pppDict objectForKey:@"InterfaceName"]) {
			pppName = [pppDict objectForKey:@"InterfaceName"];
		}
		// Now we can try to build the item
		if (!shortName) continue;  // Nothing to key off, bail
		if (!longName) longName = @"Unknown Interface";
		if (!shortName && pppName) {
			// Swap pppName for short name
			shortName = pppName;
			pppName = nil;
		}
		if (longName && shortName && pppName) {
			NSMenuItem *newMenuItem = (NSMenuItem *)[popupMenu addItemWithTitle:
														[NSString stringWithFormat:@"%@ (%@, %@)", longName, shortName, pppName]
																		action:nil
																 keyEquivalent:@""];
			[newMenuItem setRepresentedObject:shortName];
			// Update the selected index if appropriate
			if ([shortName isEqualToString:[ourPrefs netPreferInterface]]) {
				selectIndex = (int)[popupMenu numberOfItems] - 1;
			}
		} else if (longName && shortName) {
			NSMenuItem *newMenuItem = (NSMenuItem *)[popupMenu addItemWithTitle:
														[NSString stringWithFormat:@"%@ (%@)", longName, shortName]
																		 action:nil
																  keyEquivalent:@""];
			[newMenuItem setRepresentedObject:shortName];
			// Update the selected index if appropriate
			if ([shortName isEqualToString:[ourPrefs netPreferInterface]]) {
				selectIndex = (int)[popupMenu numberOfItems] - 1;
			}
		}
	}

	// Menu is built, pick
	if ((selectIndex < 0) || (selectIndex >= [popupMenu numberOfItems])) {
		selectIndex = 0;
	}
	[netPreferInterface selectItemAtIndex:selectIndex];
	[self netPrefChange:netPreferInterface];

} // updateNetInterfaceMenu

///////////////////////////////////////////////////////////////
//
//	CPU info
//
///////////////////////////////////////////////////////////////

- (BOOL)isMultiProcessor {

	uint32_t cpuCount = 0;
	size_t sysctlLength = sizeof(cpuCount);
	int mib[2] = { CTL_HW, HW_NCPU };
	if (sysctl(mib, 2, &cpuCount, &sysctlLength, NULL, 0)) return NO;
	if (cpuCount > 1) {
		return YES;
	} else {
		return NO;
	}

} // isMultiProcessor

///////////////////////////////////////////////////////////////
//
// 	System config framework
//
///////////////////////////////////////////////////////////////

- (void)connectSystemConfig {

	// Create the callback context
	SCDynamicStoreContext scContext;
	scContext.version = 0;
	scContext.info = (__bridge void * _Nullable)(self);
	scContext.retain = NULL;
	scContext.release = NULL;
	scContext.copyDescription = NULL;

	// And create the session, somewhat bizarrely, passing anything other than [self description]
	// cause an occassional crash in the callback.
	scSession = SCDynamicStoreCreate(kCFAllocatorDefault,
									 (CFStringRef)[self description],
									 scChangeCallback,
									 &scContext);
	if (!scSession) {
		NSLog(@"MenuMetersPref unable to establish configd session.");
		return;
	}

	// Install notification run source
	if (!SCDynamicStoreSetNotificationKeys(scSession,
										   (CFArrayRef)[NSArray arrayWithObjects:
														@"State:/Network/Global/IPv4",
														@"Setup:/Network/Global/IPv4",
														@"State:/Network/Interface", nil],
										   (CFArrayRef)[NSArray arrayWithObjects:
														@"State:/Network/Interface.*", nil])) {
		NSLog(@"MenuMetersPref unable to install configd notification keys.");
		CFRelease(scSession);
		scSession = NULL;
		return;
	}
	scRunSource = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, scSession, 0);
	if (!scRunSource) {
		NSLog(@"MenuMetersPref unable to get configd notification keys run loop source.");
		CFRelease(scSession);
		scSession = NULL;
		return;
	}
	CFRunLoopAddSource(CFRunLoopGetCurrent(), scRunSource, kCFRunLoopDefaultMode);

} // connectSystemConfig

- (void)disconnectSystemConfig {

	// Remove the runsource
	if (scRunSource) {
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), scRunSource, kCFRunLoopDefaultMode);
		CFRelease(scRunSource);
		scRunSource = NULL;
	}

	// Kill our configd session
	if (scSession) {
		CFRelease(scSession);
		scSession = NULL;
	}

} // disconnectSystemConfig

- (NSDictionary *)sysconfigValueForKey:(NSString *)key {

	if (!scSession) return nil;
	return (NSDictionary *)CFBridgingRelease(SCDynamicStoreCopyValue(scSession, (CFStringRef)key));

} // sysconfigValueForKey

@end
