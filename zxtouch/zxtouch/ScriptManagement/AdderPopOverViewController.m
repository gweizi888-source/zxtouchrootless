//
//  AdderPopOverViewController.m
//  zxtouch
//
//  Created by Jason on 2021/1/16.
//

#import "AdderPopOverViewController.h"
#import "Util.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/runtime.h>
#import <zlib.h>

static const void *kZipImporterKey = &kZipImporterKey;

@interface AdderPopOverViewController ()

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
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptPathNotSet", nil) buttonString:@"OK"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Script Name"
                                                                    message:@"Please enter the script name"
                                                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *submit = [UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault
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
                                                                   [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptAlreadyExists", nil) buttonString:@"OK"];
                                                               }
                                                               else
                                                               {
                                                                   [fileManager createDirectoryAtPath:folderToAddPath withIntermediateDirectories:YES attributes:nil error:&err];
                                                                   if (err)
                                                                   {
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createScriptFailed", nil), err] buttonString:@"OK"];
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
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createScriptFailed", nil), err] buttonString:@"OK"];
                                                                   }
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                       [self->upperLevel refreshTable];
                                                                   });
                                                               }
                                                               
                                                           }
                                                           else
                                                           {
                                                               [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createScriptEmptyName", nil) buttonString:@"OK"];
                                                           }
                                                       }
                                                   }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault
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
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderPathNotSet", nil) buttonString:@"OK"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Folder Name"
                                                                    message:@"Please enter the folder name"
                                                             preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *submit = [UIAlertAction actionWithTitle:@"Submit" style:UIAlertActionStyleDefault
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
                                                                   [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderAlreadyExists", nil) buttonString:@"OK"];
                                                               }
                                                               else
                                                               {
                                                                   [fileManager createDirectoryAtPath:folderToAddPath withIntermediateDirectories:YES attributes:nil error:&err];
                                                                   if (err)
                                                                   {
                                                                       [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"%@%@", NSLocalizedString(@"createFolderFailed", nil), err] buttonString:@"OK"];
                                                                   }
                                                                   dispatch_async(dispatch_get_main_queue(), ^{
                                                                       [self->upperLevel refreshTable];
                                                                   });
                                                               }
                                                               
                                                           }
                                                           else
                                                           {
                                                               [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderEmptyName", nil) buttonString:@"OK"];
                                                           }
                                                       }
                                                   }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault
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
    return self->upperLevel ?: self.presentingViewController ?: self;
}

- (void)releaseZipImporter {
    UIViewController *presenter = [self importPresenter];
    if (presenter) {
        objc_setAssociatedObject(presenter, kZipImporterKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
}

- (void)finishImportWithError:(NSError *)err destination:(NSString *)destinationPath {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = [self importPresenter];
        [self releaseZipImporter];
        if (err) {
            [Util showAlertBoxWithOneOption:presenter title:NSLocalizedString(@"error", nil) message:[NSString stringWithFormat:@"Import failed: %@", err.localizedDescription] buttonString:@"OK"];
            return;
        }

        [self->upperLevel refreshTable];
        [Util showAlertBoxWithOneOption:presenter title:@"Imported" message:[NSString stringWithFormat:@"%@ was added.", [destinationPath lastPathComponent]] buttonString:@"OK"];
    });
}

- (IBAction)importZipButtonClick:(id)sender {
    if (!self->currentFolder) {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderPathNotSet", nil) buttonString:@"OK"];
        return;
    }

    UIViewController *presenter = [self importPresenter];
    objc_setAssociatedObject(presenter, kZipImporterKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self dismissViewControllerAnimated:YES completion:^{
        // Zip-only types make the system document browser fail with
        // "There was a problem displaying the document". Ask for any file,
        // then only accept .zip. Present from the script list, not this popover.
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[(NSString *)kUTTypeData, (NSString *)kUTTypeItem] inMode:UIDocumentPickerModeImport];
        picker.delegate = self;
        picker.modalPresentationStyle = UIModalPresentationFullScreen;
        [presenter presentViewController:picker animated:YES completion:nil];
    }];
}

- (IBAction)importImageButtonClick:(id)sender {
    if (!self->currentFolder) {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:NSLocalizedString(@"createFolderPathNotSet", nil) buttonString:@"OK"];
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [Util showAlertBoxWithOneOption:self title:NSLocalizedString(@"error", nil) message:@"Photo Library is not available." buttonString:@"OK"];
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
        if (error) *error = zipError(@"This zip file is empty or damaged.");
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
        if (error) *error = zipError(@"This file is not a zip archive.");
        return NO;
    }

    uint16_t entryCount = zipRead16(bytes + endOffset + 10);
    uint32_t directoryOffset = zipRead32(bytes + endOffset + 16);
    if (directoryOffset >= length) {
        if (error) *error = zipError(@"This zip file is damaged.");
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSUInteger offset = directoryOffset;
    BOOL extracted = NO;

    for (uint16_t entry = 0; entry < entryCount; entry++) {
        if (offset + 46 > length || zipRead32(bytes + offset) != 0x02014b50) {
            if (error) *error = zipError(@"This zip file is damaged.");
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
            if (error) *error = zipError(@"This zip file is damaged.");
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
            if (error) *error = zipError(@"Encrypted zip files are not supported.");
            return NO;
        }
        if (localOffset + 30 > length) {
            if (error) *error = zipError(@"This zip file is damaged.");
            return NO;
        }
        uint16_t localNameLength = zipRead16(bytes + localOffset + 26);
        uint16_t localExtraLength = zipRead16(bytes + localOffset + 28);
        NSUInteger dataOffset = localOffset + 30 + localNameLength + localExtraLength;
        if (dataOffset + compressedSize > length) {
            if (error) *error = zipError(@"This zip file is damaged.");
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
            if (error) *error = zipError(@"This zip uses a compression method ZXTouch cannot read.");
            return NO;
        }
        if (!contents) {
            if (error) *error = zipError(@"Could not decompress a file in the zip.");
            return NO;
        }
        if (![contents writeToFile:destination options:NSDataWritingAtomic error:error]) {
            return NO;
        }
        extracted = YES;
    }

    if (!extracted) {
        if (error) *error = zipError(@"The zip does not contain any files.");
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
        err = zipError(@"Please choose a .zip file.");
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
        err = [NSError errorWithDomain:@"ZXTouchImport" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Could not read the selected image."}];
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
