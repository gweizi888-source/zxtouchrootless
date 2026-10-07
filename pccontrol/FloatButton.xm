#import "FloatButton.h"
#import "Popup.h"
#import "Common.h"
#import <objc/message.h>

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
    CGFloat _opacity;
    UIImageView *_iconView;
}

- (id)init {
    self = [super init];
    if (self) {
        _enabled = NO;
        _hasRatio = NO;
        _opacity = 0.55;
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
    id alpha = config[@"floating_button_alpha"];
    if ([alpha isKindOfClass:[NSNumber class]]) {
        CGFloat value = [alpha doubleValue];
        if (value >= 0.15 && value <= 1.0) _opacity = value;
    }
}

- (UIImage *)floatingIcon {
    SEL iconSelector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([UIImage respondsToSelector:iconSelector]) {
        UIImage *(*iconImage)(id, SEL, NSString *, NSInteger, CGFloat) = (UIImage *(*)(id, SEL, NSString *, NSInteger, CGFloat))objc_msgSend;
        NSArray *bundleIds = @[@"com.zjx.zxtouch", @"com.zjx.ioscontrol"];
        for (NSString *bundleId in bundleIds) {
            UIImage *icon = iconImage([UIImage class], iconSelector, bundleId, 2, [UIScreen mainScreen].scale);
            if (icon) return icon;
        }
    }
    return [UIImage imageWithContentsOfFile:@"/var/mobile/Library/ZXTouch/float-icon.png"];
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

- (UIWindowScene *)hostScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                return (UIWindowScene *)scene;
            }
        }
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.windowScene) return window.windowScene;
        }
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (void)attachSceneIfNeeded {
    if (!_window) return;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self hostScene];
        if (scene && _window.windowScene != scene) {
            _window.windowScene = scene;
        }
    }
}

- (void)buildWindow {
    CGRect frame = [self frameForCurrentScreen];
    // iOS 15 SpringBoard often ignores a window created with initWithWindowScene
    // before the home screen scene is active. Create with a frame, then attach.
    _window = [[UIWindow alloc] initWithFrame:frame];
    _window.windowLevel = UIWindowLevelStatusBar + 100;
    _window.backgroundColor = [UIColor clearColor];
    _window.opaque = NO;
    _window.hidden = YES;
    _window.clipsToBounds = YES;
    _window.autoresizingMask = UIViewAutoresizingNone;
    [self attachSceneIfNeeded];

    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = [UIColor clearColor];
    root.view.frame = CGRectMake(0, 0, kFloatButtonSize, kFloatButtonSize);
    _window.rootViewController = root;
    _window.frame = frame;
    root.view.frame = _window.bounds;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = root.view.bounds;
    button.autoresizingMask = UIViewAutoresizingNone;
    button.backgroundColor = [UIColor clearColor];
    [button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];

    _iconView = [[UIImageView alloc] initWithFrame:button.bounds];
    _iconView.image = [self floatingIcon];
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.layer.cornerRadius = kFloatButtonSize / 2.0;
    _iconView.layer.masksToBounds = YES;
    _iconView.alpha = _opacity;
    _iconView.userInteractionEnabled = NO;
    [button addSubview:_iconView];

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
    if (!_window) return;
    [self attachSceneIfNeeded];
    BOOL visible = _enabled && !_panelCovering;
    if (visible) {
        CGRect frame = [self frameForCurrentScreen];
        _window.frame = frame;
        _window.rootViewController.view.frame = CGRectMake(0, 0, frame.size.width, frame.size.height);
        for (UIView *subview in _window.rootViewController.view.subviews) {
            subview.frame = _window.rootViewController.view.bounds;
            subview.layer.cornerRadius = frame.size.width / 2.0;
        }
        if (_iconView) {
            _iconView.frame = _iconView.superview.bounds;
            _iconView.layer.cornerRadius = frame.size.width / 2.0;
            _iconView.alpha = _opacity;
        }
        _window.hidden = NO;
    } else {
        _window.hidden = YES;
    }
}

- (void)refresh {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
        return;
    }
    if (!_built) return;
    if (!_window) [self buildWindow];
    [self applyVisibility];
}

- (void)setOpacity:(CGFloat)opacity {
    if (opacity < 0.15) opacity = 0.15;
    if (opacity > 1.0) opacity = 1.0;
    _opacity = opacity;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setOpacity:opacity]; });
        return;
    }
    _iconView.alpha = _opacity;
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

void setFloatingButtonOpacity(CGFloat opacity) {
    if (!floatButton) return;
    [floatButton setOpacity:opacity];
}
