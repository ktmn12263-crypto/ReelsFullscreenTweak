#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------
// الحالة المشتركة
// ---------------------------------------------------------------
static BOOL gEnabled = NO;
static const NSInteger kRFTButtonTag = 987654;
static const NSInteger kRFTInspectTag = 987655;
static const NSInteger kRFTHighlightTag = 987656;
static const NSInteger kRFTTextTag = 987657;
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
            @"IGUnifiedVideoCaptionView",
            @"SundialViewerCaption",
            @"SundialCaption",
            @"ViewerCaption",
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

static BOOL RFTHasAncestor(UIView *v, NSString *token, int maxLevels) {
    UIView *p = v.superview;
    for (int i = 0; p && i < maxLevels; i++) {
        if ([NSStringFromClass([p class]) containsString:token]) return YES;
        p = p.superview;
    }
    return NO;
}

static BOOL RFTShouldHide(UIView *v) {
    if (v.tag == kRFTButtonTag) return NO;
    NSString *name = NSStringFromClass([v class]);
    for (NSString *t in RFTHideTokens()) {
        if ([name containsString:t]) return YES;
    }
    // تعتيم الكابشن السفلي فقط (وليس خلفية الفيديو)
    if ([name isEqualToString:@"IGGradientView"] &&
        RFTHasAncestor(v, @"ControlsOverlayContainerView", 3)) return YES;
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

// إبقاء الزر داخل المنطقة الآمنة (تحت الساعة/البطارية وفوق مؤشر الهوم)
static void RFTClamp(UIView *b) {
    UIView *sup = b.superview;
    if (!sup) return;
    UIEdgeInsets ins = sup.window ? sup.window.safeAreaInsets : sup.safeAreaInsets;
    CGFloat hw = b.bounds.size.width / 2;
    CGFloat hh = b.bounds.size.height / 2;
    CGFloat minX = hw + 8;
    CGFloat maxX = sup.bounds.size.width - hw - 8;
    CGFloat minY = MAX(ins.top, 20.0) + hh + 8;
    CGFloat maxY = sup.bounds.size.height - ins.bottom - hh - 8;
    CGPoint c = b.center;
    c.x = MIN(MAX(c.x, minX), maxX);
    c.y = MIN(MAX(c.y, minY), maxY);
    b.center = c;
}

// ---------------------------------------------------------------
// معالج الزر (ضغط + سحب + ضغطة مطوّلة)
// ---------------------------------------------------------------
@interface RFTHandler : NSObject
+ (instancetype)shared;
- (void)toggle:(UIButton *)b;
- (void)pan:(UIPanGestureRecognizer *)g;
- (void)longPress:(UILongPressGestureRecognizer *)g;
- (void)inspectTap:(UITapGestureRecognizer *)g;
- (void)inspectClose:(UIButton *)b;
@end

// ---------------------------------------------------------------
// وضع الفحص: نقرة على أي عنصر تعرض سلسلة الكلاسات (وتنسخها للحافظة)
// ---------------------------------------------------------------
static CALayer *sRFTSmallest = nil;
static CGFloat sRFTSmallestArea = 0;

static BOOL RFTInteresting(NSString *n) {
    for (NSString *k in @[@"Sundial", @"Caption", @"Attribution", @"Label", @"Text"]) {
        if ([n containsString:k]) return YES;
    }
    return NO;
}

// يمر على كل الطبقات ويطبع اللي تحتوي نقطة النقر (شجرة بالمسافات)
static void RFTLayerTree(CALayer *l, CGPoint ptInSuper, int depth, NSMutableString *out, int *lines) {
    if (l.hidden || l.opacity < 0.01f) return;
    BOOL contains = (depth == 0) ? YES : CGRectContainsPoint(l.frame, ptInSuper);
    CGPoint local = ptInSuper;
    if (depth > 0 && l.superlayer) local = [l convertPoint:ptInSuper fromLayer:l.superlayer];
    if (contains && *lines < 300) {
        NSString *cn = NSStringFromClass([l class]);
        id del = l.delegate;
        NSString *label = cn;
        if ([del isKindOfClass:[UIView class]]) {
            label = [NSString stringWithFormat:@"%@ <%@>", cn, NSStringFromClass([del class])];
        }
        [out appendFormat:@"%*s%@%@ %@\n", depth, "", RFTInteresting(label) ? @"* " : @"", label,
            NSStringFromCGSize(l.bounds.size)];
        (*lines)++;
        CGFloat area = l.bounds.size.width * l.bounds.size.height;
        if (area > 100 && (sRFTSmallest == nil || area < sRFTSmallestArea)) {
            sRFTSmallest = l;
            sRFTSmallestArea = area;
        }
    }
    for (CALayer *sub in l.sublayers) RFTLayerTree(sub, local, depth + 1, out, lines);
}

static void RFTToggleInspect(UIWindow *w) {
    if (!w) return;
    UIView *old = [w viewWithTag:kRFTInspectTag];
    if (old) {
        [old removeFromSuperview];
        return;
    }

    UIView *root = [[UIView alloc] initWithFrame:w.bounds];
    root.tag = kRFTInspectTag;
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.backgroundColor = [UIColor clearColor];

    UIView *catcher = [[UIView alloc] initWithFrame:root.bounds];
    catcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    catcher.backgroundColor = [UIColor clearColor];
    [catcher addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:[RFTHandler shared] action:@selector(inspectTap:)]];
    [root addSubview:catcher];

    UIView *hl = [[UIView alloc] initWithFrame:CGRectZero];
    hl.tag = kRFTHighlightTag;
    hl.userInteractionEnabled = NO;
    hl.layer.borderColor = [UIColor redColor].CGColor;
    hl.layer.borderWidth = 2;
    hl.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.12];
    [root addSubview:hl];

    CGFloat top = MAX(w.safeAreaInsets.top, 20.0) + 8;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(8, top, w.bounds.size.width - 16, 240)];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.88];
    panel.layer.cornerRadius = 12;
    panel.clipsToBounds = YES;

    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 34, panel.bounds.size.width, 206)];
    tv.tag = kRFTTextTag;
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.backgroundColor = [UIColor clearColor];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Menlo" size:11];
    tv.text = @"Inspect mode: tap any element.\nResult is copied to clipboard automatically.";
    [panel addSubview:tv];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(panel.bounds.size.width - 44, 0, 44, 34);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close setTitle:@"✕" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [close addTarget:[RFTHandler shared] action:@selector(inspectClose:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    [root addSubview:panel];
    [w addSubview:root];
}

static void RFTStyleButton(UIButton *b) {
    b.backgroundColor = gEnabled ? [UIColor colorWithWhite:0.6 alpha:0.35]
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
}
- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *b = g.view;
    UIView *sup = b.superview;
    if (!sup) return;
    CGPoint t = [g translationInView:sup];
    b.center = CGPointMake(b.center.x + t.x, b.center.y + t.y);
    RFTClamp(b);
    [g setTranslation:CGPointZero inView:sup];
    if (g.state == UIGestureRecognizerStateEnded) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setDouble:b.center.x / sup.bounds.size.width forKey:kPosX];
        [d setDouble:b.center.y / sup.bounds.size.height forKey:kPosY];
    }
}
- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    RFTToggleInspect(g.view.window);
}
- (void)inspectTap:(UITapGestureRecognizer *)g {
    UIView *root = g.view.superview;
    UIWindow *w = root.window;
    if (!w) return;
    CGPoint p = [g locationInView:w];

    root.hidden = YES;
    sRFTSmallest = nil;
    sRFTSmallestArea = 0;
    NSMutableString *tree = [NSMutableString string];
    int lines = 0;
    RFTLayerTree(w.layer, p, 0, tree, &lines);
    root.hidden = NO;

    UIView *hl = [root viewWithTag:kRFTHighlightTag];
    UITextView *tv = (UITextView *)[root viewWithTag:kRFTTextTag];
    NSMutableString *out = [NSMutableString stringWithFormat:@"tap %@  (%d layers at point)\n",
        NSStringFromCGPoint(p), lines];

    if (sRFTSmallest) {
        CGRect r = [sRFTSmallest convertRect:sRFTSmallest.bounds toLayer:w.layer];
        hl.frame = r;
        id del = sRFTSmallest.delegate;
        NSString *vn = [del isKindOfClass:[UIView class]] ? NSStringFromClass([del class]) : @"-";
        [out appendFormat:@"smallest: %@ view=%@ %@\n", NSStringFromClass([sRFTSmallest class]), vn, NSStringFromCGRect(r)];
    } else {
        hl.frame = CGRectZero;
    }
    [out appendString:@"----\n"];
    [out appendString:tree];
    sRFTSmallest = nil;

    tv.text = out;
    [UIPasteboard generalPasteboard].string = out;
}
- (void)inspectClose:(UIButton *)b {
    [[b.window viewWithTag:kRFTInspectTag] removeFromSuperview];
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
    RFTClamp(b);
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
@interface IGUnifiedVideoCaptionView : UIView @end

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
- (void)layoutSubviews {
    %orig;
    if (gEnabled) {
        self.hidden = YES;
        self.alpha = 0;
    }
}
- (void)setHidden:(BOOL)h {
    if (gEnabled) {
        %orig(YES);
    } else {
        %orig(h);
    }
}
- (void)setAlpha:(CGFloat)a {
    if (gEnabled) {
        %orig(0.0);
    } else {
        %orig(a);
    }
}
%end

%hook IGSundialViewerUserAttributionMetalLayerView
- (void)layoutSubviews {
    %orig;
    if (gEnabled) {
        self.hidden = YES;
        self.alpha = 0;
    }
}
- (void)setHidden:(BOOL)h {
    if (gEnabled) {
        %orig(YES);
    } else {
        %orig(h);
    }
}
- (void)setAlpha:(CGFloat)a {
    if (gEnabled) {
        %orig(0.0);
    } else {
        %orig(a);
    }
}
%end

%hook IGSundialViewerTitleGroupView
- (void)layoutSubviews {
    %orig;
    if (gEnabled) {
        self.hidden = YES;
        self.alpha = 0;
    }
}
- (void)setHidden:(BOOL)h {
    if (gEnabled) {
        %orig(YES);
    } else {
        %orig(h);
    }
}
- (void)setAlpha:(CGFloat)a {
    if (gEnabled) {
        %orig(0.0);
    } else {
        %orig(a);
    }
}
%end

%hook IGSundialViewerLabelWithIcon
- (void)layoutSubviews {
    %orig;
    if (gEnabled) {
        self.hidden = YES;
        self.alpha = 0;
    }
}
- (void)setHidden:(BOOL)h {
    if (gEnabled) {
        %orig(YES);
    } else {
        %orig(h);
    }
}
- (void)setAlpha:(CGFloat)a {
    if (gEnabled) {
        %orig(0.0);
    } else {
        %orig(a);
    }
}
%end

%hook IGUnifiedVideoCaptionView
- (void)layoutSubviews {
    %orig;
    if (gEnabled) {
        self.hidden = YES;
        self.alpha = 0;
    }
}
- (void)setHidden:(BOOL)h {
    if (gEnabled) {
        %orig(YES);
    } else {
        %orig(h);
    }
}
- (void)setAlpha:(CGFloat)a {
    if (gEnabled) {
        %orig(0.0);
    } else {
        %orig(a);
    }
}
%end
