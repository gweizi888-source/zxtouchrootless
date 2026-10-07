//
//  AdderPopOverViewController.m
//  zxtouch
//
//  Created by Jason on 2021/1/16.
//

#import "AdderPopOverViewController.h"
#import "Util.h"
#import "Config.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <zlib.h>

static const void *kZipImporterKey = &kZipImporterKey;
static NSError *zipError(NSString *message);

@interface AdderPopOverViewController ()

@end

static BOOL ZXFilzaIsInstalled(void) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (workspaceClass) {
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        SEL installedSelector = @selector(applicationIsInstalled:);
        if ([workspace respondsToSelector:installedSelector]) {
            BOOL (*installed)(id, SEL, NSString *) = (BOOL (*)(id, SEL, NSString *))objc_msgSend;
            if (installed(workspace, installedSelector, @"com.tigisoftware.Filza")) return YES;
        }
    }
    NSFileManager *files = [NSFileManager defaultManager];
    NSArray *candidates = @[
        @"/Applications/Filza.app",
        @"/var/jb/Applications/Filza.app",
    ];
    for (NSString *path in candidates) {
        if ([files fileExistsAtPath:path]) return YES;
    }
    NSString *bundleRoot = @"/var/containers/Bundle/Application";
    for (NSString *name in [files contentsOfDirectoryAtPath:bundleRoot error:nil]) {
        if (![name hasPrefix:@".jbroot-"]) continue;
        NSString *filza = [[bundleRoot stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"Applications/Filza.app"];
        if ([files fileExistsAtPath:filza]) return YES;
    }
    return NO;
}

static void ZXOpenFilzaAtPath(NSString *path) {
    NSString *folder = path.length ? path : @"/var/mobile";
    NSString *escaped = [folder stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSURL *url = [NSURL URLWithString:[@"filza://view" stringByAppendingString:escaped ?: @"/var/mobile"]];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@interface ZXZipFolderController : UITableViewController
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) void (^pickHandler)(NSString *path);
@property (nonatomic, copy) void (^cancelHandler)(void);
@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@end

@implementation ZXZipFolderController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择 Zip";
    self.tableView.rowHeight = 52;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Filza" style:UIBarButtonItemStylePlain target:self action:@selector(openFilza)];
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(closeBrowser)];
    }
    [self reloadEntries];
}

- (void)reloadEntries {
    NSMutableArray *entries = [NSMutableArray array];
    if (self.directory.length && ![self.directory isEqualToString:@"/var/mobile"]) {
        NSString *parent = [self.directory stringByDeletingLastPathComponent];
        if (parent.length == 0) parent = @"/";
        [entries addObject:@{@"name": @"返回上一级", @"path": parent, @"kind": @"up"}];
    }
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.directory error:nil] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *full = [self.directory stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir]) continue;
        if (isDir) {
            [entries addObject:@{@"name": name, @"path": full, @"kind": @"dir"}];
        } else if ([[name pathExtension].lowercaseString isEqualToString:@"zip"]) {
            [entries addObject:@{@"name": name, @"path": full, @"kind": @"zip"}];
        }
    }
    self.entries = entries;
    [self.tableView reloadData];
}

- (void)closeBrowser {
    [self dismissViewControllerAnimated:YES completion:self.cancelHandler];
}

- (void)promptInstallFilza {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未安装 Filza"
                                                                   message:@"请先在 Sileo 或 Zebra 安装 Filza，然后再用它选择 zip。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openFilza {
    if (!ZXFilzaIsInstalled()) {
        [self promptInstallFilza];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"用 Filza 选择"
                                                                   message:@"接下来会打开 Filza。点开 zip 后，选择「打开方式」里的 ZXTouch，就会导入。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"打开 Filza" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        ZXOpenFilzaAtPath(self.directory);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)self.entries.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"zip-row"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"zip-row"];
    if (self.entries.count == 0) {
        cell.textLabel.text = @"这个目录没有 zip";
        cell.detailTextLabel.text = @"进入子目录，或点右上角用 Filza 选择";
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *entry = self.entries[indexPath.row];
    cell.textLabel.text = entry[@"name"];
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    NSString *kind = entry[@"kind"];
    if ([kind isEqualToString:@"zip"]) {
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textColor = [UIColor systemBlueColor];
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.textColor = [UIColor labelColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.entries.count) return;
    NSDictionary *entry = self.entries[indexPath.row];
    NSString *kind = entry[@"kind"];
    NSString *path = entry[@"path"];
    if ([kind isEqualToString:@"zip"]) {
        void (^pick)(NSString *) = self.pickHandler;
        [self dismissViewControllerAnimated:YES completion:^{
            if (pick) pick(path);
        }];
        return;
    }
    ZXZipFolderController *next = [[ZXZipFolderController alloc] initWithStyle:UITableViewStyleGrouped];
    next.directory = path;
    next.pickHandler = self.pickHandler;
    next.cancelHandler = self.cancelHandler;
    [self.navigationController pushViewController:next animated:YES];
}

@end


@implementation AdderPopOverViewController
{
    NSString *currentFolder;
    ScriptListViewController *upperLevel;
}


- (UIModalPresentationStyle) adaptivePresentationStyleForPresentationController: (UIPresentationController * ) controller {
    return UIModalPresentationNone;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.preferredContentSize = CGSizeMake(300, 150);
    // Do any additional setup after loading the view from its nib.
}

- (void)setFolder:(NSString*)path {
    currentFolder = [path stringByStandardizingPath];
}

- (void)setUpperLevelViewController:(ScriptListViewController*)vc{
    upperLevel = vc;
}

- (IBAction)createScriptButtonClick:(id)sender {
    if (!self->currentFolder)
    {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptPathNotSet", nil) buttonString:NSLocalizedString(@"ok", nil)];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"scriptName", nil)
                                                                    message:NSLocalizedString(@"enterScriptName", nil)
                                                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *submit = [UIAlertAction actionWithTitle:NSLocalizedString(@"submit", nil) style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {
                                                       if (alert.textFields.count > 0) {
                                                           UITextField *textField = [alert.textFields firstObject];
                                                           if ([textField.text length] != 0)
                                                           {
                                                               // create folder
                                                               BOOL isDir;
                                                               NSError *err = nil;
                                                               NSFileManager *fileManager= [NSFileManager defaultManager];
                                                               NSString* folderToAddPath = [self->currentFolder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bdl", textField.text]];
                                                               if([fileManager fileExistsAtPath:folderToAddPath isDirectory:&isDir] && isDir)
                                                               {
                                                                   [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptAlreadyExists", nil) buttonString:NSLocalizedString(@"ok", nil)];
                                                               }
                                                               else
                                                               {
                                                                   [fileManager createDirectoryAtPath:folderToAddPath withIntermediateDirectories:YES attributes:nil error:&err];
                                                                   if (err)
                                                                   {
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createScriptFailed", nil), err] buttonString:NSLocalizedString(@"ok", nil)];
                                                                   }
                                                                   
                                                                   // add plist file
                                                                   NSDictionary *scriptInfo = @{@"Entry": @"main.py", @"FrontApp": @"", @"Orientation": @"1"};
                                                                   NSString *plistPath = [folderToAddPath stringByAppendingPathComponent:@"info.plist"];
                                                                   [scriptInfo writeToFile:plistPath atomically:YES];
                                                                   
                                                                   // add python file
                                                                   NSDateFormatter *dateFormatter=[[NSDateFormatter alloc] init];
                                                                   [dateFormatter setDateFormat:@"MM/dd/yyyy hh:mm:ss"];
                                                                   NSString *currentDateTime = [dateFormatter stringFromDate:[NSDate date]];
                                                                   NSString *initContent = [NSString stringWithFormat:@"#This script is created at %@\n#ZXTouch module documentation on Github: https://github.com/xuan32546/IOS13-SimulateTouch/\n\nfrom zxtouch.client import zxtouch\n\n\n#insert your code here.", currentDateTime];
                                                                   
                                                                   [initContent writeToFile:[folderToAddPath stringByAppendingPathComponent:@"main.py"] atomically:YES encoding:NSUTF8StringEncoding error:&err];
                                                                   if (err)
                                                                   {
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createScriptFailed", nil), err] buttonString:NSLocalizedString(@"ok", nil)];
                                                                   }
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                       [self->upperLevel refreshTable];
                                                                   });
                                                               }
                                                               
                                                           }
                                                           else
                                                           {
                                                               [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptEmptyName", nil) buttonString:NSLocalizedString(@"ok", nil)];
                                                           }
                                                       }
                                                   }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {}];

    [alert addAction:cancel];
    [alert addAction:submit];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        //textField.placeholder = @""; // if needs
    }];

    [self presentViewController:alert animated:YES completion:nil];
    
    
}

- (IBAction)createFolderButtonClick:(id)sender {
    if (!self->currentFolder)
    {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderPathNotSet", nil) buttonString:NSLocalizedString(@"ok", nil)];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"folderName", nil)
                                                                    message:NSLocalizedString(@"enterFolderName", nil)
                                                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *submit = [UIAlertAction actionWithTitle:NSLocalizedString(@"submit", nil) style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {
                                                       if (alert.textFields.count > 0) {
                                                           UITextField *textField = [alert.textFields firstObject];
                                                           if ([textField.text length] != 0)
                                                           {

                                                               // create folder
                                                               BOOL isDir;
                                                               NSError *err = nil;
                                                               NSFileManager *fileManager= [NSFileManager defaultManager];
                                                               NSString* folderToAddPath = [self->currentFolder stringByAppendingPathComponent:textField.text];
                                                               if([fileManager fileExistsAtPath:folderToAddPath isDirectory:&isDir] && isDir)
                                                               {
                                                                   [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderAlreadyExists", nil) buttonString:NSLocalizedString(@"ok", nil)];
                                                               }
                                                               else
                                                               {
                                                                   [fileManager createDirectoryAtPath:folderToAddPath withIntermediateDirectories:YES attributes:nil error:&err];
                                                                   if (err)
                                                                   {
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createFolderFailed", nil), err] buttonString:NSLocalizedString(@"ok", nil)];
                                                                   }
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                       [self->upperLevel refreshTable];
                                                                   });
                                                               }
                                                               
                                                           }
                                                           else
                                                           {
                                                               [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderEmptyName", nil) buttonString:NSLocalizedString(@"ok", nil)];
                                                           }
                                                       }
                                                   }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) {}];

    [alert addAction:cancel];
    [alert addAction:submit];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        //textField.placeholder = @""; // if needs
    }];

    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)availableDestinationPathForFileName:(NSString *)fileName {
    NSString *cleanName = [fileName lastPathComponent];
    if (cleanName.length == 0) {
        cleanName = @"Imported File";
    }

    NSString *base = [cleanName stringByDeletingPathExtension];
    NSString *extension = [cleanName pathExtension];
    NSString *candidate = [currentFolder stringByAppendingPathComponent:cleanName];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSInteger index = 2;

    while ([fileManager fileExistsAtPath:candidate]) {
        NSString *nextName = extension.length
            ? [NSString stringWithFormat:@"%@ %ld.%@", base, (long)index, extension]
            : [NSString stringWithFormat:@"%@ %ld", base, (long)index];
        candidate = [currentFolder stringByAppendingPathComponent:nextName];
        index += 1;
    }

    return candidate;
}

- (UIViewController *)importPresenter {
    if (self->upperLevel) {
        return self->upperLevel.navigationController ?: self->upperLevel;
    }
    UIViewController *root = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindow *window = ((UIWindowScene *)scene).windows.firstObject;
        if (window.rootViewController) {
            root = window.rootViewController;
            break;
        }
    }
    while (root.presentedViewController) root = root.presentedViewController;
    return root ?: self;
}

- (void)releaseZipImporter {
    UIViewController *presenter = [self importPresenter];
    if (presenter) {
        objc_setAssociatedObject(presenter, kZipImporterKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    objc_setAssociatedObject(UIApplication.sharedApplication, kZipImporterKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

- (void)finishImportWithError:(NSError *)err destination:(NSString *)destinationPath {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = [self importPresenter];
        [self releaseZipImporter];
        if (err) {
            [Util showAlertBoxWithOneOption:presenter title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:NSLocalizedString(@"importFailed", nil), err.localizedDescription] buttonString:NSLocalizedString(@"ok", nil)];
            return;
        }

        [self->upperLevel refreshTable];
        [Util showAlertBoxWithOneOption:presenter title:NSLocalizedString(@"imported", nil) message:[NSString stringWithFormat:NSLocalizedString(@"importedMessage", nil), [destinationPath lastPathComponent]] buttonString:NSLocalizedString(@"ok", nil)];
    });
}

- (void)collectZipFilesInto:(NSMutableArray<NSString *> *)outPaths
                   fromPath:(NSString *)path
                      depth:(NSInteger)depth
{
    if (depth > 2 || outPaths.count >= 40 || path.length == 0) return;
    NSError *err = nil;
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&err];
    if (err || names.count == 0) return;

    for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *full = [path stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir]) continue;
        if (isDir) {
            [self collectZipFilesInto:outPaths fromPath:full depth:depth + 1];
        } else if ([[name pathExtension].lowercaseString isEqualToString:@"zip"]) {
            [outPaths addObject:full];
        }
        if (outPaths.count >= 40) return;
    }
}

- (NSArray<NSString *> *)localZipPaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSArray *roots = @[
        @"/var/mobile/Downloads",
        @"/var/mobile/Documents",
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"],
        @"/var/mobile/Library/ZXTouch",
    ];
    for (NSString *root in roots) {
        [self collectZipFilesInto:paths fromPath:root depth:0];
    }
    return paths;
}

- (void)importZipFromPath:(NSString *)path {
    if (path.length == 0) {
        [self finishImportWithError:zipError(@"请选择 .zip 文件。") destination:nil];
        return;
    }
    NSString *clean = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    clean = [clean stringByStandardizingPath];
    if (![[clean pathExtension].lowercaseString isEqualToString:@"zip"]) {
        [self finishImportWithError:zipError(@"请选择 .zip 文件。") destination:nil];
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:clean]) {
        [self finishImportWithError:zipError(@"找不到这个文件。") destination:nil];
        return;
    }
    NSError *err = nil;
    NSString *destination = [self importZipAtURL:[NSURL fileURLWithPath:clean] error:&err];
    [self finishImportWithError:err destination:destination];
}

- (void)showZipBrowser {
    NSString *start = @"/var/mobile";
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/Downloads"]) {
        start = @"/var/mobile/Downloads";
    }
    ZXZipFolderController *browser = [[ZXZipFolderController alloc] initWithStyle:UITableViewStyleGrouped];
    browser.directory = start;
    browser.pickHandler = ^(NSString *path) {
        [self importZipFromPath:path];
    };
    browser.cancelHandler = ^{
        [self releaseZipImporter];
    };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:browser];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    nav.presentationController.delegate = self;
    [[self importPresenter] presentViewController:nav animated:YES completion:nil];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
    if ([presentationController.presentedViewController isKindOfClass:[UINavigationController class]]) {
        [self releaseZipImporter];
    }
}

- (IBAction)importZipButtonClick:(id)sender {
    if (!self->currentFolder) {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderPathNotSet", nil) buttonString:NSLocalizedString(@"ok", nil)];
        return;
    }

    UIViewController *presenter = [self importPresenter];
    objc_setAssociatedObject(presenter, kZipImporterKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self dismissViewControllerAnimated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!ZXFilzaIsInstalled()) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未安装 Filza"
                                                                               message:@"没有检测到 Filza。可以先在下面的目录里点 zip，或安装 Filza 后再用右上角打开。"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"先从目录选" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                    [self showZipBrowser];
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
                    [self releaseZipImporter];
                }]];
                [[self importPresenter] presentViewController:alert animated:YES completion:nil];
                return;
            }
            [self showZipBrowser];
        });
    }];
}

+ (void)importExternalZipAtURL:(NSURL *)url {
    if (!url) return;
    NSString *path = url.path;
    if (path.length == 0) return;
    AdderPopOverViewController *importer = [[AdderPopOverViewController alloc] init];
    [importer setFolder:SCRIPTS_PATH];
    objc_setAssociatedObject(UIApplication.sharedApplication, kZipImporterKey, importer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL access = [url startAccessingSecurityScopedResource];
    [importer importZipFromPath:path];
    if (access) [url stopAccessingSecurityScopedResource];
}

- (IBAction)importImageButtonClick:(id)sender {
    if (!self->currentFolder) {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderPathNotSet", nil) buttonString:NSLocalizedString(@"ok", nil)];
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"photoLibraryUnavailable", nil) buttonString:NSLocalizedString(@"ok", nil)];
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[(NSString *)kUTTypeImage];
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

static uint16_t zipRead16(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static uint32_t zipRead32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static NSError *zipError(NSString *message) {
    return [NSError errorWithDomain:@"ZXTouchImport" code:2 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL zipPathIsSafe(NSString *name) {
    if (name.length == 0 || [name hasPrefix:@"/"] || [name hasPrefix:@"\\"]) {
        return NO;
    }
    for (NSString *part in [name pathComponents]) {
        if ([part isEqualToString:@".."]) {
            return NO;
        }
    }
    return YES;
}

static NSData *zipInflate(NSData *input, uint32_t expectedSize) {
    if (expectedSize == 0) {
        return [NSData data];
    }
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        return nil;
    }
    NSMutableData *output = [NSMutableData dataWithLength:expectedSize];
    stream.next_in = (Bytef *)input.bytes;
    stream.avail_in = (uInt)input.length;
    stream.next_out = output.mutableBytes;
    stream.avail_out = expectedSize;
    int status = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);
    if (status != Z_STREAM_END) {
        return nil;
    }
    return output;
}

- (BOOL)unzipData:(NSData *)data toDirectory:(NSString *)directory error:(NSError **)error {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length < 22) {
        if (error) *error = zipError(@"这个压缩包是空的或已损坏。");
        return NO;
    }

    NSInteger endOffset = NSNotFound;
    NSUInteger scan = MIN(length, (NSUInteger)65557);
    for (NSInteger index = (NSInteger)length - 22; index >= (NSInteger)length - (NSInteger)scan && index >= 0; index--) {
        if (zipRead32(bytes + index) == 0x06054b50) {
            endOffset = index;
            break;
        }
    }
    if (endOffset == NSNotFound) {
        if (error) *error = zipError(@"这不是 zip 压缩包。");
        return NO;
    }

    uint16_t entryCount = zipRead16(bytes + endOffset + 10);
    uint32_t directoryOffset = zipRead32(bytes + endOffset + 16);
    if (directoryOffset >= length) {
        if (error) *error = zipError(@"这个压缩包已损坏。");
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSUInteger offset = directoryOffset;
    BOOL extracted = NO;

    for (uint16_t entry = 0; entry < entryCount; entry++) {
        if (offset + 46 > length || zipRead32(bytes + offset) != 0x02014b50) {
            if (error) *error = zipError(@"这个压缩包已损坏。");
            return NO;
        }
        uint16_t flags = zipRead16(bytes + offset + 8);
        uint16_t method = zipRead16(bytes + offset + 10);
        uint32_t compressedSize = zipRead32(bytes + offset + 20);
        uint32_t uncompressedSize = zipRead32(bytes + offset + 24);
        uint16_t nameLength = zipRead16(bytes + offset + 28);
        uint16_t extraLength = zipRead16(bytes + offset + 30);
        uint16_t commentLength = zipRead16(bytes + offset + 32);
        uint32_t localOffset = zipRead32(bytes + offset + 42);
        if (offset + 46 + nameLength > length) {
            if (error) *error = zipError(@"这个压缩包已损坏。");
            return NO;
        }
        NSString *name = [[NSString alloc] initWithBytes:bytes + offset + 46 length:nameLength encoding:NSUTF8StringEncoding];
        if (!name) {
            name = [[NSString alloc] initWithBytes:bytes + offset + 46 length:nameLength encoding:NSASCIIStringEncoding];
        }
        offset += 46 + nameLength + extraLength + commentLength;

        if (!zipPathIsSafe(name) || [name containsString:@"__MACOSX"] || compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF) {
            continue;
        }
        if ((flags & 1) != 0) {
            if (error) *error = zipError(@"不支持加密的压缩包。");
            return NO;
        }
        if (localOffset + 30 > length) {
            if (error) *error = zipError(@"这个压缩包已损坏。");
            return NO;
        }
        uint16_t localNameLength = zipRead16(bytes + localOffset + 26);
        uint16_t localExtraLength = zipRead16(bytes + localOffset + 28);
        NSUInteger dataOffset = localOffset + 30 + localNameLength + localExtraLength;
        if (dataOffset + compressedSize > length) {
            if (error) *error = zipError(@"这个压缩包已损坏。");
            return NO;
        }

        BOOL isDirectory = [name hasSuffix:@"/"] || [name hasSuffix:@"\\"];
        NSString *destination = [directory stringByAppendingPathComponent:name];
        if (isDirectory) {
            [fileManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:nil];
            continue;
        }
        [fileManager createDirectoryAtPath:[destination stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];

        NSData *compressed = [NSData dataWithBytes:bytes + dataOffset length:compressedSize];
        NSData *contents = nil;
        if (method == 0) {
            contents = compressed;
        } else if (method == 8) {
            contents = zipInflate(compressed, uncompressedSize);
        } else {
            if (error) *error = zipError(@"这个压缩包的压缩方式无法读取。");
            return NO;
        }
        if (!contents) {
            if (error) *error = zipError(@"压缩包里有文件解压失败。");
            return NO;
        }
        if (![contents writeToFile:destination options:NSDataWritingAtomic error:error]) {
            return NO;
        }
        extracted = YES;
    }

    if (!extracted) {
        if (error) *error = zipError(@"压缩包里没有文件。");
        return NO;
    }
    return YES;
}

- (NSString *)importZipAtURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) {
        return nil;
    }

    NSString *tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    if (![self unzipData:data toDirectory:tempDirectory error:error]) {
        [[NSFileManager defaultManager] removeItemAtPath:tempDirectory error:nil];
        return nil;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:[tempDirectory stringByAppendingPathComponent:@"__MACOSX"] error:nil];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *name in [fileManager contentsOfDirectoryAtPath:tempDirectory error:nil]) {
        if (![name hasPrefix:@"."]) {
            [items addObject:name];
        }
    }

    NSString *source = tempDirectory;
    NSString *folderName = [[url.lastPathComponent stringByDeletingPathExtension] length] ? [url.lastPathComponent stringByDeletingPathExtension] : @"Imported Script";
    if (items.count == 1) {
        NSString *onlyPath = [tempDirectory stringByAppendingPathComponent:items[0]];
        BOOL isDirectory = NO;
        if ([fileManager fileExistsAtPath:onlyPath isDirectory:&isDirectory] && isDirectory) {
            source = onlyPath;
            folderName = items[0];
        }
    }
    if ([source isEqualToString:tempDirectory] &&
        [fileManager fileExistsAtPath:[tempDirectory stringByAppendingPathComponent:@"info.plist"]] &&
        ![[folderName pathExtension].lowercaseString isEqualToString:@"bdl"]) {
        folderName = [folderName stringByAppendingPathExtension:@"bdl"];
    }

    NSString *destination = [self availableDestinationPathForFileName:folderName];
    NSError *moveError = nil;
    if (![fileManager moveItemAtPath:source toPath:destination error:&moveError]) {
        [fileManager removeItemAtPath:tempDirectory error:nil];
        if (error) *error = moveError;
        return nil;
    }
    if (![source isEqualToString:tempDirectory]) {
        [fileManager removeItemAtPath:tempDirectory error:nil];
    }
    return destination;
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) {
        return;
    }

    BOOL didAccess = [url startAccessingSecurityScopedResource];
    NSString *extension = url.pathExtension.lowercaseString;
    NSError *err = nil;
    NSString *destinationPath = nil;
    if (![extension isEqualToString:@"zip"]) {
        err = zipError(@"请选择 .zip 文件。");
    } else {
        destinationPath = [self importZipAtURL:url error:&err];
    }
    if (didAccess) {
        [url stopAccessingSecurityScopedResource];
    }

    [self finishImportWithError:err destination:destinationPath];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self documentPicker:controller didPickDocumentsAtURLs:@[url]];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self releaseZipImporter];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSURL *imageURL = info[UIImagePickerControllerImageURL];
    NSString *fileName = imageURL.lastPathComponent.length ? imageURL.lastPathComponent : @"Imported Image.png";
    NSString *destinationPath = [self availableDestinationPathForFileName:fileName];

    NSError *err = nil;
    NSData *imageData = nil;
    NSString *extension = [[destinationPath pathExtension] lowercaseString];
    if ([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"]) {
        imageData = UIImageJPEGRepresentation(image, 0.92);
    } else {
        if (extension.length == 0) {
            destinationPath = [destinationPath stringByAppendingPathExtension:@"png"];
        }
        imageData = UIImagePNGRepresentation(image);
    }

    if (!imageData) {
        err = [NSError errorWithDomain:@"ZXTouchImport" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无法读取所选图片。"}];
    } else {
        [imageData writeToFile:destinationPath options:NSDataWritingAtomic error:&err];
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        [self finishImportWithError:err destination:destinationPath];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}
@end
