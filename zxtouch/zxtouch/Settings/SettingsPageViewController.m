//
//  SettingsPageViewController.m
//  zxtouch
//
//  Created by Jason on 2021/1/18.
//

#import "SettingsPageViewController.h"
#import "ScriptListTableCell.h"
#import "TouchIndicatorConfigurationViewController.h"
#import "Util.h"
#import "Socket.h"

#import "TableViewCellWithSwitch.h"
#import "TableViewCellWithSlider.h"
#import "TableViewCellWithEntry.h"

#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"

#import <dlfcn.h>
#import <objc/runtime.h>
#import "Config.h"
#import "ConfigManager.h"
#import "RemoteDashboardServer.h"

#define SETTING_CELL_SWITCH 0
#define SETTING_CELL_ENTRY 1

#define ZX_ACTION_SMART_TOGGLE @"smart_toggle"
#define ZX_ACTION_TOGGLE_PANEL @"toggle_panel"
#define ZX_ACTION_STOP_SCRIPT @"stop_script"
#define ZX_ACTION_TOGGLE_RECORDING @"toggle_recording"
#define ZX_ACTION_RUN_SCRIPT @"run_script"

#define ZX_TRIGGER_VOLUME_UP @"volume_up"
#define ZX_TRIGGER_VOLUME_DOWN @"volume_down"
#define ZX_TRIGGER_HOME @"home"

static UIImage *ZXSettingsSymbol(NSString *name) {
    if (@available(iOS 13.0, *)) {
        return [UIImage systemImageNamed:name];
    }
    return nil;
}

@interface SettingsPageViewController ()
{
    GCDWebServer* _webServer;
}
@end

@implementation SettingsPageViewController
{
    NSArray *sections;
    NSArray<NSArray*> *cellsForEachSection;
    ConfigManager *configManager;
}

- (BOOL)darkModeEnabled {
    id configValue = [configManager getValueFromKey:@"dark_mode"];
    if (configValue) {
        return [configValue boolValue];
    }
    BOOL legacyValue = [[NSUserDefaults standardUserDefaults] boolForKey:@"dark_mode"];
    [configManager updateKey:@"dark_mode" forValue:@(legacyValue)];
    [configManager save];
    return legacyValue;
}

- (NSString *)triggerActionTitle:(NSString *)action {
    if ([action isEqualToString:ZX_ACTION_TOGGLE_PANEL]) return NSLocalizedString(@"togglePanel", nil);
    if ([action isEqualToString:ZX_ACTION_STOP_SCRIPT]) return NSLocalizedString(@"stopScript", nil);
    if ([action isEqualToString:ZX_ACTION_TOGGLE_RECORDING]) return NSLocalizedString(@"toggleRecording", nil);
    if ([action isEqualToString:ZX_ACTION_RUN_SCRIPT]) return NSLocalizedString(@"runDefaultScript", nil);
    return NSLocalizedString(@"smartToggle", nil);
}

- (NSString *)triggerTitle:(NSString *)triggerKey {
    if ([triggerKey isEqualToString:ZX_TRIGGER_VOLUME_UP]) return NSLocalizedString(@"volumeUp", nil);
    if ([triggerKey isEqualToString:ZX_TRIGGER_HOME]) return NSLocalizedString(@"homeButton", nil);
    return NSLocalizedString(@"volumeDown", nil);
}

- (NSMutableDictionary *)triggerConfigForKey:(NSString *)triggerKey {
    NSMutableDictionary *allTriggers = [[configManager getValueFromKey:@"trigger_configs"] mutableCopy];
    NSDictionary *existing = [allTriggers isKindOfClass:[NSDictionary class]] ? allTriggers[triggerKey] : nil;
    if ([existing isKindOfClass:[NSDictionary class]]) return [existing mutableCopy];

    if ([triggerKey isEqualToString:ZX_TRIGGER_VOLUME_DOWN]) {
        BOOL enabled = YES;
        if ([configManager getValueFromKey:@"double_click_volume_show_popup"])
            enabled = [[configManager getValueFromKey:@"double_click_volume_show_popup"] boolValue];
        return [@{
            @"enabled": @(enabled),
            @"count": @(2),
            @"action": [configManager getValueFromKey:@"double_click_volume_action"] ?: ZX_ACTION_SMART_TOGGLE,
            @"script": [configManager getValueFromKey:@"double_click_volume_script"] ?: @""
        } mutableCopy];
    }

    return [@{@"enabled": @(NO), @"count": @(2), @"action": ZX_ACTION_SMART_TOGGLE, @"script": @""} mutableCopy];
}

- (void)saveTriggerConfig:(NSMutableDictionary *)trigger forKey:(NSString *)triggerKey {
    NSMutableDictionary *allTriggers = [[configManager getValueFromKey:@"trigger_configs"] mutableCopy];
    if (![allTriggers isKindOfClass:[NSMutableDictionary class]]) allTriggers = [NSMutableDictionary dictionary];
    allTriggers[triggerKey] = trigger;
    [configManager updateKey:@"trigger_configs" forValue:allTriggers];

    if ([triggerKey isEqualToString:ZX_TRIGGER_VOLUME_DOWN]) {
        [configManager updateKey:@"double_click_volume_show_popup" forValue:trigger[@"enabled"]];
        [configManager updateKey:@"double_click_volume_action" forValue:trigger[@"action"]];
        [configManager updateKey:@"double_click_volume_script" forValue:trigger[@"script"]];
    }
    [configManager save];
    [self reloadSettingsModel];
}

- (NSString *)triggerSummaryForKey:(NSString *)triggerKey {
    NSDictionary *trigger = [self triggerConfigForKey:triggerKey];
    if (![trigger[@"enabled"] boolValue]) return NSLocalizedString(@"triggerOff", nil);
    NSString *actionTitle = [self triggerActionTitle:trigger[@"action"]];
    NSString *script = trigger[@"script"];
    if ([trigger[@"action"] isEqualToString:ZX_ACTION_RUN_SCRIPT] && [script length] > 0) {
        actionTitle = [NSString stringWithFormat:NSLocalizedString(@"runNamedScript", nil), [[script lastPathComponent] stringByDeletingPathExtension]];
    }
    return [NSString stringWithFormat:NSLocalizedString(@"triggerSummary", nil), trigger[@"count"], actionTitle];
}

- (NSArray<NSString *> *)availableScriptPaths {
    NSMutableArray *paths = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:SCRIPTS_PATH];
    NSString *relative = nil;
    while ((relative = [enumerator nextObject])) {
        if ([[relative pathExtension] isEqualToString:@"bdl"]) {
            [paths addObject:[SCRIPTS_PATH stringByAppendingPathComponent:relative]];
            [enumerator skipDescendants];
        }
    }
    return [paths sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSString *)iconNameForCellTitle:(NSString *)title {
    if ([title containsString:@"Web"]) return @"globe";
    if ([title containsString:@"Touch"]) return @"hand.tap";
    if ([title containsString:@"Double-click"]) return @"bolt.badge.clock";
    if ([title containsString:@"Volume"]) return @"speaker.wave.2";
    if ([title containsString:@"Default Trigger"]) return @"play.square.stack";
    if ([title containsString:@"Switch App"]) return @"arrow.triangle.2.circlepath";
    if ([title containsString:@"Example"]) return @"folder";
    if ([title containsString:@"Registry"]) return @"list.bullet.rectangle";
    if ([title containsString:@"Dark"]) return @"moon";
    if ([title containsString:@"ZXTouch"]) return @"info.circle";
    return @"gearshape";
}

- (NSArray<NSDictionary *> *)remoteManagementCells {
    BOOL enabled = ZXRemoteDashboardIsEnabled();
    NSMutableArray *cells = [NSMutableArray arrayWithObject:@{
        @"type": @(SETTING_CELL_SWITCH),
        @"title": NSLocalizedString(@"webServer", nil),
        @"icon": @"globe",
        @"switch_click_handler": NSStringFromSelector(@selector(handleWebServerWithSwitchCellInstance:)),
        @"switch_init_status": @(enabled)
    }];
    if (enabled) {
        [cells addObject:@{
            @"type": @(SETTING_CELL_ENTRY),
            @"title": NSLocalizedString(@"dashboardURL", nil),
            @"secondary_title": NSLocalizedString(@"dashboardURLHint", nil),
            @"icon": @"link",
            @"row_click_handler": NSStringFromSelector(@selector(handleDashboardURLTap:))
        }];
    }
    return cells;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.title = NSLocalizedString(@"settingsTitle", nil);
    self.navigationController.tabBarItem.title = NSLocalizedString(@"settingsTitle", nil);
    configManager = [[ConfigManager alloc] initWithPath:SPRINGBOARD_CONFIG_PATH];

    UINib *SwitchCellNib = [UINib nibWithNibName:@"TableViewCellWithSwitch" bundle:nil];
    [_tableView registerNib:SwitchCellNib forCellReuseIdentifier:@"SwitchCell"];

    UINib *entryCellNib = [UINib nibWithNibName:@"TableViewCellWithEntry" bundle:nil];
    [_tableView registerNib:entryCellNib forCellReuseIdentifier:@"EntryCell"];
    
    _tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    _tableView.tableFooterView = [[UIView alloc] init];
    _tableView.rowHeight = 54;
    _tableView.separatorInset = UIEdgeInsetsMake(0, 52, 0, 0);
    [self reloadSettingsModel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (configManager) {
        [self reloadSettingsModel];
    }
}

- (void)reloadSettingsModel {
    configManager = [[ConfigManager alloc] initWithPath:SPRINGBOARD_CONFIG_PATH];
    BOOL doubleClickPopup = YES;
    if ([configManager getValueFromKey:@"double_click_volume_show_popup"])
        doubleClickPopup = [[configManager getValueFromKey:@"double_click_volume_show_popup"] boolValue];
    BOOL switchAppBeforeRunScript = YES;
    if ([configManager getValueFromKey:@"switch_app_before_run_script"])
        switchAppBeforeRunScript = [[configManager getValueFromKey:@"switch_app_before_run_script"] boolValue];
    BOOL showFinishedPopup = YES;
    if ([configManager getValueFromKey:@"show_script_finished_popup"])
    {
        showFinishedPopup = [[configManager getValueFromKey:@"show_script_finished_popup"] boolValue];
    }

    BOOL darkMode = [self darkModeEnabled];
    BOOL floatingButton = YES;
    if ([configManager getValueFromKey:@"floating_button_enabled"])
        floatingButton = [[configManager getValueFromKey:@"floating_button_enabled"] boolValue];
    CGFloat floatingOpacity = 0.55;
    id storedOpacity = [configManager getValueFromKey:@"floating_button_alpha"];
    if ([storedOpacity isKindOfClass:[NSNumber class]]) {
        floatingOpacity = [storedOpacity doubleValue];
        if (floatingOpacity < 0.15 || floatingOpacity > 1.0) floatingOpacity = 0.55;
    }
    NSString *opacityText = [NSString stringWithFormat:@"%d%%", (int)llround(floatingOpacity * 100.0)];

    sections = @[NSLocalizedString(@"remoteManagement", nil), NSLocalizedString(@"control", nil), NSLocalizedString(@"automation", nil), NSLocalizedString(@"script", nil), NSLocalizedString(@"appearance", nil), NSLocalizedString(@"about", nil)];
    cellsForEachSection = @[
        [self remoteManagementCells],
        @[
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"touchIndicator", nil), @"icon": @"hand.tap", @"secondary_title": @"", @"row_click_handler": NSStringFromSelector(@selector(handleTouchIndicatorWithEntryCellInstance:))},
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"floatingButton", nil), @"icon": @"circle.circle", @"switch_click_handler": NSStringFromSelector(@selector(handleFloatingButtonToggle:)), @"switch_init_status": @(floatingButton)},
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"floatingButtonOpacity", nil), @"icon": @"circle.lefthalf.filled", @"secondary_title": opacityText, @"row_click_handler": NSStringFromSelector(@selector(handleFloatingOpacityTap:))},
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"doubleClickShowPopup", nil), @"icon": @"speaker.wave.2", @"switch_click_handler": NSStringFromSelector(@selector(handlePopupWindowDoubleClick:)), @"switch_init_status": @(doubleClickPopup)}
        ],
        @[
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"volumeUp", nil), @"icon": @"speaker.plus", @"secondary_title": [self triggerSummaryForKey:ZX_TRIGGER_VOLUME_UP], @"trigger_key": ZX_TRIGGER_VOLUME_UP, @"row_click_handler": NSStringFromSelector(@selector(handleTriggerTap:))},
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"volumeDown", nil), @"icon": @"speaker.minus", @"secondary_title": [self triggerSummaryForKey:ZX_TRIGGER_VOLUME_DOWN], @"trigger_key": ZX_TRIGGER_VOLUME_DOWN, @"row_click_handler": NSStringFromSelector(@selector(handleTriggerTap:))},
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"homeButton", nil), @"icon": @"house", @"secondary_title": [self triggerSummaryForKey:ZX_TRIGGER_HOME], @"trigger_key": ZX_TRIGGER_HOME, @"row_click_handler": NSStringFromSelector(@selector(handleTriggerTap:))}
        ],
        @[
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"switchAppBeforePlaying", nil), @"icon": @"arrow.triangle.2.circlepath", @"switch_click_handler": NSStringFromSelector(@selector(handleSwitchAppBeforePlaying:)), @"switch_init_status": @(switchAppBeforeRunScript)},
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"scriptFinishedPopup", nil), @"icon": @"checkmark.circle", @"switch_click_handler": NSStringFromSelector(@selector(handleScriptFinishedPopupToggle:)), @"switch_init_status": @(showFinishedPopup)},
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"exampleScripts", nil), @"icon": @"folder", @"secondary_title": EXAMPLE_SCRIPTS_PATH, @"row_click_handler": NSStringFromSelector(@selector(handleExamplesTap:))},
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"scriptRegistry", nil), @"icon": @"list.bullet.rectangle", @"secondary_title": SCRIPT_REGISTRY_PATH, @"row_click_handler": NSStringFromSelector(@selector(handleRegistryTap:))}
        ],
        @[
            @{@"type": @(SETTING_CELL_SWITCH), @"title": NSLocalizedString(@"darkMode", nil), @"icon": @"moon", @"switch_click_handler": NSStringFromSelector(@selector(handleDarkModeToggle:)), @"switch_init_status": @(darkMode)}
        ],
        @[
            @{@"type": @(SETTING_CELL_ENTRY), @"title": NSLocalizedString(@"aboutZXTouch", nil), @"icon": @"info.circle", @"secondary_title": NSLocalizedString(@"aboutZXTouchDetail", nil), @"row_click_handler": NSStringFromSelector(@selector(handleCreditsTap:))}
        ]
    ];
    [_tableView reloadData];
}

- (void)notifyTweakCache:(NSString *)command {
    Socket *socket = [[Socket alloc] init];
    if ([socket connect:@"127.0.0.1" byPort:6000] != 0) return;
    [socket setRecvTimeout:3];
    [socket send:[command stringByAppendingString:@"\r\n"]];
    [socket recv:1024];
    [socket close];
}

- (void)handleFloatingButtonToggle:(UISwitch *)s {
    [configManager updateKey:@"floating_button_enabled" forValue:@([s isOn])];
    [configManager save];
    [self notifyTweakCache:@"904"];
}

- (void)handleFloatingOpacityTap:(TableViewCellWithEntry *)cell {
    CGFloat current = 0.55;
    id stored = [configManager getValueFromKey:@"floating_button_alpha"];
    if ([stored isKindOfClass:[NSNumber class]]) {
        current = [stored doubleValue];
        if (current < 0.2 || current > 1.0) current = 0.55;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"floatingButtonOpacity", nil)
                                                                   message:@"拖动后点保存"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *content = [[UIViewController alloc] init];
    content.preferredContentSize = CGSizeMake(270, 44);
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(8, 6, 254, 32)];
    slider.minimumValue = 0.2f;
    slider.maximumValue = 1.0f;
    slider.value = current;
    [content.view addSubview:slider];
    [alert setValue:content forKey:@"contentViewController"];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"save", nil) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [configManager updateKey:@"floating_button_alpha" forValue:@(slider.value)];
        [configManager save];
        [self notifyTweakCache:@"904"];
        [self reloadSettingsModel];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleSwitchAppBeforePlaying:(UISwitch*)s {
    if ([s isOn])
    {
        [configManager updateKey:@"switch_app_before_run_script" forValue:@(true)];
        [configManager save];
    }
    else
    {
        [configManager updateKey:@"switch_app_before_run_script" forValue:@(false)];
        [configManager save];
    }
    
    [self notifyTweakCache:@"902"];
}

- (void)handleScriptFinishedPopupToggle:(UISwitch*)s {
    // Controls the "Script Finished" popup the tweak shows when a script ends.
    // Stored in the SpringBoard config so Play.xm can read it; defaults to on so
    // existing installs keep their current behaviour.
    [configManager updateKey:@"show_script_finished_popup" forValue:@([s isOn])];
    [configManager save];
}

- (void)handlePopupWindowDoubleClick:(UISwitch*)s {
    if ([s isOn])
    {
        [configManager updateKey:@"double_click_volume_show_popup" forValue:@(true)];
        [configManager save];
    }
    else
    {
        [configManager updateKey:@"double_click_volume_show_popup" forValue:@(false)];
        [configManager save];
    }
    [self notifyTweakCache:@"901"];
}

- (void)setVolumeAction:(NSString *)action {
    [configManager updateKey:@"double_click_volume_action" forValue:action];
    [configManager save];
    [self reloadSettingsModel];
}

static const void *ZXTriggerKeyAssoc = &ZXTriggerKeyAssoc;

- (NSString *)triggerKeyFromCell:(TableViewCellWithEntry *)cell {
    NSString *key = objc_getAssociatedObject(cell, ZXTriggerKeyAssoc);
    if ([key isKindOfClass:[NSString class]] && key.length > 0) return key;
    return ZX_TRIGGER_VOLUME_DOWN;
}

- (void)setAction:(NSString *)action forTrigger:(NSString *)triggerKey {
    NSMutableDictionary *trigger = [self triggerConfigForKey:triggerKey];
    trigger[@"enabled"] = @(YES);
    trigger[@"action"] = action;
    [self saveTriggerConfig:trigger forKey:triggerKey];
}

- (void)setCount:(NSInteger)count forTrigger:(NSString *)triggerKey {
    NSMutableDictionary *trigger = [self triggerConfigForKey:triggerKey];
    trigger[@"enabled"] = @(YES);
    trigger[@"count"] = @(count);
    [self saveTriggerConfig:trigger forKey:triggerKey];
}

- (void)chooseScriptForTrigger:(NSString *)triggerKey fromCell:(UITableViewCell *)cell {
    NSArray<NSString *> *scripts = [self availableScriptPaths];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"runScriptEllipsis", nil)
        message:scripts.count ? NSLocalizedString(@"chooseScript", nil) : NSLocalizedString(@"noScriptsFound", nil)
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *script in scripts) {
        NSString *title = [[script lastPathComponent] stringByDeletingPathExtension];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSMutableDictionary *trigger = [self triggerConfigForKey:triggerKey];
            trigger[@"enabled"] = @(YES);
            trigger[@"action"] = ZX_ACTION_RUN_SCRIPT;
            trigger[@"script"] = script;
            [self saveTriggerConfig:trigger forKey:triggerKey];
        }]];
        if (sheet.actions.count >= 18) break;
    }

    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"enterPath", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self handleTriggerScriptTap:(TableViewCellWithEntry *)cell];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = cell;
        pop.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleTriggerTap:(TableViewCellWithEntry*)cell {
    NSString *triggerKey = [self triggerKeyFromCell:cell];
    NSMutableDictionary *trigger = [self triggerConfigForKey:triggerKey];
    NSString *title = [self triggerTitle:triggerKey];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
        message:[NSString stringWithFormat:NSLocalizedString(@"triggerCurrent", nil), [self triggerSummaryForKey:triggerKey]]
        preferredStyle:UIAlertControllerStyleActionSheet];

    if ([trigger[@"enabled"] boolValue]) {
        [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"disableTrigger", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            NSMutableDictionary *updated = [self triggerConfigForKey:triggerKey];
            updated[@"enabled"] = @(NO);
            [self saveTriggerConfig:updated forKey:triggerKey];
        }]];
    } else {
        [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"enableTrigger", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSMutableDictionary *updated = [self triggerConfigForKey:triggerKey];
            updated[@"enabled"] = @(YES);
            [self saveTriggerConfig:updated forKey:triggerKey];
        }]];
    }

    for (NSInteger count = 1; count <= 5; count++) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:NSLocalizedString(@"clickCount", nil), (long)count] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self setCount:count forTrigger:triggerKey];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"runScriptEllipsis", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self chooseScriptForTrigger:triggerKey fromCell:cell];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"togglePanel", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setAction:ZX_ACTION_TOGGLE_PANEL forTrigger:triggerKey];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"stopScript", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setAction:ZX_ACTION_STOP_SCRIPT forTrigger:triggerKey];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"toggleRecording", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setAction:ZX_ACTION_TOGGLE_RECORDING forTrigger:triggerKey];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"smartToggle", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setAction:ZX_ACTION_SMART_TOGGLE forTrigger:triggerKey];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = cell;
        pop.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleVolumeActionTap:(TableViewCellWithEntry*)cell {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"volumeDown", nil)
        message:NSLocalizedString(@"chooseScript", nil)
        preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"smartToggle", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setVolumeAction:ZX_ACTION_SMART_TOGGLE];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"togglePanel", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setVolumeAction:ZX_ACTION_TOGGLE_PANEL];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"stopScript", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setVolumeAction:ZX_ACTION_STOP_SCRIPT];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"toggleRecording", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setVolumeAction:ZX_ACTION_TOGGLE_RECORDING];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"runDefaultScript", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self setVolumeAction:ZX_ACTION_RUN_SCRIPT];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = cell;
        pop.sourceRect = cell.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)handleTriggerScriptTap:(TableViewCellWithEntry*)cell {
    NSString *triggerKey = [self triggerKeyFromCell:cell];
    NSMutableDictionary *trigger = [self triggerConfigForKey:triggerKey];
    NSString *current = trigger[@"script"] ?: @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"triggerScriptTitle", nil)
        message:NSLocalizedString(@"triggerScriptMessage", nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"/var/mobile/Library/ZXTouch/scripts/example.bdl";
        textField.text = current;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"clear", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSMutableDictionary *updated = [self triggerConfigForKey:triggerKey];
        updated[@"script"] = @"";
        [self saveTriggerConfig:updated forKey:triggerKey];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"save", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *path = alert.textFields.firstObject.text ?: @"";
        NSMutableDictionary *updated = [self triggerConfigForKey:triggerKey];
        updated[@"enabled"] = @(YES);
        updated[@"action"] = ZX_ACTION_RUN_SCRIPT;
        updated[@"script"] = path;
        [self saveTriggerConfig:updated forKey:triggerKey];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleWebServerWithSwitchCellInstance:(UISwitch*)s {
    if (![s isOn]) {
        ZXRemoteDashboardSetEnabled(NO);
        [self reloadSettingsModel];
        return;
    }

    if (!ZXRemoteDashboardSetEnabled(YES)) {
        [s setOn:NO animated:YES];
        NSString *dashboardError = ZXRemoteDashboardLastError();
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"dashboardUnavailable", nil)
            message:dashboardError.length ? dashboardError : NSLocalizedString(@"dashboardStartFailed", nil)
            buttonString:NSLocalizedString(@"ok", nil)];
        return;
    }

    [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"remoteDashboard", nil)
        message:[NSString stringWithFormat:NSLocalizedString(@"remoteDashboardMessage", nil), ZXRemoteDashboardURL()]
        buttonString:NSLocalizedString(@"ok", nil)];
    [self reloadSettingsModel];
}

- (void)handleDashboardURLTap:(TableViewCellWithEntry *)cell {
    NSString *url = ZXRemoteDashboardURL();
    UIPasteboard.generalPasteboard.string = url;
    [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"dashboardURL", nil)
        message:[NSString stringWithFormat:NSLocalizedString(@"copiedClipboard", nil), url]
        buttonString:NSLocalizedString(@"ok", nil)];
}

- (void)handleDarkModeToggle:(UISwitch*)s {
    BOOL dark = [s isOn];
    [configManager updateKey:@"dark_mode" forValue:@(dark)];
    [configManager save];

    [[NSUserDefaults standardUserDefaults] setBool:dark forKey:@"dark_mode"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // Apply to all app windows immediately (iOS 13+)
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *win in ((UIWindowScene *)scene).windows) {
                    win.overrideUserInterfaceStyle = style;
                }
            }
        }
    }

    [self notifyTweakCache:@"903"];
}

- (void)handleCreditsTap:(TableViewCellWithEntry*)cell {
    // Show a brief about alert
    [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"aboutZXTouch", nil)
        message:NSLocalizedString(@"creditsMessage", nil)
        buttonString:NSLocalizedString(@"ok", nil)];
}

- (void)handleExamplesTap:(TableViewCellWithEntry*)cell {
    NSArray *examples = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:EXAMPLE_SCRIPTS_PATH error:nil];
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"exampleScriptsMessage", nil), (unsigned long)examples.count, EXAMPLE_SCRIPTS_PATH];
    [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"exampleScripts", nil) message:message buttonString:NSLocalizedString(@"ok", nil)];
}

- (void)handleRegistryTap:(TableViewCellWithEntry*)cell {
    NSDictionary *registry = [NSDictionary dictionaryWithContentsOfFile:SCRIPT_REGISTRY_PATH];
    NSString *version = registry[@"version"] ?: NSLocalizedString(@"missing", nil);
    NSString *examplesPath = registry[@"examplesPath"] ?: EXAMPLE_SCRIPTS_PATH;
    NSArray *scripts = registry[@"scripts"] ?: @[];
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"scriptRegistryMessage", nil), version, (unsigned long)scripts.count, examplesPath];
    [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"scriptRegistry", nil) message:message buttonString:NSLocalizedString(@"ok", nil)];
}

- (void)handleTouchIndicatorWithEntryCellInstance:(TableViewCellWithEntry*)cell {
    if ([cell isSelected])
    {
        UIStoryboard *sb = [UIStoryboard storyboardWithName:@"SettingPages" bundle:nil];
        TouchIndicatorConfigurationViewController *touchIndicatorConfigurationViewController = [sb instantiateViewControllerWithIdentifier:@"TouchIndicatorConfigurationPage"];
        [self.navigationController pushViewController:touchIndicatorConfigurationViewController animated:YES];
        //[self.navigationController setTitle:@"Touch Indicator"];
    }

}


//配置每个section(段）有多少row（行） cell
//默认只有一个section
-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return cellsForEachSection[section].count;
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return sections.count;
}

//每行显示什么东西
-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{

    UITableViewCell *result;
    

    NSInteger indexInCurrentSection = indexPath.row;

    
    NSArray* cellList = cellsForEachSection[indexPath.section];

    NSDictionary *cellInfo = cellList[indexInCurrentSection];
    if ([cellInfo[@"type"] intValue] == SETTING_CELL_SWITCH)
    {
        static NSString *cellID = @"SwitchCell";

        TableViewCellWithSwitch *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
        
        //判断队列里面是否有这个cell 没有自己创建，有直接使用
        if (cell == nil) {
            //没有,创建一个
            cell = [[TableViewCellWithSwitch alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
        }
        
        cell.title.text = cellInfo[@"title"];
        cell.title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        cell.iconView.image = ZXSettingsSymbol(cellInfo[@"icon"] ?: @"gearshape");
        cell.iconView.tintColor = [UIColor systemBlueColor];
        cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [cell.switchBtn removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
        [cell.switchBtn addTarget:self action:NSSelectorFromString(cellInfo[@"switch_click_handler"]) forControlEvents:UIControlEventValueChanged];
        [cell.switchBtn setOn:[cellInfo[@"switch_init_status"] boolValue]];
        
        result = cell;
    }
    else if ([cellInfo[@"type"] intValue] == SETTING_CELL_ENTRY)
    {
        static NSString *cellID = @"EntryCell";

        TableViewCellWithEntry *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
        
        //判断队列里面是否有这个cell 没有自己创建，有直接使用
        if (cell == nil) {
            //没有,创建一个
            NSLog(@"create a setting cell switch");
            cell = [[TableViewCellWithEntry alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];
        }
        
        cell.title.text = cellInfo[@"title"];
        cell.subTitle.text = cellInfo[@"secondary_title"];
        cell.title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        cell.subTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        cell.subTitle.textColor = [UIColor secondaryLabelColor];
        cell.iconView.image = ZXSettingsSymbol(cellInfo[@"icon"] ?: @"gearshape");
        cell.iconView.tintColor = [UIColor systemBlueColor];
        cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.clickHandler = cellInfo[@"row_click_handler"];
        if (cellInfo[@"trigger_key"]) {
            objc_setAssociatedObject(cell, ZXTriggerKeyAssoc, cellInfo[@"trigger_key"], OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        
        result = cell;
    }
    
    
    return result;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
    if ([cell isKindOfClass:[TableViewCellWithEntry class]])
    {
        TableViewCellWithEntry *entry = (TableViewCellWithEntry*)cell;
        [self performSelector:NSSelectorFromString(entry.clickHandler) withObject:entry];
    }
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {

}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}


- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *resultView = [[UIView alloc] init];
    //view.backgroundColor = [UIColor greenColor];
    
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    title.textColor = [UIColor secondaryLabelColor];

    title.text = sections[section];

    
    [resultView addSubview:title];
    
    [[title.leftAnchor constraintEqualToAnchor:resultView.leftAnchor constant:20] setActive:YES];
    [[title.bottomAnchor constraintEqualToAnchor:resultView.bottomAnchor constant:-5] setActive:YES];

    return resultView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 38;
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
