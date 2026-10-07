#import "FloatButton.h"
#import "Popup.h"
#import "Common.h"

static const CGFloat kFloatButtonSize = 56;

FloatButton *floatButton = nil;
extern PopupWindow *popupWindow;

@implementation FloatButton
{
    UIWindow *_window;
    BOOL _enabled;
    BOOL _panelCovering;
    BOOL _built;
    BOOL _dragging;
    BOOL _hasRatio;
    CGFloat _ratioX;
    CGFloat _ratioY;
}

- (id)init {
    self = [super init];
    if (self) {
        _enabled = NO;
        _hasRatio = NO;
        [self loadSavedPosition];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self buildWindow];
            _built = YES;
            [self applyVisibility];
        });
    }
    return self;
}

- (void)loadSavedPosition {
    NSDictionary *config = [[NSDictionary alloc] initWithContentsOfFile:getCommonConfigFilePath()];
    id x = config[@"floating_button_x"];
    id y = config[@"floating_button_y"];
    if ([x isKindOfClass:[NSNumber class]] && [y isKindOfClass:[NSNumber class]]) {
        CGFloat rx = [x doubleValue];
        CGFloat ry = [y doubleValue];
        if (rx > 0.02 && rx < 0.98 && ry > 0.02 && ry < 0.98) {
            _ratioX = rx;
            _ratioY = ry;
            _hasRatio = YES;
        }
    }
}

- (CGRect)frameForCurrentScreen {
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat x;
    CGFloat y;
    if (_hasRatio) {
        x = _ratioX * bounds.size.width - kFloatButtonSize / 2.0;
        y = _ratioY * bounds.size.height - kFloatButtonSize / 2.0;
    } else {
        x = bounds.size.width - kFloatButtonSize - 14;
        y = bounds.size.height * 0.42;
    }
    return [self clampedFrame:CGRectMake(x, y, kFloatButtonSize, kFloatButtonSize)];
}

- (CGRect)clampedFrame:(CGRect)frame {
    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat minX = 8;
    CGFloat minY = 48;
    CGFloat maxX = MAX(minX, bounds.size.width - kFloatButtonSize - 8);
    CGFloat maxY = MAX(minY, bounds.size.height - kFloatButtonSize - 36);
    frame.origin.x = MIN(MAX(frame.origin.x, minX), maxX);
    frame.origin.y = MIN(MAX(frame.origin.y, minY), maxY);
    frame.size = CGSizeMake(kFloatButtonSize, kFloatButtonSize);
    return frame;
}

- (void)buildWindow {
    CGRect frame = [self frameForCurrentScreen];
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
    if (scene) {
        _window = [[UIWindow alloc] initWithWindowScene:scene];
        _window.frame = frame;
    } else {
        _window = [[UIWindow alloc] initWithFrame:frame];
    }
    _window.windowLevel = UIWindowLevelAlert + 2;
    _window.backgroundColor = [UIColor clearColor];
    _window.opaque = NO;
    _window.hidden = YES;
    _window.autoresizingMask = UIViewAutoresizingNone;

    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = [UIColor clearColor];
    _window.rootViewController = root;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, kFloatButtonSize, kFloatButtonSize);
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    button.backgroundColor = [UIColor colorWithRed:0.18 green:0.45 blue:0.95 alpha:0.94];
    button.layer.cornerRadius = kFloatButtonSize / 2.0;
    button.layer.masksToBounds = YES;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    [button setTitle:@"脚本" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [button addGestureRecognizer:pan];
    [root.view addSubview:button];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
        object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            if (_window && !_window.hidden) {
                _window.frame = [self frameForCurrentScreen];
            }
        }];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (!_window) return;
    CGPoint translation = [pan translationInView:_window];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _dragging = NO;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        if (fabs(translation.x) + fabs(translation.y) > 3) _dragging = YES;
        CGRect frame = _window.frame;
        frame.origin.x += translation.x;
        frame.origin.y += translation.y;
        _window.frame = [self clampedFrame:frame];
        [pan setTranslation:CGPointZero inView:_window];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [self savePosition];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            _dragging = NO;
        });
    }
}

- (void)savePosition {
    if (!_window) return;
    CGRect bounds = [UIScreen mainScreen].bounds;
    if (bounds.size.width < 1 || bounds.size.height < 1) return;
    CGPoint center = CGPointMake(CGRectGetMidX(_window.frame), CGRectGetMidY(_window.frame));
    _ratioX = center.x / bounds.size.width;
    _ratioY = center.y / bounds.size.height;
    _hasRatio = YES;

    NSString *path = getCommonConfigFilePath();
    NSMutableDictionary *config = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (![config isKindOfClass:[NSMutableDictionary class]]) {
        NSDictionary *existing = [[NSDictionary alloc] initWithContentsOfFile:path];
        config = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    }
    config[@"floating_button_x"] = @(_ratioX);
    config[@"floating_button_y"] = @(_ratioY);
    [config writeToFile:path atomically:YES];
}

- (void)buttonTapped {
    if (_dragging || !popupWindow) return;
    if ([popupWindow isShown]) [popupWindow hide];
    else [popupWindow show];
}

- (void)applyVisibility {
    if (!_built || !_window) return;
    BOOL visible = _enabled && !_panelCovering;
    if (visible) {
        _window.frame = [self frameForCurrentScreen];
        _window.hidden = NO;
    } else {
        _window.hidden = YES;
    }
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    if ([NSThread isMainThread]) [self applyVisibility];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self applyVisibility]; });
}

- (void)setPanelCovering:(BOOL)covering {
    _panelCovering = covering;
    if ([NSThread isMainThread]) [self applyVisibility];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self applyVisibility]; });
}

@end

void setFloatingButtonEnabled(BOOL enabled) {
    if (!floatButton) return;
    [floatButton setEnabled:enabled];
}
