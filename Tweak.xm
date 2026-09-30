#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------
// الحالة المشتركة
// ---------------------------------------------------------------
static BOOL gEnabled = NO;
static const NSInteger kRFTButtonTag = 987654;
static NSString *const kPosX = @"RFT_posX";
static NSString *const kPosY = @"RFT_posY";

// أجزاء أسماء الكلاسات اللي نخفيها (مطابقة "يحتوي على")
static NSArray<NSString *> *RFTHideTokens(void) {
    static NSArray *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tokens = @[
            // أزرار التفاعل
            @"IGSundialViewerVerticalUFI",
            @"IGSundialUFIButtonWithCount",
            @"SundialViewerVerticalUFI",
            @"SundialUFIButton",
            // الكابشن + اسم الحساب
            @"IGSundialViewerUserAttribution",
            @"IGSundialViewerCoauthorUser",
            @"SundialViewerUserAttribution",
            // العنوان والأيقونات
            @"IGSundialViewerTitleGroup",
            @"IGSundialViewerTitleButton",
            @"SundialViewerTitleGroup",
            // الموسيقى / الصوت
            @"IGSundialViewerLabelWithIcon",
            @"IGSundialViewerAudioAttribution",
            @"IGSundialViewerAttributionWithIcon",
            // الشريط العلوي وشريط التقدم
            @"IGSundialViewerNavigationBar",
            @"SundialViewerNavigationBar",
            @"IGSundialViewerProgressIndicator"
        ];
    });
    return tokens;
}

static BOOL RFTShouldHide(UIView *v) {
    if (v.tag == kRFTButtonTag) return NO;
    NSString *name = NSStringFromClass([v class]);
    for (NSString *t in RFTHideTokens()) {
        if ([name containsString:t]) return YES;
    }
    return NO;
}

// ---------------------------------------------------------------
// تطبيق الحالة recursively
// ---------------------------------------------------------------
static void RFTApply(UIView *root) {
    if (!root) return;
    for (UIView *sub in root.subviews) {
        if (sub.tag == kRFTButtonTag) continue;
        if (RFTShouldHide(sub)) {
            sub.hidden = gEnabled;
            sub.alpha = gEnabled ? 0.0 : 1.0;
            continue;
        }
        RFTApply(sub);
    }
}

// طباعة شجرة الواجهة (للفحص: ضغطة مطوّلة على الزر تنسخها للحافظة)
static void RFTDump(UIView *v, int depth, NSMutableString *out) {
    [out appendFormat:@"%*s%@ [hidden=%d alpha=%.1f]\n", depth * 2, "",
        NSStringFromClass([v class]), v.hidden, v.alpha];
    for (UIView *s in v.subviews) RFTDump(s, depth + 1, out);
}

// ---------------------------------------------------------------
// معالج الزر (ضغط + سحب + ضغطة مطوّلة)
// ---------------------------------------------------------------
@interface RFTHandler : NSObject
+ (instancetype)shared;
- (void)toggle:(UIButton *)b;
- (void)pan:(UIPanGestureRecognizer *)g;
- (void)longPress:(UILongPressGestureRecognizer *)g;
@end

static void RFTStyleButton(UIButton *b) {
    b.backgroundColor = gEnabled ? [UIColor colorWithRed:0.1 green:0.6 blue:1 alpha:0.85]
                                 : [UIColor colorWithWhite:0 alpha:0.5];
    [b setTitle:(gEnabled ? @"⤡" : @"⤢") forState:UIControlStateNormal];
}

@implementation RFTHandler
+ (instancetype)shared {
    static RFTHandler *h; static dispatch_once_t o;
    dispatch_once(&o, ^{ h = [RFTHandler new]; });
    return h;
}
- (void)toggle:(UIButton *)b {
    gEnabled = !gEnabled;
    RFTStyleButton(b);
    RFTApply(b.superview);
    UIWindow *w = b.window;
    if (w) RFTApply(w);
}
- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *b = g.view;
    UIView *sup = b.superview;
    if (!sup) return;
    CGPoint t = [g translationInView:sup];
    CGPoint c = CGPointMake(b.center.x + t.x, b.center.y + t.y);
    CGFloat hw = b.bounds.size.width / 2, hh = b.bounds.size.height / 2;
    c.x = MIN(MAX(c.x, hw), sup.bounds.size.width - hw);
    c.y = MIN(MAX(c.y, hh), sup.bounds.size.height - hh);
    b.center = c;
    [g setTranslation:CGPointZero inView:sup];
    if (g.state == UIGestureRecognizerStateEnded) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setDouble:c.x / sup.bounds.size.width forKey:kPosX];
        [d setDouble:c.y / sup.bounds.size.height forKey:kPosY];
    }
}
- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSMutableString *out = [NSMutableString string];
    RFTDump(g.view.superview, 0, out);
    [UIPasteboard generalPasteboard].string = out;
}
@end

static void RFTInstallButton(UIView *host) {
    if (!host) return;
    UIButton *b = (UIButton *)[host viewWithTag:kRFTButtonTag];
    if (!b) {
        b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = kRFTButtonTag;
        b.frame = CGRectMake(0, 0, 44, 44);
        b.layer.cornerRadius = 22;
        b.titleLabel.font = [UIFont systemFontOfSize:22];
        [b addTarget:[RFTHandler shared] action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
        [b addGestureRecognizer:[[UIPanGestureRecognizer alloc]
            initWithTarget:[RFTHandler shared] action:@selector(pan:)]];
        [b addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
            initWithTarget:[RFTHandler shared] action:@selector(longPress:)]];
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        CGFloat ux = [d objectForKey:kPosX] ? [d doubleForKey:kPosX] : 0.9;
        CGFloat uy = [d objectForKey:kPosY] ? [d doubleForKey:kPosY] : 0.15;
        b.center = CGPointMake(host.bounds.size.width * ux, host.bounds.size.height * uy);
        [host addSubview:b];
    }
    RFTStyleButton(b);
    [host bringSubviewToFront:b];
}

// ---------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------
@interface IGSundialFeedViewController : UIViewController @end
@interface IGSundialViewerVideoCell : UICollectionViewCell @end
@interface IGSundialViewerControlsOverlayView : UIView @end
@interface IGSundialViewerControlsOverlayController : NSObject
- (void)setControlsAlphaAttributes:(id)attrs;
@end
@interface IGSundialViewerUserAttributionView : UIView @end
@interface IGSundialViewerUserAttributionMetalLayerView : UIView @end
@interface IGSundialViewerTitleGroupView : UIView @end
@interface IGSundialViewerLabelWithIcon : UIView @end

// ---------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------
%hook IGSundialFeedViewController
- (void)viewDidLoad {
    %orig;
    RFTInstallButton(self.view);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    RFTInstallButton(self.view);
    RFTApply(self.view);
}
- (void)viewDidLayoutSubviews {
    %orig;
    RFTInstallButton(self.view);
    RFTApply(self.view);
}
%end

%hook IGSundialViewerVideoCell
- (void)layoutSubviews {
    %orig;
    RFTApply(self);
}
%end

%hook IGSundialViewerControlsOverlayView
- (void)layoutSubviews {
    %orig;
    RFTApply(self);
}
%end

%hook IGSundialViewerControlsOverlayController
- (void)setControlsAlphaAttributes:(id)attrs {
    %orig;
    if (gEnabled && [self respondsToSelector:@selector(view)]) {
        UIView *v = [self performSelector:@selector(view)];
        if ([v isKindOfClass:[UIView class]]) RFTApply(v);
    }
}
%end

// فرض الإخفاء على الكلاسات اللي إنستغرام يعيد إظهارها
%hook IGSundialViewerUserAttributionView
- (void)layoutSubviews { %orig; if (gEnabled) { self.hidden = YES; self.alpha = 0; } }
- (void)setHidden:(BOOL)h { BOOL rftV = gEnabled ? YES : h; %orig(rftV); }
- (void)setAlpha:(CGFloat)a { CGFloat rftV = gEnabled ? 0 : a; %orig(rftV); }
%end

%hook IGSundialViewerUserAttributionMetalLayerView
- (void)layoutSubviews { %orig; if (gEnabled) { self.hidden = YES; self.alpha = 0; } }
- (void)setHidden:(BOOL)h { BOOL rftV = gEnabled ? YES : h; %orig(rftV); }
- (void)setAlpha:(CGFloat)a { CGFloat rftV = gEnabled ? 0 : a; %orig(rftV); }
%end

%hook IGSundialViewerTitleGroupView
- (void)layoutSubviews { %orig; if (gEnabled) { self.hidden = YES; self.alpha = 0; } }
- (void)setHidden:(BOOL)h { BOOL rftV = gEnabled ? YES : h; %orig(rftV); }
- (void)setAlpha:(CGFloat)a { CGFloat rftV = gEnabled ? 0 : a; %orig(rftV); }
%end

%hook IGSundialViewerLabelWithIcon
- (void)layoutSubviews { %orig; if (gEnabled) { self.hidden = YES; self.alpha = 0; } }
- (void)setHidden:(BOOL)h { BOOL rftV = gEnabled ? YES : h; %orig(rftV); }
- (void)setAlpha:(CGFloat)a { CGFloat rftV = gEnabled ? 0 : a; %orig(rftV); }
%end
