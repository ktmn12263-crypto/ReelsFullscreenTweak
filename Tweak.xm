// ReelsFullscreenToggle
//
// Adds a small button on the Reels screen. Tapping it toggles a
// "fullscreen" mode that hides the interaction UI (like/comment/share/
// caption/etc.) so the video fills the screen. The mode is stored in a
// single shared state object, so it stays on when the user swipes to the
// next Reel — every newly displayed Reel cell re-applies the current state.
//
// The class names below (IGSundialFeedViewController,
// IGSundialViewerVideoCell, IGSundialViewerVerticalUFI,
// IGSundialViewerControlsOverlayView) come from a class-dump YOU
// performed on your own installed copy of Instagram — I have not
// verified them myself, since I never analyzed that binary. Test on
// device; if something doesn't fire or the app crashes, re-check these
// names against your own class-dump output, since they change with
// every Instagram version.
//
// No logging, no NSLog, no on-screen debug text is included — the only
// UI change is the one small toggle button itself.

#import <UIKit/UIKit.h>

// ---------------------------------------------------------------------
// Shared state: one flag, shared across every Reel cell/view controller.
// ---------------------------------------------------------------------
@interface ReelsFullscreenState : NSObject
@property (nonatomic, assign) BOOL isFullscreenEnabled;
// Remembers where the user last dragged the floating button to, in
// UNIT coordinates (0.0–1.0 of the screen width/height), so it can be
// restored at the same relative spot on a new/recycled Reel screen
// instead of resetting to the default position every time.
@property (nonatomic, assign) CGPoint savedButtonUnitPosition;
@property (nonatomic, assign) BOOL hasSavedButtonPosition;
+ (instancetype)shared;
@end

@implementation ReelsFullscreenState
+ (instancetype)shared {
    static ReelsFullscreenState *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [ReelsFullscreenState new];
        instance.isFullscreenEnabled = NO;
        instance.hasSavedButtonPosition = NO;
    });
    return instance;
}
@end

// ---------------------------------------------------------------------
// Small helper to build the toggle button consistently.
// ---------------------------------------------------------------------
static UIButton *RFTMakeToggleButton(void) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(0, 0, 34, 34);
    button.tintColor = [UIColor whiteColor];
    button.layer.cornerRadius = 17;
    button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    UIImage *icon = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"
                     withConfiguration:cfg];
    [button setImage:icon forState:UIControlStateNormal];

    button.accessibilityLabel = @"Toggle fullscreen";
    return button;
}

// Keeps a view's center inside its superview's bounds (with a small
// margin), so the floating button can never be dragged off-screen.
static CGPoint RFTClampCenterToSuperview(CGPoint center, UIView *view) {
    UIView *superview = view.superview;
    if (!superview) return center;
    CGFloat halfW = view.bounds.size.width / 2.0;
    CGFloat halfH = view.bounds.size.height / 2.0;
    CGFloat margin = 4.0;
    CGFloat minX = halfW + margin;
    CGFloat maxX = superview.bounds.size.width - halfW - margin;
    CGFloat minY = halfH + margin + superview.safeAreaInsets.top;
    CGFloat maxY = superview.bounds.size.height - halfH - margin - superview.safeAreaInsets.bottom;
    center.x = MAX(minX, MIN(center.x, maxX));
    center.y = MAX(minY, MIN(center.y, maxY));
    return center;
}

// Applies (or removes) the "hide interaction UI" effect on a given
// Reel cell's content view. Recursively walks the ENTIRE subview tree
// (not just direct children) looking for the vertical UFI (like/
// comment/share) and the controls overlay, and only hides them when
// the shared toggle is on — never unconditionally.
static void RFTApplyStateToView(UIView *root) {
    BOOL hide = [ReelsFullscreenState shared].isFullscreenEnabled;
    for (UIView *subview in root.subviews) {
        NSString *className = NSStringFromClass([subview class]);
        if ([className containsString:@"IGSundialViewerVerticalUFI"] ||
            [className containsString:@"IGSundialViewerControlsOverlayView"] ||
            // Caption / username / bottom text row. NOTE: these two
            // names are GUESSES based on Instagram's usual "Sundial"
            // naming pattern — verify with your own class-dump and
            // swap in the real names if these don't match/hide anything.
            [className containsString:@"IGSundialViewerCaptionView"] ||
            [className containsString:@"IGSundialViewerBottomInfoView"]) {
            subview.hidden = hide;
            subview.alpha = hide ? 0.0 : 1.0;
        }
        // Recurse into every subview, however deeply nested the UFI is.
        RFTApplyStateToView(subview);
    }
}

// ---------------------------------------------------------------------
// Tell the compiler what these private classes actually inherit from,
// so properties like `.view` and `.contentView` resolve correctly.
// (Logos only knows their names exist unless we declare this.)
// Adjust the superclass here if your class-dump shows something
// different (e.g. UITableViewCell instead of UICollectionViewCell).
// ---------------------------------------------------------------------
@interface IGSundialFeedViewController : UIViewController
@end

@interface IGSundialViewerVideoCell : UICollectionViewCell
@end

// ---------------------------------------------------------------------
// Hook the view controller that hosts the Reels feed / single Reel.
// ---------------------------------------------------------------------
%hook IGSundialFeedViewController

- (void)viewDidLoad {
    %orig;

    UIButton *toggleButton = RFTMakeToggleButton();
    toggleButton.tag = 123456; // marker so we don't add it twice

    // Avoid duplicate buttons if this view controller is reused.
    if ([self.view viewWithTag:123456]) {
        return;
    }

    [toggleButton addTarget:self
                      action:@selector(rft_toggleFullscreen:)
            forControlEvents:UIControlEventTouchUpInside];

    // Dragging: a pan gesture moves the button anywhere on screen.
    // (Tap-to-toggle above and drag-to-move here don't conflict —
    // UIButton only fires touchUpInside if the touch didn't turn into
    // a real drag/pan.)
    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                 action:@selector(rft_handleDrag:)];
    [toggleButton addGestureRecognizer:pan];

    [self.view addSubview:toggleButton];

    CGFloat buttonSize = 34;
    toggleButton.bounds = CGRectMake(0, 0, buttonSize, buttonSize);

    ReelsFullscreenState *state = [ReelsFullscreenState shared];
    if (state.hasSavedButtonPosition) {
        // Restore the last place the user dragged it to.
        CGPoint saved = state.savedButtonUnitPosition;
        toggleButton.center = CGPointMake(saved.x * self.view.bounds.size.width,
                                           saved.y * self.view.bounds.size.height);
    } else {
        // Default: right edge, vertically centered on screen.
        CGFloat rightMargin = 16;
        toggleButton.center = CGPointMake(self.view.bounds.size.width - buttonSize / 2.0 - rightMargin,
                                           self.view.bounds.size.height / 2.0);
    }
    toggleButton.center = RFTClampCenterToSuperview(toggleButton.center, toggleButton);
    toggleButton.autoresizingMask = UIViewAutoresizingNone;

    // Re-apply whatever the current global state is (in case the user
    // already enabled fullscreen on a previous Reel).
    RFTApplyStateToView(self.view);
}

// Runs whenever this view controller's Reel becomes the visible one
// (e.g. after the user swipes). Re-applies the current global state so
// "fullscreen" stays on across swipes instead of resetting per-video.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    RFTApplyStateToView(self.view);
}

%new
- (void)rft_toggleFullscreen:(UIButton *)sender {
    ReelsFullscreenState *state = [ReelsFullscreenState shared];
    state.isFullscreenEnabled = !state.isFullscreenEnabled;
    RFTApplyStateToView(self.view);
}

%new
- (void)rft_handleDrag:(UIPanGestureRecognizer *)pan {
    UIView *button = pan.view;
    CGPoint translation = [pan translationInView:self.view];

    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint newCenter = CGPointMake(button.center.x + translation.x,
                                         button.center.y + translation.y);
        button.center = RFTClampCenterToSuperview(newCenter, button);
        [pan setTranslation:CGPointZero inView:self.view];
    } else if (pan.state == UIGestureRecognizerStateEnded ||
               pan.state == UIGestureRecognizerStateCancelled) {
        // Persist the drop position as a fraction of the screen size,
        // so it can be restored correctly even if a future Reel screen
        // has a slightly different size (e.g. rotation).
        ReelsFullscreenState *state = [ReelsFullscreenState shared];
        state.savedButtonUnitPosition = CGPointMake(button.center.x / self.view.bounds.size.width,
                                                      button.center.y / self.view.bounds.size.height);
        state.hasSavedButtonPosition = YES;
    }
}

%end

// ---------------------------------------------------------------------
// Reels video cells are recycled as the user swipes. Hook layout so a
// freshly-dequeued/recycled cell immediately reflects the CURRENT
// shared toggle state — it only hides UFI/overlay when the flag is on,
// never unconditionally, so tapping the button off restores them.
// ---------------------------------------------------------------------
%hook IGSundialViewerVideoCell

- (void)layoutSubviews {
    %orig;
    RFTApplyStateToView(self.contentView);
}

%end

%ctor {
    // Nothing to do at load time — everything is driven by the hooks
    // above. Left intentionally empty (no logging).
}
