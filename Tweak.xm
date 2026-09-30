#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------
// الحالة المشتركة
// ---------------------------------------------------------------
static BOOL gEnabled = NO;
static const NSInteger kRFTButtonTag = 987654;
static NSString *const kPosX = @"RFT_posX";
static NSString *const kPosY = @"RFT_posY";

// الكلاسات (أو أجزاء من أسمائها) اللي نخفيها.
// المطابقة بـ "يحتوي على" عشان تتحمل اختلاف الأسماء بين التحديثات.
static NSArray<NSString *> *RFTHideTokens(void) {
    static NSArray *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tokens = @[
            @"IGSundialViewerVerticalUFI",
            @"IGSundialUFIButtonWithCount",
            @"IGSundialViewerUserAttributionView",
            @"IGSundialViewerNavigationBar",
            @"IGSundialViewerTitleGroupView",
            @"IGSundialViewerProgressIndicator",
            @"SundialViewerVerticalUFI",
            @"SundialUFIButton",
            @"SundialViewerUserAttribution",
            @"SundialViewerNavigationBar",
            @"SundialViewerTitleGroup"
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
            // لا ننزل داخله، الأب مخفي بكل أبنائه
            continue;
        }
        RFTApply(sub);
    }
}

// ---------------------------------------------------------------
// معالج الزر (ضغط + سحب)
// ---------------------------------------------------------------
@interface RFTHandler : NSObject
+ (instancetype)shared;
- (void)toggle:(UIButton *)b;
- (void)pan:(UIPanGestureRecognizer *)g;
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
    UIView *root = b.superview;
    RFTApply(root);
    // نطبق على كل الخلايا الظاهرة أيضًا
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
        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:[RFTHandler shared] action:@selector(pan:)];
        [b addGestureRecognizer:p];
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

// كل ريل جديد يرث الحالة
%hook IGSundialViewerVideoCell
- (void)layoutSubviews {
    %orig;
    RFTApply(self);
}
%end

// الطبقة اللي فوق الفيديو: نعيد الإخفاء كلما إنستغرام حاول يظهرها
%hook IGSundialViewerControlsOverlayView
- (void)layoutSubviews {
    %orig;
    RFTApply(self);
}
%end

// المتحكم الرئيسي: بعد ما ينهي تغيير الـ alpha نعيد تطبيق حالتنا
%hook IGSundialViewerControlsOverlayController
- (void)setControlsAlphaAttributes:(id)attrs {
    %orig;
    if (gEnabled && [self respondsToSelector:@selector(view)]) {
        UIView *v = [self performSelector:@selector(view)];
        if ([v isKindOfClass:[UIView class]]) RFTApply(v);
    }
}
%end
