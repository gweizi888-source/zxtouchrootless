#include "TextRecognizer.h"
#include <roothide.h>
#import <Vision/Vision.h>
#import "../Screen.h"
#include "../Common.h"
#include "../AlertBox.h"

NSString* performTextRecognizerTextFromRawData(UInt8* eventData, NSError** error)
{
    if (SYSTEM_VERSION_LESS_THAN(@"13.0"))
    {
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;OCR only supports iOS13 or newer version of iOS. iOS12 or older may be supported in the future.\r\n"}];
        showAlertBox(@"不支持", @"文字识别只支持 iOS 13 及以上。", 99);
        return nil;
    }

    NSArray *data = [[NSString stringWithUTF8String:(char *)eventData] componentsSeparatedByString:@";;"];
    if ([data count] == 0)
    {
        NSLog(@"com.zjx.springboard: Data not in good format.");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Data not in good format.\r\n"}];
        return nil;
    }

    int task = [data[0] intValue];

    if (task == TASK_TEXT_FROM_AREA) // format: 1;;x1,y1,x2,y2;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path
    {
        if ([data count] < 8)
        {
            NSLog(@"com.zjx.springboard: Data not in good format. The format should be 1;;x1,,y1,,width,,height;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path.");
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Data not in good format. The format should be 1;;x1,,y1,,width,,height;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path\r\n"}];
            return nil;
        }

        VNRequestTextRecognitionLevel level = VNRequestTextRecognitionLevelAccurate;

        NSString* rectData = data[1]; // rect
        NSString* customWordsData = data[2];
        float minimumHeight = [data[3] floatValue];
        int levelData = [data[4] intValue];
        NSString* languagesData = data[5];
        BOOL correct = [data[6] boolValue];
        NSString* debugPath = data[7];

        // parse rect part
        NSArray *rect = [rectData componentsSeparatedByString:@",,"];
        if ([rect count] < 4)
        {
            NSLog(@"com.zjx.springboard: Rect data not in good format. The format should be x1,,y1,,width,,height");
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Rect data not in good format. The format should be x1,,y1,,width,,height\r\n"}];
            return nil;
        }
    
        CGRect recognizeRect = CGRectMake([rect[0] floatValue], [rect[1] floatValue], [rect[2] floatValue], [rect[3] floatValue]);
        // parse customwords part
        NSArray *customWords = [customWordsData componentsSeparatedByString:@",,"];

        // parse minimum_height part
        if (minimumHeight <= 0)
        {
            minimumHeight = 1/32;
        }

        // parse level
        if (levelData == 1)
        {
            level = VNRequestTextRecognitionLevelFast;
        }
        // parse languages part
        NSArray *languages = [languagesData componentsSeparatedByString:@",,"];

        // Run Vision in a short-lived helper process.  On some iOS 16 devices
        // Vision revision 2 traps while releasing its ANE model; doing OCR in
        // SpringBoard would put the device into safe mode.
        CGImageRef screenshot = [Screen createScreenShotCGImageRef];
        int orientation = [Screen getScreenOrientation];
        if (!screenshot)
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to capture screen for OCR.\r\n"}];
            return nil;
        }

        // SpringBoard and standalone tools see different /var/mobile roots on
        // RootHide.  Use the resolved jailbreak path in both the config and
        // command arguments so the helper can open the same files we write.
        NSString *workDirectory = [jbroot(@"/var/mobile/Library/ZXTouch")
            stringByAppendingPathComponent:@"ocr"];
        [[NSFileManager defaultManager] createDirectoryAtPath:workDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSString *identifier = [[NSUUID UUID] UUIDString];
        NSString *imagePath = [workDirectory stringByAppendingPathComponent:
            [identifier stringByAppendingString:@".jpg"]];
        NSString *configPath = [workDirectory stringByAppendingPathComponent:
            [identifier stringByAppendingString:@".plist"]];
        NSString *outputPath = [workDirectory stringByAppendingPathComponent:
            [identifier stringByAppendingString:@".result.plist"]];

        NSData *imageData = UIImageJPEGRepresentation(
            [UIImage imageWithCGImage:screenshot], 0.95);
        CFRelease(screenshot);
        if (![imageData writeToFile:imagePath atomically:YES])
        {
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Unable to save screen for isolated OCR.\r\n"}];
            return nil;
        }

        NSArray *safeCustomWords = ([customWords count] > 1 || ![customWords[0] isEqualToString:@""])
            ? customWords : @[];
        NSArray *safeLanguages = ([languages count] > 1 || ![languages[0] isEqualToString:@""])
            ? languages : @[];

        // Accurate OCR of a tall region fails with "Error computing NN outputs"
        // on iPhone 13.  Split it into overlapping bands, but recognize all of
        // them in one helper launch from one screenshot.
        NSMutableArray *rects = [NSMutableArray array];
        CGFloat band = 640;
        CGFloat step = 560;
        if (recognizeRect.size.height > band)
        {
            for (CGFloat offset = 0; offset < recognizeRect.size.height; offset += step)
            {
                CGFloat piece = MIN(band, recognizeRect.size.height - offset);
                [rects addObject:@[@(recognizeRect.origin.x), @(recognizeRect.origin.y + offset),
                                   @(recognizeRect.size.width), @(piece)]];
            }
        }
        else
        {
            [rects addObject:@[@(recognizeRect.origin.x), @(recognizeRect.origin.y),
                               @(recognizeRect.size.width), @(recognizeRect.size.height)]];
        }

        NSDictionary *config = @{
            @"imagePath": imagePath,
            @"outputPath": outputPath,
            @"rect": rects[0],
            @"rects": rects,
            @"orientation": @(orientation),
            @"customWords": safeCustomWords,
            @"minimumHeight": @(minimumHeight),
            @"level": @(levelData),
            @"languages": safeLanguages,
            @"correct": @(correct),
            @"debugPath": debugPath ?: @""
        };
        [config writeToFile:configPath atomically:YES];

        NSString *helperPath = jbroot(@"/usr/bin/zxtouchb");
        NSString *command = [NSString stringWithFormat:@"'%@' -ocr '%@'", helperPath, configPath];
        int exitCode = system2([command UTF8String], NULL, NULL);
        NSDictionary *response = [NSDictionary dictionaryWithContentsOfFile:outputPath];

        [[NSFileManager defaultManager] removeItemAtPath:imagePath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:configPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];

        NSString *result = response[@"result"];
        if (result)
        {
            return result;
        }

        NSString *message = response[@"error"];
        if (!message)
        {
            message = [NSString stringWithFormat:@"OCR helper exited with code %d.", exitCode];
        }
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"-1;;%@\r\n", message]}];
        return nil;
    }
    else if (task == TASK_GET_SUPPORTED_LANGUAGE_LIST)
    {
        if ([data count] < 2)
        {
            NSLog(@"com.zjx.springboard: Data not in good format. The format should be 2;;level data:%@", data);
            *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Data not in good format. The format should be 2;;level\r\n"}];
            return nil;
        }
        VNRequestTextRecognitionLevel level = VNRequestTextRecognitionLevelAccurate;

        int levelData = [data[1] intValue];
        if (levelData == 1)
        {
            level = VNRequestTextRecognitionLevelFast;
        }

        NSArray *supportedLanguage;
        if (SYSTEM_VERSION_LESS_THAN(@"14.0"))
        {
            supportedLanguage = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:level revision:1 error:error];
        }
        else
        {
            supportedLanguage = [VNRecognizeTextRequest supportedRecognitionLanguagesForTextRecognitionLevel:level revision:2 error:error];
        }

        return [supportedLanguage componentsJoinedByString:@";;"];
    }
    else 
    {
        NSLog(@"com.zjx.springboard: Text recognition unknown task type");
        *error = [NSError errorWithDomain:@"com.zjx.zxtouchsp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;Text recognition unknown task type\r\n"}];
        return nil;
    }
}