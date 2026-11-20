// Lantern Lane: a full-screen WKWebView above Godot's view, for the Three.js city
// (design/city-threejs.md, "Bridge protocol"). Nothing is loaded from the network:
// the page comes from a folder of the app through the custom scheme lantern://city/.
//
// Threads. UIKit and WebKit are used on the main thread only. The Godot methods
// may be called from any thread and never wait for the main thread or the page:
// what must run on the main thread is queued there. The state the two sides share
// is atomic, and the page's messages wait in a queue behind a lock.
#import <TargetConditionals.h>
#if TARGET_OS_TV
#error "tvOS has no WebKit: the WebView plugin is for iOS and iPadOS only"
#endif

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <os/lock.h>

#include <atomic>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include "web_view.h"
#include "core/config/engine.h"

static NSString *const kLLScheme = @"lantern";
static NSString *const kLLHost = @"city";
static NSString *const kLLPageURL = @"lantern://city/index.html";
static NSString *const kLLHandlerName = @"godot";
// post(): calls to the page that have not answered yet. A whole burst of one Godot
// frame (hello, states, children's models, frame) is in flight together, because the
// answers arrive on the main thread, between Godot's frames.
static const int kLLMaxInFlight = 64;
// poll(): unread messages of the page. The oldest is dropped when it is full.
static const NSUInteger kLLMaxQueued = 512;
static const NSUInteger kLLMaxMessageLength = 1024 * 1024;
// The page is loaded again when the web process ended (iOS ends it when memory is
// short, also while the app is in the background), but not in a loop: at most this
// many times within kLLReloadWindow seconds.
static const NSUInteger kLLMaxAutoReloads = 3;
static const NSTimeInterval kLLReloadWindow = 60.0;

static LanternWebView *web_view_instance = nullptr;

static std::atomic<bool> ll_open(false);
static std::atomic<bool> ll_loaded(false);
static std::atomic<int> ll_in_flight(0);
static std::atomic<uint32_t> ll_generation(0);
static std::atomic<int64_t> ll_dropped(0); // Godot to page
static std::atomic<int64_t> ll_poll_dropped(0); // page to Godot
static std::atomic<int64_t> ll_js_errors(0);
static std::atomic<int64_t> ll_terminated(0);

static os_unfair_lock ll_queue_lock = OS_UNFAIR_LOCK_INIT;
static NSMutableArray<NSString *> *ll_queue = nil;

// ---------------------------------------------------------------- shared helpers

static void ll_enqueue(NSString *text) {
	if (text == nil) {
		return;
	}
	os_unfair_lock_lock(&ll_queue_lock);
	if (ll_queue == nil) {
		ll_queue = [NSMutableArray array];
	}
	if (ll_queue.count >= kLLMaxQueued) {
		[ll_queue removeObjectAtIndex:0];
		ll_poll_dropped++;
	}
	[ll_queue addObject:text];
	os_unfair_lock_unlock(&ll_queue_lock);
}

static NSArray<NSString *> *ll_drain() {
	os_unfair_lock_lock(&ll_queue_lock);
	NSArray<NSString *> *out = ll_queue;
	ll_queue = nil;
	os_unfair_lock_unlock(&ll_queue_lock);
	return out;
}

// A message of the plugin itself, in the protocol's "log" form, so that Godot reads
// it with the page's messages.
static void ll_native_log(NSString *level, NSString *text) {
	NSLog(@"WebView: %@", text);
	NSDictionary *message = @{ @"t" : @"log", @"level" : level, @"text" : [@"native: " stringByAppendingString:text] };
	NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
	if (data != nil) {
		ll_enqueue([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
	}
}

// Gives back one in-flight slot; never below zero.
static void ll_release_slot() {
	int value = ll_in_flight.load();
	while (value > 0 && !ll_in_flight.compare_exchange_weak(value, value - 1)) {
	}
}

// A new page (or none): calls still in flight belong to the old one and are forgotten.
static void ll_reset_transport() {
	ll_loaded.store(false);
	ll_generation++;
	ll_in_flight.store(0);
}

static NSString *ll_ns(const String &p_text) {
	return [[NSString alloc] initWithUTF8String:p_text.utf8().get_data()];
}

static String ll_gd(NSString *p_text) {
	NSData *data = [p_text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
	if (data == nil || data.length == 0) {
		return String();
	}
	return String::utf8((const char *)data.bytes, (int)data.length);
}

// ---------------------------------------------------------------- files of the page

// The real path (links resolved, "." and ".." removed) of an existing file or folder.
static NSString *ll_realpath(NSString *path) {
	if (path.length == 0) {
		return nil;
	}
	const char *text = [path UTF8String];
	char resolved[PATH_MAX];
	if (text == NULL || realpath(text, resolved) == NULL) {
		return nil;
	}
	return [NSString stringWithUTF8String:resolved];
}

static NSCharacterSet *ll_refused_characters() {
	static NSCharacterSet *set = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableCharacterSet *chars = [[NSCharacterSet controlCharacterSet] mutableCopy];
		[chars addCharactersInString:@"\\"];
		set = [chars copy];
	});
	return set;
}

// lantern://city/<path> gives "<path>" (the path below the root, percent-decoded), or
// nil when the URL is refused: another scheme or host, a "." or ".." part, a control
// character or a backslash.
static NSString *ll_relative_path(NSURL *url) {
	if (url == nil || ![url.scheme.lowercaseString isEqualToString:kLLScheme] || ![url.host.lowercaseString isEqualToString:kLLHost]) {
		return nil;
	}
	NSString *path = url.path;
	if (path == nil) {
		return nil;
	}
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	for (NSString *part in [path componentsSeparatedByString:@"/"]) {
		if (part.length == 0) {
			continue;
		}
		if ([part isEqualToString:@"."] || [part isEqualToString:@".."]) {
			return nil;
		}
		if ([part rangeOfCharacterFromSet:ll_refused_characters()].location != NSNotFound) {
			return nil;
		}
		[parts addObject:part];
	}
	if (parts.count == 0) {
		return @"index.html";
	}
	return [parts componentsJoinedByString:@"/"];
}

// The file a URL names, or nil with the HTTP status: 403 when the URL is refused or
// the file's real path is outside the root (a link that leaves it), 404 when there is
// no such file. `root` is a real path (ll_realpath).
static NSString *ll_resolve_file(NSString *root, NSURL *url, NSInteger *status) {
	NSString *relative = ll_relative_path(url);
	if (relative == nil || root.length == 0) {
		*status = 403;
		return nil;
	}
	NSString *real = ll_realpath([root stringByAppendingPathComponent:relative]);
	if (real == nil) {
		*status = 404;
		return nil;
	}
	NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
	if (![real hasPrefix:prefix]) {
		*status = 403;
		return nil;
	}
	BOOL directory = NO;
	if (![[NSFileManager defaultManager] fileExistsAtPath:real isDirectory:&directory] || directory) {
		*status = 404;
		return nil;
	}
	*status = 200;
	return real;
}

// WebKit runs a module script only when it has a JavaScript MIME type.
static NSString *ll_content_type(NSString *path) {
	static NSDictionary<NSString *, NSString *> *types = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		types = @{
			@"html" : @"text/html; charset=utf-8",
			@"js" : @"text/javascript; charset=utf-8",
			@"mjs" : @"text/javascript; charset=utf-8",
			@"json" : @"application/json",
			@"bin" : @"application/octet-stream",
			@"png" : @"image/png",
			@"css" : @"text/css; charset=utf-8",
			@"txt" : @"text/plain; charset=utf-8",
			@"svg" : @"image/svg+xml",
			@"jpg" : @"image/jpeg",
			@"jpeg" : @"image/jpeg",
			@"webp" : @"image/webp",
			@"wasm" : @"application/wasm",
		};
	});
	NSString *type = types[path.pathExtension.lowercaseString];
	return type != nil ? type : @"application/octet-stream";
}

// Serves lantern://city/<path> from <root>/<path>. It does not refer to the web view,
// so the configuration that keeps it makes no retain cycle.
@interface LLCitySchemeHandler : NSObject <WKURLSchemeHandler>
@property(atomic, copy) NSString *root;
- (void)cancelAll;
@end

@implementation LLCitySchemeHandler {
	// The tasks WebKit still waits for. Main thread only (WebKit starts and stops tasks
	// there). A task that is not in it is never answered: answering a stopped task
	// raises an exception.
	NSHashTable<id<WKURLSchemeTask>> *_live;
	dispatch_queue_t _io;
}

- (instancetype)init {
	self = [super init];
	if (self != nil) {
		_live = [[NSHashTable alloc] initWithOptions:(NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality) capacity:16];
		_io = dispatch_queue_create("lanternlane.webview.files", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT, QOS_CLASS_USER_INITIATED, 0));
	}
	return self;
}

- (void)cancelAll {
	[_live removeAllObjects];
}

- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
	[_live addObject:urlSchemeTask];
	NSString *root = self.root;
	NSURL *url = urlSchemeTask.request.URL;
	BOOL head = [urlSchemeTask.request.HTTPMethod.uppercaseString isEqualToString:@"HEAD"];
	// Every file is read, whole, off the main thread (the city's mesh pack is several
	// MB). Not mapped: a mapped file would be paged in on the main thread, when WebKit
	// copies it.
	dispatch_async(_io, ^{
		NSInteger status = 403;
		NSString *file = ll_resolve_file(root, url, &status);
		NSData *body = nil;
		if (file != nil) {
			body = [NSData dataWithContentsOfFile:file options:0 error:nil];
			if (body == nil) {
				status = 404;
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			[self answer:urlSchemeTask url:url status:status file:file body:body head:head];
		});
	});
}

- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)urlSchemeTask {
	[_live removeObject:urlSchemeTask];
}

// Main thread.
- (void)answer:(id<WKURLSchemeTask>)task url:(NSURL *)url status:(NSInteger)status file:(NSString *)file body:(NSData *)body head:(BOOL)head {
	if (![_live containsObject:task]) {
		return; // stopped while the file was read
	}
	[_live removeObject:task];
	BOOL found = status == 200 && body != nil;
	NSData *payload = found ? body : [[NSString stringWithFormat:@"%ld", (long)status] dataUsingEncoding:NSUTF8StringEncoding];
	NSDictionary<NSString *, NSString *> *headers = @{
		@"Content-Type" : found ? ll_content_type(file) : @"text/plain; charset=utf-8",
		@"Content-Length" : [NSString stringWithFormat:@"%lu", (unsigned long)payload.length],
		@"Cache-Control" : @"no-store",
		@"Access-Control-Allow-Origin" : @"*",
	};
	@try {
		NSHTTPURLResponse *response = url == nil ? nil : [[NSHTTPURLResponse alloc] initWithURL:url statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:headers];
		if (response == nil) {
			[task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil]];
			return;
		}
		[task didReceiveResponse:response];
		if (!head && payload.length > 0) {
			[task didReceiveData:payload];
		}
		[task didFinish];
	} @catch (NSException *exception) {
		NSLog(@"WebView: a request ended early: %@", exception.reason);
	}
}

@end

// ---------------------------------------------------------------- the page's messages

// WKUserContentController keeps its message handlers. This one only points at its
// target, so the controller does not keep the host alive.
@interface LLWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) id<WKScriptMessageHandler> target;
- (instancetype)initWithTarget:(id<WKScriptMessageHandler>)target;
@end

@implementation LLWeakScriptMessageHandler

- (instancetype)initWithTarget:(id<WKScriptMessageHandler>)target {
	self = [super init];
	if (self != nil) {
		_target = target;
	}
	return self;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
	[self.target userContentController:userContentController didReceiveScriptMessage:message];
}

@end

// ---------------------------------------------------------------- the web view

// Godot's own view controller, the way the engine's iOS code reaches it
// (GDTAppDelegateService.viewController; AppDelegate.viewController before 4.5),
// asked through the runtime so that no engine header of that code is needed.
static UIViewController *ll_godot_view_controller() {
	for (NSString *name in @[ @"GDTAppDelegateService", @"AppDelegate" ]) {
		Class cls = NSClassFromString(name);
		if (cls != Nil && [cls respondsToSelector:@selector(viewController)]) {
			id controller = [cls performSelector:@selector(viewController)];
			if ([controller isKindOfClass:[UIViewController class]]) {
				return controller;
			}
		}
	}
	return nil;
}

// The window that shows Godot's view; else the key window; else any window.
static UIWindow *ll_window() {
	UIWindow *window = ll_godot_view_controller().viewIfLoaded.window;
	if (window != nil) {
		return window;
	}
	UIWindow *fallback = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
			if (candidate.isKeyWindow) {
				return candidate;
			}
			if (fallback == nil && !candidate.hidden) {
				fallback = candidate;
			}
		}
	}
	if (fallback != nil) {
		return fallback;
	}
	id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
	if ([delegate respondsToSelector:@selector(window)]) {
		return delegate.window;
	}
	return nil;
}

// Owns the web view. Main thread only.
@interface LLWebViewHost : NSObject <WKNavigationDelegate, WKScriptMessageHandler>
+ (LLWebViewHost *)shared;
- (BOOL)openRoot:(NSString *)root url:(NSURL *)url;
- (void)close;
- (void)evaluate:(NSString *)script generation:(uint32_t)generation;
@end

@implementation LLWebViewHost {
	WKWebView *_webView;
	WKUserContentController *_content;
	LLCitySchemeHandler *_files;
	LLWeakScriptMessageHandler *_proxy;
	NSURL *_pageURL;
	NSMutableArray<NSNumber *> *_reloadTimes; // system uptime of the latest automatic reloads
	// A load was asked for and has not committed: what the view shows and what speaks
	// is still the document before it.
	BOOL _awaitingCommit;
}

- (void)loadPage {
	_awaitingCommit = YES;
	[_webView loadRequest:[NSURLRequest requestWithURL:_pageURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30.0]];
}

+ (LLWebViewHost *)shared {
	static LLWebViewHost *host = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		host = [[LLWebViewHost alloc] init];
	});
	return host;
}

- (void)buildWithFrame:(CGRect)frame {
	_files = [[LLCitySchemeHandler alloc] init];
	_proxy = [[LLWeakScriptMessageHandler alloc] initWithTarget:self];
	_content = [[WKUserContentController alloc] init];
	[_content addScriptMessageHandler:_proxy name:kLLHandlerName];

	WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
	configuration.userContentController = _content;
	// Nothing of the page is kept on disk (no cookies, caches or storage).
	configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
	[configuration setURLSchemeHandler:_files forURLScheme:kLLScheme];
	configuration.allowsInlineMediaPlayback = YES;
	configuration.allowsAirPlayForMediaPlayback = NO;
	configuration.allowsPictureInPictureMediaPlayback = NO;
	configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
	// The same page on iPhone and iPad: no desktop-class browsing mode on iPad.
	configuration.defaultWebpagePreferences.preferredContentMode = WKContentModeMobile;

	WKWebView *view = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
	view.navigationDelegate = self; // weak in WKWebView
	view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	view.opaque = YES;
	view.backgroundColor = UIColor.whiteColor;
	view.underPageBackgroundColor = UIColor.whiteColor;
	view.allowsBackForwardNavigationGestures = NO;
	view.allowsLinkPreview = NO;
	UIScrollView *scroll = view.scrollView;
	scroll.backgroundColor = UIColor.whiteColor;
	scroll.scrollEnabled = NO;
	scroll.bounces = NO;
	scroll.alwaysBounceVertical = NO;
	scroll.alwaysBounceHorizontal = NO;
	scroll.bouncesZoom = NO;
	scroll.minimumZoomScale = 1.0;
	scroll.maximumZoomScale = 1.0;
	scroll.pinchGestureRecognizer.enabled = NO;
	scroll.showsVerticalScrollIndicator = NO;
	scroll.showsHorizontalScrollIndicator = NO;
	scroll.scrollsToTop = NO;
	scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
#ifdef DEBUG_ENABLED
	// Safari's Web Inspector may attach in debug builds only.
	if (@available(iOS 16.4, *)) {
		view.inspectable = YES;
	}
#endif
	_webView = view;
}

- (BOOL)openRoot:(NSString *)root url:(NSURL *)url {
	UIWindow *window = ll_window();
	if (window == nil) {
		ll_open.store(false);
		ll_native_log(@"error", @"no window to show the page in");
		return NO;
	}
	ll_reset_transport();
	(void)ll_drain();
	_reloadTimes = [NSMutableArray array];
	_pageURL = url;
	if (_webView == nil) {
		[self buildWithFrame:window.bounds];
	}
	_files.root = root;
	WKWebView *view = _webView;
	// A child of the window itself: above Godot's view, resized with the window
	// (rotation, split view), and Godot's view is not in its responder chain, so no
	// touch of the page reaches the game.
	if (view.superview != window) {
		[view removeFromSuperview];
		[window addSubview:view];
	}
	view.frame = window.bounds;
	view.hidden = NO;
	[window bringSubviewToFront:view];
	[self loadPage];
	return YES;
}

- (void)close {
	ll_reset_transport();
	(void)ll_drain();
	WKWebView *view = _webView;
	if (view == nil) {
		return;
	}
	view.navigationDelegate = nil;
	[view stopLoading];
	// The content controller keeps its handlers until they are removed. Ours is only
	// the weak proxy, so nothing keeps this host or the web view alive after this.
	[_content removeScriptMessageHandlerForName:kLLHandlerName];
	[_content removeAllUserScripts];
	[_files cancelAll];
	[view endEditing:YES];
	view.hidden = YES;
	[view removeFromSuperview];
	_webView = nil;
	_content = nil;
	_files = nil;
	_proxy = nil;
	_pageURL = nil;
	_awaitingCommit = NO;
}

- (void)evaluate:(NSString *)script generation:(uint32_t)generation {
	WKWebView *view = _webView;
	if (view == nil || generation != ll_generation.load() || !ll_loaded.load()) {
		ll_release_slot();
		ll_dropped++;
		return;
	}
	void (^done)(id, NSError *) = ^(id result, NSError *error) {
		if (generation != ll_generation.load()) {
			return; // the page of this call is gone, and so is its slot
		}
		ll_release_slot();
		// Not the page's errors: a result that cannot be passed back, and a page that went away.
		BOOL ignored = [error.domain isEqualToString:WKErrorDomain] && (error.code == WKErrorJavaScriptResultTypeIsUnsupported || error.code == WKErrorWebContentProcessTerminated || error.code == WKErrorWebViewInvalidated);
		if (error != nil && !ignored) {
			ll_js_errors++;
		}
	};
	[view evaluateJavaScript:script completionHandler:done];
}

// WKScriptMessageHandler (through the weak proxy), main thread.
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
	if (_webView == nil || _awaitingCommit || message.webView != _webView || ![message.name isEqualToString:kLLHandlerName]) {
		return; // also what a document that is being replaced still says
	}
	if (message.frameInfo != nil && !message.frameInfo.isMainFrame) {
		return;
	}
	id body = message.body;
	NSString *text = nil;
	if ([body isKindOfClass:[NSString class]]) {
		text = body;
	} else if ([NSJSONSerialization isValidJSONObject:body]) {
		NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
		if (data != nil) {
			text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		}
	}
	if (text == nil || text.length > kLLMaxMessageLength) {
		ll_poll_dropped++;
		return;
	}
	// A page that speaks runs its scripts: it can be called from now on, even when
	// its load event is still to come.
	ll_loaded.store(true);
	ll_enqueue(text);
}

// WKNavigationDelegate, main thread.
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
	// Only the bundled page: no link ever leaves the app or loads from the network.
	NSURL *url = navigationAction.request.URL;
	BOOL ours = [url.scheme.lowercaseString isEqualToString:kLLScheme] && [url.host.lowercaseString isEqualToString:kLLHost];
	BOOL blank = [url.scheme.lowercaseString isEqualToString:@"about"];
	decisionHandler((ours || blank) ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
	if (webView != _webView) {
		return;
	}
	// A new document (also when the page reloads itself): the calls to the one before
	// it, and its "loaded", are gone.
	ll_reset_transport();
	_awaitingCommit = NO;
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	if (webView == _webView && !_awaitingCommit) {
		ll_loaded.store(true);
	}
}

- (void)reportFailure:(NSError *)error {
	if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
		return; // replaced by a newer load
	}
	ll_native_log(@"error", [NSString stringWithFormat:@"the page did not load: %@ (%@ %ld)", error.localizedDescription, error.domain, (long)error.code]);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	if (webView == _webView) {
		[self reportFailure:error];
	}
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	if (webView == _webView) {
		[self reportFailure:error];
	}
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
	if (webView != _webView) {
		return;
	}
	ll_terminated++;
	ll_reset_transport();
	[_files cancelAll];
	NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
	while (_reloadTimes.count > 0 && now - _reloadTimes.firstObject.doubleValue > kLLReloadWindow) {
		[_reloadTimes removeObjectAtIndex:0];
	}
	if (_reloadTimes.count >= kLLMaxAutoReloads || _pageURL == nil) {
		ll_native_log(@"error", @"the web process keeps ending; the page is not loaded again");
		return;
	}
	[_reloadTimes addObject:@(now)];
	ll_native_log(@"warn", @"the web process ended; loading the page again");
	[self loadPage];
}

@end

// lantern://city/index.html?<query>. The query is used as given (already encoded);
// when it is not valid in a URL it is percent-encoded.
static NSURL *ll_page_url(NSString *query) {
	if (query == nil) {
		return nil;
	}
	while ([query hasPrefix:@"?"]) {
		query = [query substringFromIndex:1];
	}
	if (query.length == 0) {
		return [NSURL URLWithString:kLLPageURL];
	}
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", kLLPageURL, query]];
	if (url == nil) {
		NSString *encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
		if (encoded != nil) {
			url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", kLLPageURL, encoded]];
		}
	}
	return url;
}

// ---------------------------------------------------------------- the Godot object

void LanternWebView::_bind_methods() {
	ClassDB::bind_method(D_METHOD("open", "root_dir", "query"), &LanternWebView::open);
	ClassDB::bind_method(D_METHOD("close"), &LanternWebView::close);
	ClassDB::bind_method(D_METHOD("post", "json"), &LanternWebView::post);
	ClassDB::bind_method(D_METHOD("poll"), &LanternWebView::poll);
	ClassDB::bind_method(D_METHOD("is_open"), &LanternWebView::is_open);
	ClassDB::bind_method(D_METHOD("stats"), &LanternWebView::stats);
}

bool LanternWebView::open(const String &p_root_dir, const String &p_query) {
	NSString *root = ll_realpath(ll_ns(p_root_dir));
	NSFileManager *files = [NSFileManager defaultManager];
	BOOL directory = NO;
	if (root == nil || ![files fileExistsAtPath:root isDirectory:&directory] || !directory) {
		NSLog(@"WebView: open: the root is not a folder");
		return false;
	}
	directory = NO;
	if (![files fileExistsAtPath:[root stringByAppendingPathComponent:@"index.html"] isDirectory:&directory] || directory) {
		NSLog(@"WebView: open: no index.html in the root");
		return false;
	}
	NSURL *url = ll_page_url(ll_ns(p_query));
	if (url == nil) {
		NSLog(@"WebView: open: the query is not usable in a URL");
		return false;
	}
	ll_open.store(true);
	if ([NSThread isMainThread]) {
		return [[LLWebViewHost shared] openRoot:root url:url];
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[[LLWebViewHost shared] openRoot:root url:url];
	});
	return true;
}

void LanternWebView::close() {
	ll_open.store(false);
	ll_loaded.store(false);
	if ([NSThread isMainThread]) {
		[[LLWebViewHost shared] close];
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[[LLWebViewHost shared] close];
	});
}

bool LanternWebView::post(const String &p_json) {
	if (!ll_open.load() || !ll_loaded.load() || ll_in_flight.load() >= kLLMaxInFlight) {
		ll_dropped++;
		return false;
	}
	NSString *json = ll_ns(p_json);
	if (json == nil || json.length == 0) {
		ll_dropped++;
		return false;
	}
	NSString *script = [NSString stringWithFormat:@"window.LL&&window.LL.recv(%@)", json];
	uint32_t generation = ll_generation.load();
	ll_in_flight++;
	if ([NSThread isMainThread]) {
		[[LLWebViewHost shared] evaluate:script generation:generation];
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[LLWebViewHost shared] evaluate:script generation:generation];
		});
	}
	return true;
}

PackedStringArray LanternWebView::poll() {
	PackedStringArray out;
	for (NSString *message in ll_drain()) {
		out.push_back(ll_gd(message));
	}
	return out;
}

bool LanternWebView::is_open() const {
	return ll_open.load();
}

Dictionary LanternWebView::stats() const {
	double footprint_mb = -1.0;
	task_vm_info_data_t info;
	mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
		footprint_mb = (double)info.phys_footprint / (1024.0 * 1024.0);
	}
	Dictionary out;
	out["thermal"] = (int)[[NSProcessInfo processInfo] thermalState];
	out["footprint_mb"] = footprint_mb;
	out["dropped"] = (int64_t)ll_dropped.load();
	out["web_process_terminated"] = (int64_t)ll_terminated.load();
	out["poll_dropped"] = (int64_t)ll_poll_dropped.load();
	out["js_errors"] = (int64_t)ll_js_errors.load();
	out["in_flight"] = (int)ll_in_flight.load();
	out["loaded"] = (bool)ll_loaded.load();
	return out;
}

LanternWebView::LanternWebView() {}
LanternWebView::~LanternWebView() {}

void web_view_init() {
	web_view_instance = memnew(LanternWebView);
	Engine::get_singleton()->add_singleton(Engine::Singleton("WebView", web_view_instance));
}

void web_view_deinit() {
	if (web_view_instance) {
		web_view_instance->close();
		memdelete(web_view_instance);
		web_view_instance = nullptr;
	}
}
