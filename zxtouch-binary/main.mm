#import <Foundation/Foundation.h>
#import "../pccontrol/TextRecognization/VKOcrManager.h"
#include <stdio.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>

#include <dlfcn.h>

static int call_system(const char *cmd) {
    static int (*sys_fn)(const char *) = NULL;
    if (!sys_fn) {
        sys_fn = (int (*)(const char *))dlsym(RTLD_DEFAULT, "system");
    }
    return sys_fn ? sys_fn(cmd) : -1;
}

#define SPRINGBOARD_PORT 6000
#define equal(a, b) strcmp(a, b) == 0

int executeCommand();
int playBackFromRawFile();
__attribute__((noreturn)) void performOCR(NSString *configPath);

int getSpringboardSocket() {
    int sock = 0, valread;
     struct sockaddr_in serv_addr;

     if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0)
     {
         NSLog(@"### com.zjx.zxtouchb:  Socket creation error");
         return -1;
     }
    
     serv_addr.sin_family = AF_INET;
     serv_addr.sin_port = htons(SPRINGBOARD_PORT);
        
     // Convert IPv4 and IPv6 addresses from text to binary form
     if(inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr)<=0)
     {
         NSLog(@"### com.zjx.zxtouchb: Invalid address. Address not supported");
         return -1;
     }
    
     if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0)
     {
         NSLog(@"### com.zjx.zxtouchb: \nConnection Failed \n");
         return -1;
     }
    
    return sock;
}


int main(int argc, char *argv[], char *envp[]) {
    @autoreleasepool {
    if (argc < 2)
    {
        NSLog(@"com.zjx.zxtouchb: usage: zxtouchd task [...]");
        printf("com.zjx.zxtouchb: usage: zxtouchd task [...]");
        return 0;
    }
    
    if (equal(argv[1], "-e"))
    {
        executeCommand();
        // notify tweak that the task has been finished
        //int spSocket = getSpringboardSocket();
        //send(spSocket, "90\r\n", strlen("90\r\n"), 0);
        //NSLog(@"com.zjx.zxtouchb: 90 has been sent");
    }
    else if (equal(argv[1], "-pr")) // play back from raw file
    {
        playBackFromRawFile();
    }
    else if (equal(argv[1], "-ocr"))
    {
        if (argc < 3)
        {
            NSLog(@"com.zjx.zxtouchb: please specify the OCR config path.");
            return 2;
        }
        performOCR([NSString stringWithUTF8String:argv[2]]);
    }
    else
    {
        NSLog(@"com.zjx.zxtouchb: usage: zxtouchd [parameter] [...]");
    }

    /*
    else if (strcmp(argv[1], "-r") == 0 || strcmp(argv[1], "--run-script-from-shell-output") == 0) //when user want to run scripts on local machine, then they don't have to create socket themself. They can use this.
    {
        if (argc < 3)
        {
            NSLog(@"com.zjx.zxtouchb: please specify command to run.");
            return 0;
        }
        
        int sbSocket = getSpringboardSocket();
        NSString *commandToSend = [NSString stringWithFormat:@"17%s\n\r", argv[2]];

        char *commandToSendChar = (char*)[commandToSend UTF8String];
        send(sbSocket , commandToSendChar, strlen(commandToSendChar) , 0);
        close(sbSocket);
    }
    else if (strcmp(argv[1], "--content-from-file") == 0)
    {
        if (argc < 3)
        {
            NSLog(@"com.zjx.zxtouchb: please specify file path.");
            return 0;
        }
    
        system([[NSString stringWithFormat:@"cat %s", argv[2]] UTF8String]);
    }
    else
     */

    return 0;
    }
}

__attribute__((noreturn)) void performOCR(NSString *configPath)
{
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
    NSString *outputPath = config[@"outputPath"];
    if (!config || !outputPath)
    {
        _exit(2);
    }

    NSArray *rects = config[@"rects"];
    if (![rects isKindOfClass:[NSArray class]] || rects.count == 0)
    {
        rects = config[@"rect"] ? @[config[@"rect"]] : @[];
    }
    for (NSArray *rectData in rects)
    {
        if (![rectData isKindOfClass:[NSArray class]] || rectData.count != 4)
        {
            [@{@"error": @"Invalid OCR rectangle."} writeToFile:outputPath atomically:YES];
            _exit(2);
        }
    }
    if (rects.count == 0)
    {
        [@{@"error": @"Invalid OCR rectangle."} writeToFile:outputPath atomically:YES];
        _exit(2);
    }

    CIImage *image = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:config[@"imagePath"]]];
    if (!image)
    {
        [@{@"error": @"Unable to open OCR image."} writeToFile:outputPath atomically:YES];
        _exit(2);
    }

    NSArray *customWords = config[@"customWords"];
    NSArray *languages = config[@"languages"];
    NSString *debugPath = config[@"debugPath"];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSError *error = nil;
    BOOL anySuccess = NO;

    for (NSArray *rectData in rects)
    {
        CGRect rect = CGRectMake([rectData[0] doubleValue],
                                 [rectData[1] doubleValue],
                                 [rectData[2] doubleValue],
                                 [rectData[3] doubleValue]);
        VKOcrManager *manager = [[VKOcrManager alloc]
            initWithCIImage:image
            area:rect
            orientation:[config[@"orientation"] intValue]];
        if (customWords.count > 0)
        {
            [manager setCustomWords:customWords];
        }
        [manager setMinimumHeight:[config[@"minimumHeight"] floatValue]];
        [manager setRecognitionLevel:[config[@"level"] intValue] == 1
            ? VNRequestTextRecognitionLevelFast
            : VNRequestTextRecognitionLevelAccurate];
        if (languages.count > 0)
        {
            [manager setLanguages:languages];
        }
        [manager setCorrection:[config[@"correct"] boolValue]];

        NSError *bandError = nil;
        NSString *bandResult = [manager recognize:&bandError];
        if (!bandResult)
        {
            error = bandError;
            continue;
        }
        anySuccess = YES;
        if (rects.count == 1 && debugPath.length > 0)
        {
            [manager outputDebugImage:debugPath error:&bandError];
        }
        if (bandResult.length == 0)
        {
            continue;
        }

        // Bands overlap, so the same line can come back twice.
        for (NSString *line in [bandResult componentsSeparatedByString:@";;"])
        {
            NSArray *parts = [line componentsSeparatedByString:@",,"];
            NSString *key = line;
            if (parts.count >= 5)
            {
                key = [NSString stringWithFormat:@"%@|%d|%d", parts[0],
                    [parts[1] intValue] / 12, [parts[2] intValue] / 12];
            }
            if ([seen containsObject:key])
            {
                continue;
            }
            [seen addObject:key];
            [lines addObject:line];
        }
    }

    NSString *result = anySuccess ? [lines componentsJoinedByString:@";;"] : nil;

    NSDictionary *response = result
        ? @{@"result": result}
        : @{@"error": error.localizedDescription ?: @"OCR failed."};
    [response writeToFile:outputPath atomically:YES];

    // Vision revision 2 can trap while destroying its ANE model on iOS 16.
    // This helper handles one request per process.  Exit without draining ARC
    // objects after the result is durable so that a Vision cleanup bug can
    // never crash SpringBoard.
    _exit(result ? 0 : 3);
}

int executeCommand()
{
    NSArray *parameterArr = [[NSProcessInfo processInfo] arguments];

    if ([parameterArr count] < 3)
    {
        NSLog(@"com.zjx.zxtouchb: please specify the command to be executed.");
        return 0;
    }
    NSLog(@"com.zjx.zxtouchb: command to run: %@", [NSString stringWithFormat:@"%@", parameterArr[2]] );
    
    return call_system([[NSString stringWithFormat:@"%@", parameterArr[2]] UTF8String]);
}


int playBackFromRawFile()
{
    NSArray *parameterArr = [[NSProcessInfo processInfo] arguments];

    if ([parameterArr count] < 3)
    {
        NSLog(@"com.zjx.zxtouchb: please specify the raw file path.");
        return 0;
    }
    
    int sbSocket = getSpringboardSocket();
    
    FILE *file = fopen([parameterArr[2] UTF8String], "r");
    
    char buffer[256];
    int taskType;
    int sleepTime;
    
    while (fgets(buffer, sizeof(char)*256, file) != NULL){
        //NSLog(@"sleep: %s",buffer);

        sscanf(buffer, "%2d%d", &taskType, &sleepTime);
        if (taskType == 18)
        {
            //[NSThread sleepForTimeInterval:sleepTime/1000000];
            usleep(sleepTime/2);
        }
        else
        {
            send(sbSocket , buffer, strlen(buffer) , 0);
        }
    }
}

