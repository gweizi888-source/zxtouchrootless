#ifndef FLOAT_BUTTON_H
#define FLOAT_BUTTON_H

#import <Foundation/Foundation.h>

@interface FloatButton : NSObject
- (void)setEnabled:(BOOL)enabled;
- (void)setPanelCovering:(BOOL)covering;
@end

void setFloatingButtonEnabled(BOOL enabled);

extern FloatButton *floatButton;

#endif
