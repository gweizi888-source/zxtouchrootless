#ifndef TOAST_H
#define TOAST_H

#import <UIKit/UIKit.h>

void showToastFromRawData(UInt8 *eventData, NSError **error);

@interface Toast : NSObject
+ (void) showToastWithContent:(NSString*)content type:(int)type duration:(float)duration position:(int)position fontSize:(int)afontSize x:(int)customX y:(int)customY; // position: 0 top, 1 bottom. customX/customY are pixels; -1 keeps the old placement.
+ (void) hideToast;
- (void) show;
- (void) setContent:(NSString*)content;
- (void) setBackgroundColor:(UIColor*)color;
- (void) setDuration:(int)d;

@end

#endif