#ifndef FLOAT_BUTTON_H
#define FLOAT_BUTTON_H

#import <Foundation/Foundation.h>

@interface FloatButton : NSObject
- (void)setEnabled:(BOOL)enabled;
- (void)setPanelCovering:(BOOL)covering;
- (void)refresh;
@end

void setFloatingButtonEnabled(BOOL enabled);
void setFloatingButtonOpacity(CGFloat opacity);

extern FloatButton *floatButton;

#endif
