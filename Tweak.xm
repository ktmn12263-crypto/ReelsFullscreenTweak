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
+ (instancetype)shared;
@end

@implementation ReelsFullscreenState
+ (instancetype)shared {
    static ReelsFullscreenState *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [ReelsFullscreenState new];
        instance.isFullscreenEnabled = NO;
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

// Applies (or removes) the "hide interaction UI" effect on a given
// Reel cell's content view. Walks the subview tree looking for the
// vertical UFI (like/comment/share) and the controls overlay, and only
// hides them when the shared toggle is on — never unconditionally.
static void RFTApplyStateToView(UIView *root) {
    BOOL hide = [ReelsFullscreenState shared].isFullscreenEnabled;
    for (UIView *subview in root.subviews) {
        NSString *className = NSStringFromClass([subview class]);
        if ([className containsString:@"IGSundialViewerVerticalUFI"] ||
            [className containsString:@"IGSundialViewerControlsOverlayView"]) {
            subview.hidden = hide;
            subview.alpha = hide ? 0.0 : 1.0;
        }
    }
}

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

    [self.view addSubview:toggleButton];

    // Position it top-right, below the status bar / notch area.
    // Adjust the offsets to match Instagram's own safe-area usage.
    CGFloat topInset = self.view.safeAreaInsets.top;
    toggleButton.frame = CGRectMake(self.view.bounds.size.width - 34 - 16,
                                     topInset + 12,
                                     34, 34);
    toggleButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                     UIViewAutoresizingFlexibleBottomMargin;

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
