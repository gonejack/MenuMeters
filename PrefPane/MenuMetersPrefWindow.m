//
//  MenuMetersPrefWindow.m
//
//  Programmatic replacement for MenuMetersPref.xib
//
//  This file is part of MenuMeters.
//
//  MenuMeters is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2 as
//  published by the Free Software Foundation.
//

#import "MenuMetersPrefWindow.h"

///////////////////////////////////////////////////////////////
//
//	Localization
//
///////////////////////////////////////////////////////////////

static NSString *MMPrefLocalized(NSString *key) {
	return NSLocalizedStringFromTable(key, @"MenuMetersPref", nil);
}

#define M(key) MMPrefLocalized(key)

///////////////////////////////////////////////////////////////
//
//	Control factories
//
///////////////////////////////////////////////////////////////

static NSTextField *MMPrefLabel(NSView *parent, NSString *key, NSRect frame,
								NSTextAlignment alignment, CGFloat fontSize,
								NSColor *textColor) {
	NSTextField *label = [NSTextField labelWithString:M(key)];
	label.frame = frame;
	label.alignment = alignment;
	label.font = [NSFont systemFontOfSize:fontSize];
	label.textColor = textColor;
	label.lineBreakMode = NSLineBreakByClipping;
	[parent addSubview:label];
	return label;
}

static NSButton *MMPrefCheckbox(NSView *parent, NSString *key, NSRect frame,
								id target, SEL action) {
	NSButton *button = [NSButton checkboxWithTitle:M(key) target:target action:action];
	button.frame = frame;
	button.font = [NSFont systemFontOfSize:13];
	[parent addSubview:button];
	return button;
}

static NSButton *MMPrefPushButton(NSView *parent, NSString *key, NSRect frame,
								  id target, SEL action) {
	NSButton *button = [NSButton buttonWithTitle:M(key) target:target action:action];
	button.frame = frame;
	button.font = [NSFont systemFontOfSize:13];
	[parent addSubview:button];
	return button;
}

static NSPopUpButton *MMPrefPopUp(NSView *parent, NSRect frame, NSArray<NSString *> *keys,
								  NSInteger selectedIndex, id target, SEL action) {
	NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO];
	button.font = [NSFont systemFontOfSize:13];
	for (NSString *key in keys) {
		[button addItemWithTitle:M(key)];
	}
	if (selectedIndex >= 0 && selectedIndex < (NSInteger)keys.count) {
		[button selectItemAtIndex:selectedIndex];
	}
	button.target = target;
	button.action = action;
	[parent addSubview:button];
	return button;
}

static NSSlider *MMPrefSlider(NSView *parent, NSRect frame,
							  double minValue, double maxValue, double value,
							  NSInteger tickMarks, BOOL allowsTickMarkValuesOnly,
							  BOOL continuous, NSControlSize controlSize,
							  id target, SEL action) {
	NSSlider *slider = [[NSSlider alloc] initWithFrame:frame];
	slider.minValue = minValue;
	slider.maxValue = maxValue;
	slider.doubleValue = value;
	slider.numberOfTickMarks = tickMarks;
	slider.allowsTickMarkValuesOnly = allowsTickMarkValuesOnly;
	slider.continuous = continuous;
	slider.controlSize = controlSize;
	slider.target = target;
	slider.action = action;
	[parent addSubview:slider];
	return slider;
}

static NSColorWell *MMPrefColorWell(NSView *parent, NSRect frame, id target, SEL action) {
	NSColorWell *well = [[NSColorWell alloc] initWithFrame:frame];
	well.target = target;
	well.action = action;
	[parent addSubview:well];
	return well;
}

static void MMPrefSeparator(NSView *parent, NSRect frame) {
	NSBox *separator = [[NSBox alloc] initWithFrame:frame];
	separator.boxType = NSBoxSeparator;
	[parent addSubview:separator];
}

///////////////////////////////////////////////////////////////
//
//	Window construction
//
///////////////////////////////////////////////////////////////

@implementation MenuMetersPref (PreferenceWindow)

- (NSWindow *)buildPreferenceWindow {
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(119, 174, 594, 673)
												   styleMask:(NSWindowStyleMaskTitled |
															  NSWindowStyleMaskClosable |
															  NSWindowStyleMaskMiniaturizable)
													 backing:NSBackingStoreBuffered
													   defer:NO];
	window.title = M(@"MenuMeters");
	window.releasedWhenClosed = NO;
	window.delegate = self;
	self.window = window;

	// The frames and control order below mirror MenuMetersPref.xib exactly.
	// Keeping the original fixed frames preserves the layout while removing the
	// nib dependency.
    NSView *contentView = window.contentView;
    prefTabs = [[NSTabView alloc] initWithFrame:NSMakeRect(13, 11, 568, 652)];
    prefTabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:prefTabs];

    {
        NSTabViewItem *tabItem = [[NSTabViewItem alloc] initWithIdentifier:@"cpu"];
        tabItem.label = M(@"CPU");
        NSView *tabView = [[NSView alloc] initWithFrame:NSMakeRect(10, 33, 548, 606)];
        tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, -3, 554, 626)];
        container.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
        [tabView addSubview:container];
        cpuPowerMateMode = MMPrefPopUp(container, NSMakeRect(317, 90, 216, 26), @[M(@"glow"), M(@"pulse"), M(@"inverse glow"), M(@"inverse pulse")], 2, self, @selector(cpuPrefChange:));
        cpuPowerMate = MMPrefCheckbox(container, @"PowerMate shows CPU usage as", NSMakeRect(87, 94, 225, 21), self, @selector(cpuPrefChange:));
        cpuPowerMate.state = NSControlStateValueOff;
        MMPrefSeparator(container, NSMakeRect(68, 75, 464, 5));
        MMPrefLabel(container, @"Colors", NSMakeRect(18, 69, 45, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        MMPrefSeparator(container, NSMakeRect(130, 326, 401, 5));
        MMPrefLabel(container, @"Graph Display", NSMakeRect(17, 326, 107, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        MMPrefSeparator(container, NSMakeRect(227, 208, 303, 5));
        MMPrefLabel(container, @"Horizontal Thermometer Display", NSMakeRect(17, 203, 211, 21), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        MMPrefSeparator(container, NSMakeRect(146, 386, 385, 5));
        MMPrefLabel(container, @"Percentage Display", NSMakeRect(17, 385, 124, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuGraphWidthLabel = MMPrefLabel(container, @"Graph width:", NSMakeRect(85, 298, 160, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuHorizontalRowsLabel = MMPrefLabel(container, @"Horizontal Rows:", NSMakeRect(84, 170, 115, 22), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuPercentModeLabel = MMPrefLabel(container, @"Display percentage as:", NSMakeRect(85, 359, 148, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuGraphWidth = MMPrefSlider(container, NSMakeRect(251, 294, 279, 18), 11, 88, 33, 8, YES, NO, NSControlSizeSmall, self, @selector(cpuPrefChange:));
        cpuHorizontalRows = MMPrefSlider(container, NSMakeRect(251, 172, 279, 18), 1, 8, 4, 8, YES, NO, NSControlSizeSmall, self, @selector(cpuPrefChange:));
        cpuMenuWidthLabel = MMPrefLabel(container, @"Horizontal Width:", NSMakeRect(85, 146, 148, 22), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuMenuWidth = MMPrefSlider(container, NSMakeRect(250, 148, 280, 18), 60, 400, 120, 8, NO, NO, NSControlSizeSmall, self, @selector(cpuPrefChange:));
        cpuSystemColorLabel = MMPrefLabel(container, @"System", NSMakeRect(226, 58, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        cpuUserColorLabel = MMPrefLabel(container, @"User", NSMakeRect(86, 58, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        cpuUserColor = MMPrefColorWell(container, NSMakeRect(110, 20, 53, 30), self, @selector(cpuPrefChange:));
        cpuSystemColor = MMPrefColorWell(container, NSMakeRect(250, 20, 53, 30), self, @selector(cpuPrefChange:));
        cpuIntervalDisplay = MMPrefLabel(container, @"x", NSMakeRect(183, 453, 54, 17), NSTextAlignmentCenter, 13, NSColor.controlTextColor);
        MMPrefLabel(container, @"Update interval (seconds):", NSMakeRect(18, 453, 168, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuInterval = MMPrefSlider(container, NSMakeRect(249, 444, 283, 24), 0.5, 10, 1.5, 20, YES, YES, NSControlSizeRegular, self, @selector(liveUpdateInterval:));
        cpuMeterToggle = MMPrefCheckbox(container, @"Display CPU Menu Meter", NSMakeRect(19, 571, 227, 27), self, @selector(cpuPrefChange:));
        cpuMeterToggle.state = NSControlStateValueOff;
        MMPrefSeparator(container, NSMakeRect(130, 267, 402, 5));
        MMPrefLabel(container, @"Process Display", NSMakeRect(18, 267, 106, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuMaxProcessCount = MMPrefSlider(container, NSMakeRect(250, 235, 280, 18), 0, 25, 5, 26, YES, YES, NSControlSizeSmall, self, @selector(cpuPrefChange:));
        cpuMaxProcessCountCountLabel = MMPrefLabel(container, @"(%d)", NSMakeRect(202, 239, 35, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        MMPrefLabel(container, @"Temperature", NSMakeRect(360, 58, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        cpuTemperatureColor = MMPrefColorWell(container, NSMakeRect(384, 20, 53, 30), self, @selector(cpuPrefChange:));
        MMPrefLabel(container, @"Misc", NSMakeRect(18, 117, 125, 22), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        MMPrefLabel(container, @"Show:", NSMakeRect(84, 410, 121, 22), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuMultipleCPU = MMPrefPopUp(container, NSMakeRect(248, 408, 285, 26), @[M(@"all cores, including hyperthreaded ones"), M(@"physical cores only"), M(@"the average of all cores"), M(@"the sum of all cores"), M(@"all cores sorted")], 0, self, @selector(cpuPrefChange:));
        MMPrefSeparator(container, NSMakeRect(69, 125, 462, 5));
        MMPrefLabel(container, @"Processes to show:", NSMakeRect(84, 240, 161, 16), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        cpuTemperatureToggle = MMPrefCheckbox(container, @"Show CPU Temperature in", NSMakeRect(248, 524, 181, 18), self, @selector(cpuPrefChange:));
        cpuTemperatureToggle.state = NSControlStateValueOff;
        cpuPercentMode = MMPrefPopUp(container, NSMakeRect(249, 353, 284, 26), @[M(@"Total (large text)"), M(@"Total (medium text)"), M(@"User and System (small text)")], 2, self, @selector(cpuPrefChange:));
        cpuTemperatureUnit = MMPrefPopUp(container, NSMakeRect(433, 518, 99, 26), @[M(@"℃"), M(@"℉")], 0, self, @selector(cpuPrefChange:));
        cpuHorizontalThermometer = MMPrefCheckbox(container, @"Horizontal bar", NSMakeRect(382, 550, 140, 18), self, @selector(cpuPrefChange:));
        cpuHorizontalThermometer.state = NSControlStateValueOn;
        cpuThermometer = MMPrefCheckbox(container, @"Vertical bar", NSMakeRect(382, 573, 140, 18), self, @selector(cpuPrefChange:));
        cpuThermometer.state = NSControlStateValueOn;
        cpuGraph = MMPrefCheckbox(container, @"Graph", NSMakeRect(248, 550, 140, 18), self, @selector(cpuPrefChange:));
        cpuGraph.state = NSControlStateValueOn;
        cpuPercentage = MMPrefCheckbox(container, @"Percentage", NSMakeRect(248, 574, 140, 18), self, @selector(cpuPrefChange:));
        cpuPercentage.state = NSControlStateValueOn;
        cpuTemperatureSensor = MMPrefPopUp(container, NSMakeRect(326, 488, 206, 25), @[], -1, self, @selector(cpuPrefChange:));
        MMPrefLabel(container, @"Sensor:", NSMakeRect(269, 489, 63, 22), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        tabItem.view = tabView;
        [prefTabs addTabViewItem:tabItem];
    }

    {
        NSTabViewItem *tabItem = [[NSTabViewItem alloc] initWithIdentifier:@"internaldrive"];
        tabItem.label = M(@"Disk");
        NSView *tabView = [[NSView alloc] initWithFrame:NSMakeRect(10, 33, 548, 606)];
        tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 52, 554, 571)];
        container.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
        [tabView addSubview:container];
        MMPrefLabel(container, @"(Holding the Option key will reverse the behavior)", NSMakeRect(21, 391, 511, 13), NSTextAlignmentCenter, 10, NSColor.controlTextColor);
        diskSelectMode = MMPrefPopUp(container, NSMakeRect(284, 409, 241, 26), @[M(@"opens the volume"), M(@"unmounts/ejects the volume")], 0, self, @selector(diskPrefChange:));
        MMPrefLabel(container, @"Selecting a volume from the disk menu", NSMakeRect(29, 414, 251, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        MMPrefLabel(container, @"Update interval (seconds):", NSMakeRect(18, 486, 168, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        diskImageSet = MMPrefPopUp(container, NSMakeRect(273, 516, 262, 26), @[M(@"ImageSet")], 0, self, @selector(diskPrefChange:));
        diskInterval = MMPrefSlider(container, NSMakeRect(19, 454, 515, 24), 0.1, 5, 0.3, 50, YES, YES, NSControlSizeRegular, self, @selector(liveUpdateInterval:));
        diskIntervalDisplay = MMPrefLabel(container, @"x", NSMakeRect(183, 486, 54, 17), NSTextAlignmentCenter, 13, NSColor.controlTextColor);
        diskMeterToggle = MMPrefCheckbox(container, @"Display Disk Activity Menu Meter", NSMakeRect(19, 516, 251, 27), self, @selector(diskPrefChange:));
        diskMeterToggle.state = NSControlStateValueOff;
        tabItem.view = tabView;
        [prefTabs addTabViewItem:tabItem];
    }

    {
        NSTabViewItem *tabItem = [[NSTabViewItem alloc] initWithIdentifier:@"memorychip"];
        tabItem.label = M(@"Memory");
        NSView *tabView = [[NSView alloc] initWithFrame:NSMakeRect(10, 33, 548, 606)];
        tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 52, 554, 571)];
        container.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
        [tabView addSubview:container];
        memPageIndicator = MMPrefCheckbox(container, @"Show paging activity indicator", NSMakeRect(171, 390, 302, 18), self, @selector(memPrefChange:));
        memPageIndicator.state = NSControlStateValueOff;
        MMPrefSeparator(container, NSMakeRect(75, 415, 457, 5));
        MMPrefLabel(container, @"General", NSMakeRect(18, 414, 189, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        memFreeUsedLabeling = MMPrefCheckbox(container, @"Show Used/Free labels", NSMakeRect(171, 370, 302, 18), self, @selector(memPrefChange:));
        memFreeUsedLabeling.state = NSControlStateValueOff;
        memInterval = MMPrefSlider(container, NSMakeRect(19, 454, 515, 24), 1, 60, 15, 60, YES, YES, NSControlSizeRegular, self, @selector(liveUpdateInterval:));
        MMPrefLabel(container, @"Update interval (seconds):", NSMakeRect(18, 486, 168, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        memDisplayMode = MMPrefPopUp(container, NSMakeRect(273, 516, 262, 26), @[M(@"Usage Chart"), M(@"Usage Bar"), M(@"Usage History Graph"), M(@"Used/Free Totals")], 0, self, @selector(memPrefChange:));
        memIntervalDisplay = MMPrefLabel(container, @"x", NSMakeRect(183, 486, 54, 17), NSTextAlignmentCenter, 13, NSColor.controlTextColor);
        memMeterToggle = MMPrefCheckbox(container, @"Display Memory Menu Meter", NSMakeRect(19, 516, 251, 27), self, @selector(memPrefChange:));
        memMeterToggle.state = NSControlStateValueOff;
        memInactiveColor = MMPrefColorWell(container, NSMakeRect(299, 178, 53, 30), self, @selector(memPrefChange:));
        memWiredColor = MMPrefColorWell(container, NSMakeRect(210, 178, 53, 30), self, @selector(memPrefChange:));
        memActiveColor = MMPrefColorWell(container, NSMakeRect(121, 178, 53, 30), self, @selector(memPrefChange:));
        MMPrefLabel(container, @"Active", NSMakeRect(97, 216, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        MMPrefLabel(container, @"Inactive", NSMakeRect(275, 216, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        MMPrefLabel(container, @"Wired", NSMakeRect(186, 216, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        memCompressedColor = MMPrefColorWell(container, NSMakeRect(385, 178, 53, 30), self, @selector(memPrefChange:));
        MMPrefLabel(container, @"Compressed", NSMakeRect(362, 216, 96, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        memUsedColor = MMPrefColorWell(container, NSMakeRect(299, 42, 53, 30), self, @selector(memPrefChange:));
        MMPrefLabel(container, @"Free", NSMakeRect(221, 80, 35, 14), NSTextAlignmentLeft, 11, NSColor.controlTextColor);
        MMPrefLabel(container, @"Used", NSMakeRect(308, 80, 44, 14), NSTextAlignmentLeft, 11, NSColor.controlTextColor);
        memFreeColor = MMPrefColorWell(container, NSMakeRect(210, 42, 53, 30), self, @selector(memPrefChange:));
        MMPrefSeparator(container, NSMakeRect(140, 317, 392, 5));
        memGraphWidth = MMPrefSlider(container, NSMakeRect(172, 282, 299, 17), 11, 88, 33, 8, YES, NO, NSControlSizeSmall, self, @selector(memPrefChange:));
        MMPrefLabel(container, @"Graph Display", NSMakeRect(18, 319, 116, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        memGraphWidthLabel = MMPrefLabel(container, @"Graph width:", NSMakeRect(30, 289, 137, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        MMPrefSeparator(container, NSMakeRect(68, 243, 464, 5));
        MMPrefLabel(container, @"Colors", NSMakeRect(18, 242, 45, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        memPressureMode = MMPrefCheckbox(container, @"Display memory pressure", NSMakeRect(170, 352, 303, 18), self, @selector(memPrefChange:));
        memPressureMode.state = NSControlStateValueOff;
        memPageoutColorLabel = MMPrefLabel(container, @"Pageout", NSMakeRect(275, 146, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        memPageoutColor = MMPrefColorWell(container, NSMakeRect(299, 108, 53, 30), self, @selector(memPrefChange:));
        memPageinColorLabel = MMPrefLabel(container, @"Pagein", NSMakeRect(186, 146, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        memPageinColor = MMPrefColorWell(container, NSMakeRect(210, 108, 53, 30), self, @selector(memPrefChange:));
        tabItem.view = tabView;
        [prefTabs addTabViewItem:tabItem];
    }

    {
        NSTabViewItem *tabItem = [[NSTabViewItem alloc] initWithIdentifier:@"network"];
        tabItem.label = M(@"Network");
        NSView *tabView = [[NSView alloc] initWithFrame:NSMakeRect(10, 33, 548, 606)];
        tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 52, 554, 571)];
        container.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
        [tabView addSubview:container];
        netInactiveColor = MMPrefColorWell(container, NSMakeRect(341, 31, 53, 30), self, @selector(netPrefChange:));
        MMPrefLabel(container, @"Inactive", NSMakeRect(317, 69, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        netDisplayOrientation = MMPrefPopUp(container, NSMakeRect(222, 385, 172, 26), @[M(@"Transmit/Receive"), M(@"Receive/Transmit")], 0, self, @selector(netPrefChange:));
        MMPrefLabel(container, @"Display orientation:", NSMakeRect(94, 390, 128, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        netScaleCalc = MMPrefPopUp(container, NSMakeRect(222, 307, 172, 26), @[M(@"Linear"), M(@"Square root"), M(@"Cube root"), M(@"Logarithmic")], 0, self, @selector(netPrefChange:));
        netScaleCalcLabel = MMPrefLabel(container, @"Display scaling:", NSMakeRect(30, 313, 192, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        netScaleMode = MMPrefPopUp(container, NSMakeRect(222, 333, 172, 26), @[M(@"Interface speed"), M(@"Peak traffic")], 0, self, @selector(netPrefChange:));
        netScaleModeLabel = MMPrefLabel(container, @"Display scales to:", NSMakeRect(30, 339, 192, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        MMPrefSeparator(container, NSMakeRect(75, 415, 457, 4));
        MMPrefLabel(container, @"General", NSMakeRect(18, 416, 64, 15), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        netPreferInterface = MMPrefPopUp(container, NSMakeRect(222, 359, 273, 26), @[M(@"Primary (automatic)")], 0, self, @selector(netPrefChange:));
        MMPrefLabel(container, @"Display prefers interface:", NSMakeRect(30, 365, 192, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        MMPrefSeparator(container, NSMakeRect(68, 89, 464, 5));
        MMPrefLabel(container, @"Colors", NSMakeRect(18, 88, 45, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        MMPrefSeparator(container, NSMakeRect(140, 193, 392, 5));
        MMPrefLabel(container, @"Graph Display", NSMakeRect(18, 193, 115, 16), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        MMPrefSeparator(container, NSMakeRect(153, 272, 379, 5));
        MMPrefLabel(container, @"Throughput Display", NSMakeRect(18, 271, 130, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        netGraphStyle = MMPrefPopUp(container, NSMakeRect(162, 156, 165, 26), @[M(@"Standard"), M(@"Centered"), M(@"Opposed"), M(@"Inverse Opposed")], 0, self, @selector(netPrefChange:));
        netGraphWidthLabel = MMPrefLabel(container, @"Graph width:", NSMakeRect(74, 135, 86, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        netGraphStyleLabel = MMPrefLabel(container, @"Graph style:", NSMakeRect(80, 162, 80, 17), NSTextAlignmentRight, 13, NSColor.controlTextColor);
        netThroughputBits = MMPrefCheckbox(container, @"Show bits per second", NSMakeRect(163, 250, 317, 18), self, @selector(netPrefChange:));
        netThroughputBits.state = NSControlStateValueOff;
        netThroughputLabeling = MMPrefCheckbox(container, @"Show throughput labels (Tx/Rx)", NSMakeRect(163, 210, 317, 18), self, @selector(netPrefChange:));
        netThroughputLabeling.state = NSControlStateValueOff;
        netRxColor = MMPrefColorWell(container, NSMakeRect(251, 31, 53, 30), self, @selector(netPrefChange:));
        netGraphWidth = MMPrefSlider(container, NSMakeRect(165, 128, 313, 18), 11, 88, 33, 8, YES, NO, NSControlSizeSmall, self, @selector(netPrefChange:));
        netTxColor = MMPrefColorWell(container, NSMakeRect(161, 31, 53, 30), self, @selector(netPrefChange:));
        MMPrefLabel(container, @"Receive", NSMakeRect(227, 69, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        MMPrefLabel(container, @"Transmit", NSMakeRect(138, 69, 100, 14), NSTextAlignmentCenter, 11, NSColor.controlTextColor);
        MMPrefLabel(container, @"Update interval (seconds):", NSMakeRect(18, 486, 168, 17), NSTextAlignmentLeft, 13, NSColor.controlTextColor);
        netDisplayMode = MMPrefPopUp(container, NSMakeRect(273, 516, 262, 26), @[M(@"Arrows"), M(@"Throughput"), M(@"Arrows and Throughput"), M(@"Graph"), M(@"Graph and Arrows"), M(@"Graph and Throughput"), M(@"Graph, Arrows and Throughput")], 6, self, @selector(netPrefChange:));
        netMeterToggle = MMPrefCheckbox(container, @"Display Network Menu Meter", NSMakeRect(19, 516, 251, 27), self, @selector(netPrefChange:));
        netMeterToggle.state = NSControlStateValueOff;
        netIntervalDisplay = MMPrefLabel(container, @"x", NSMakeRect(183, 486, 54, 17), NSTextAlignmentCenter, 13, NSColor.controlTextColor);
        netInterval = MMPrefSlider(container, NSMakeRect(19, 454, 515, 25), 0.5, 20, 2, 40, YES, YES, NSControlSizeRegular, self, @selector(liveUpdateInterval:));
        netThroughput1KBound = MMPrefCheckbox(container, @"Ignore values below 1K/s", NSMakeRect(163, 230, 317, 18), self, @selector(netPrefChange:));
        netThroughput1KBound.state = NSControlStateValueOff;
        tabItem.view = tabView;
        [prefTabs addTabViewItem:tabItem];
    }

    {
        NSTabViewItem *tabItem = [[NSTabViewItem alloc] initWithIdentifier:@"info.circle"];
        tabItem.label = M(@"About");
        NSView *tabView = [[NSView alloc] initWithFrame:NSMakeRect(10, 33, 548, 606)];
        tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSScrollView *aboutScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(-3, 120, 554, 483)];
        aboutScroll.borderType = NSNoBorder;
        aboutScroll.hasHorizontalScroller = NO;
        aboutScroll.hasVerticalScroller = YES;
        aboutScroll.autohidesScrollers = YES;
        aboutScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        NSTextView *aboutTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 554, 483)];
        aboutTextView.minSize = NSMakeSize(0, 483);
        aboutTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        aboutTextView.verticallyResizable = YES;
        aboutTextView.horizontallyResizable = NO;
        aboutTextView.autoresizingMask = NSViewWidthSizable;
        aboutTextView.richText = NO;
        aboutTextView.importsGraphics = NO;
        aboutTextView.editable = NO;
        aboutTextView.selectable = YES;
        aboutTextView.drawsBackground = YES;
        aboutTextView.textContainer.containerSize = NSMakeSize(554, CGFLOAT_MAX);
        aboutTextView.textContainer.widthTracksTextView = YES;
        aboutScroll.documentView = aboutTextView;
        aboutView = aboutTextView;
        [tabView addSubview:aboutScroll];
        NSView *sparkleContainer = [[NSView alloc] initWithFrame:NSMakeRect(-3, -3, 554, 125)];
        sparkleContainer.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
        sparkleUIContainer = sparkleContainer;
        [tabView addSubview:sparkleContainer];
        updateIntervalLabel = MMPrefLabel(sparkleContainer, @"Automatic update check interval:", NSMakeRect(17, 24, 203, 16), NSTextAlignmentLeft, 13, NSColor.labelColor);
        MMPrefLabel(sparkleContainer, @"Color tint:", NSMakeRect(25, 82, 195, 16), NSTextAlignmentRight, 13, NSColor.labelColor);
        MMPrefLabel(sparkleContainer, @"original", NSMakeRect(233, 99, 109, 16), NSTextAlignmentLeft, 13, NSColor.secondaryLabelColor);
        MMPrefLabel(sparkleContainer, @"Activity monitor:", NSMakeRect(25, 52, 195, 16), NSTextAlignmentRight, 13, NSColor.labelColor);
        updateIntervalButton = MMPrefPopUp(sparkleContainer, NSMakeRect(228, 17, 156, 25), @[M(@"Never"), M(@"Once per day"), M(@"Once per week"), M(@"Once per month")], 1, self, @selector(updateInterval:));
        activityMonitorPaneCheckbox = MMPrefCheckbox(sparkleContainer, @"Opens specific panes", NSMakeRect(230, 51, 306, 18), self, @selector(showAlertConcerningSystemEventsEtc:));
        activityMonitorPaneCheckbox.state = NSControlStateValueOff;
        checkUpdatesButton = MMPrefPushButton(sparkleContainer, @"Check updates now", NSMakeRect(381, 13, 160, 32), nil, @selector(checkForUpdates:));
        tintPercentageSlider = MMPrefSlider(sparkleContainer, NSMakeRect(230, 76, 306, 28), 0, 100, 10, 0, NO, YES, NSControlSizeRegular, self, @selector(tintPercentageChanged:));
        MMPrefLabel(sparkleContainer, @"pure black/white", NSMakeRect(427, 99, 109, 16), NSTextAlignmentRight, 13, NSColor.secondaryLabelColor);
        tabItem.view = tabView;
        [prefTabs addTabViewItem:tabItem];
    }

	return window;
}

@end
