//
//  MenuMetersPrefPane.h
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

#import <SystemConfiguration/SystemConfiguration.h>
#import <AppKit/AppKit.h>
#import <sys/types.h>
#import <sys/sysctl.h>
#import <unistd.h>
#import "MenuMeters.h"
#import "MenuMeterDefaults.h"
#import "MenuMeterWorkarounds.h"
#import "MenuMeterCPU.h"
#import "MenuMeterDisk.h"
#import "MenuMeterMem.h"
#import "MenuMeterNet.h"
#import "MenuMeterPowerMate.h"
#ifdef SPARKLE
#import <Sparkle/Sparkle.h>
#endif

@interface MenuMetersPref :
NSWindowController<NSWindowDelegate, NSToolbarDelegate, NSTabViewDelegate>
{

	// Our preferences
	MenuMeterDefaults				*ourPrefs;
	// System config framework hooks
	SCDynamicStoreRef				scSession;
	CFRunLoopSourceRef				scRunSource;
	// Main controls
	NSTabView				*prefTabs;
	NSTextView				*aboutView;
	// CPU pane controls
	NSButton				*cpuMeterToggle;
	NSButton				*cpuPercentage;
	NSButton				*cpuGraph;
	NSButton				*cpuThermometer;
	NSButton				*cpuHorizontalThermometer;

	NSButton				*cpuTemperatureToggle;
	NSPopUpButton			*cpuTemperatureUnit;
	NSTextField				*cpuIntervalDisplay;
	NSSlider				*cpuInterval;
	NSPopUpButton			*cpuPercentMode;
	NSTextField				*cpuPercentModeLabel;
	NSSlider				*cpuMaxProcessCount;
	NSTextField				*cpuMaxProcessCountCountLabel;
	NSSlider				*cpuGraphWidth;
	NSTextField				*cpuGraphWidthLabel;
	NSSlider				*cpuHorizontalRows;
	NSTextField				*cpuHorizontalRowsLabel;
	NSSlider				*cpuMenuWidth;
	NSTextField				*cpuMenuWidthLabel;
	NSPopUpButton			*cpuMultipleCPU;
	NSButton				*cpuPowerMate;
	NSPopUpButton			*cpuPowerMateMode;
	NSColorWell				*cpuUserColor;
	NSColorWell				*cpuTemperatureColor;
	NSPopUpButton			*cpuTemperatureSensor;
	NSTextField				*cpuUserColorLabel;
	NSColorWell				*cpuSystemColor;
	NSTextField				*cpuSystemColorLabel;
	// Disk pane controls
	NSButton				*diskMeterToggle;
	NSPopUpButton			*diskImageSet;
	NSTextField				*diskIntervalDisplay;
	NSSlider				*diskInterval;
	NSPopUpButton			*diskSelectMode;
	// Mem pane controls
	NSButton				*memMeterToggle;
	NSPopUpButton			*memDisplayMode;
	NSTextField				*memIntervalDisplay;
	NSSlider				*memInterval;
	NSButton				*memFreeUsedLabeling;
	NSButton				*memPageIndicator;
	NSSlider				*memGraphWidth;
	NSTextField				*memGraphWidthLabel;
	NSColorWell				*memActiveColor;
	NSColorWell				*memInactiveColor;
	NSColorWell				*memWiredColor;
	NSColorWell				*memCompressedColor;
	NSColorWell				*memFreeColor;
	NSColorWell				*memUsedColor;
	NSColorWell				*memPageinColor;
	NSTextField				*memPageinColorLabel;
	NSColorWell				*memPageoutColor;
	NSTextField				*memPageoutColorLabel;
	NSButton				*memPressureMode;
	// Net pane controls
	NSButton				*netMeterToggle;
	NSPopUpButton			*netDisplayMode;
	NSPopUpButton			*netDisplayOrientation;
	NSPopUpButton			*netPreferInterface;
	NSPopUpButton			*netScaleMode;
	NSTextField				*netScaleModeLabel;
	NSPopUpButton			*netScaleCalc;
	NSTextField				*netScaleCalcLabel;
	NSTextField				*netIntervalDisplay;
	NSSlider				*netInterval;
	NSButton				*netThroughputLabeling;
	NSButton				*netThroughput1KBound;
	NSButton				*netThroughputBits;
	NSPopUpButton			*netGraphStyle;
	NSTextField				*netGraphStyleLabel;
	NSSlider				*netGraphWidth;
	NSTextField				*netGraphWidthLabel;
	NSColorWell				*netTxColor;
	NSColorWell				*netRxColor;
	NSColorWell				*netInactiveColor;
	// About pane controls
	NSTextField				*updateIntervalLabel;
	NSPopUpButton			*updateIntervalButton;
	NSButton				*checkUpdatesButton;
	NSButton				*activityMonitorPaneCheckbox;
	NSSlider				*tintPercentageSlider;
	NSView					*sparkleUIContainer;
	BOOL hiddenAlertIsShown;
} // MenuMetersPref

// Pref pane standard methods
- (void)mainViewDidLoad;
- (void)willSelect;
- (void)didUnselect;

#ifdef SPARKLE
-(instancetype)initWithAboutFileName:(NSString*)about andUpdater:(SPUUpdater*)updater_;
#else
-(instancetype)initWithAboutFileName:(NSString*)about;
#endif
// IB Targets
-(IBAction)openAbout:(id)sender;
- (IBAction)liveUpdateInterval:(id)sender;
- (IBAction)cpuPrefChange:(id)sender;
- (IBAction)diskPrefChange:(id)sender;
- (IBAction)memPrefChange:(id)sender;
- (IBAction)netPrefChange:(id)sender;
- (IBAction)updateInterval:(id)sender;
- (IBAction)tintPercentageChanged:(id)sender;
- (IBAction)showAlertConcerningSystemEventsEtc:(id)sender;

@end
