#!/bin/bash

sed -i 's|<application |<application android:extractNativeLibs="false" |' chrome/android/java/AndroidManifest.xml
sed -i 's|<data android:mimeType="message/rfc822"/>|<data android:mimeType="message/rfc822"/><data android:mimeType="application/pdf"/>|' chrome/android/java/AndroidManifest.xml
sed -i '/com.google.ar.core.min_apk_version/d' third_party/arcore-android-sdk-client/AndroidManifest_basesplit.xml
# sed -i 's|Google LLC|jqssun, Google LLC|' chrome/browser/ui/android/strings/android_chrome_strings.grd

sed -i '/android_apk_or_module_srcjar_deps_common/{n;s|if (!_omit_dex) {|if (_is_base_module \&\& !_omit_dex) {|}' build/config/android/rules.gni
sed -i '/safelyRemovePreference(prefFragment/d' vanadium/chromium_src/chrome/browser/language/android/java/src/org/chromium/chrome/browser/language/settings/LanguageSettingsExt.java # language
sed -i '/safelyRemovePreference($/{N;/PREF_JAVASCRIPT_OPTIMIZER/d}' vanadium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/privacy/settings/PrivacySettingsExt.java # optimizer
sed -i 's|if (!Intent\.ACTION_VIEW\.equals(intent\.getAction())) {|if (!Intent.ACTION_VIEW.equals(intent.getAction()) \|\| !android.webkit.URLUtil.isNetworkUrl(IntentHandler.getUrlFromIntent(intent))) {|' vanadium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard
sed -i 's|if (urlFromIntent == null) {|if (!android.webkit.URLUtil.isNetworkUrl(urlFromIntent)) {|' vanadium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard
sed -i 's|static void maybeModifyCustomTabIntents(Intent intent) {|& if (!android.webkit.URLUtil.isNetworkUrl(IntentHandler.getUrlFromIntent(intent))) { return; }|' vanadium/chromium_src/chrome/android/java/src/org/chromium/chrome/browser/LaunchIntentDispatcherHooks.java # scheme guard
sed -i 's|readBoolean(getSettingsPreferenceKey(moduleType), true)|readBoolean(getSettingsPreferenceKey(moduleType), !HomeModulesUtils.belongsToEducationalTipModule(moduleType))|' chrome/browser/magic_stack/android/java/src/org/chromium/chrome/browser/magic_stack/HomeModulesConfigManager.java # ntp
sed -i 's|private static boolean verifyPackage(Context ctx, String pkgName, byte\[\] sha256CertDigestBytes) {|& if (true) return false; |' vanadium/android_config/parser/java/src/app/vanadium/config/VanadiumConfParser.java # config parser
sed -i 's|static boolean isSupported() {|& if (android.os.Build.VERSION.SDK_INT < 31) return false;|;s|LocationManager locationManager, LocationListener listener) {|& if (android.os.Build.VERSION.SDK_INT < 31) return false;|' vanadium/chromium_src/services/downstream/device/geolocation/android/java/src/org/chromium/device/geolocation/CoarseLocationRequests.java # api

# sed -i 's|int ExpirationMilestoneForFlag(const char\* flag) {|int ExpirationMilestoneForFlag(const char* flag) { if ((true)) return -1;|' chrome/browser/unexpire_flags.cc
for flag in "align-wakeups" "android-bottom-bar" "cct-open-in-browser-button-if-allowed-by-embedder" "darken-websites-checkbox-in-themes-setting" "enable-accessibility-sequential-focus" "enforce-incognito-isolation" "inline-pdf-v2" "jump-start-omnibox" "lock-controls-on-tablets-v2" "offline-auto-fetch" "use-fullscreen-insets-api"; do
    sed -i "/\"name\": \"$flag\"/,/}/ s/\"expiry_milestone\": [0-9]\+/\"expiry_milestone\": -1/" chrome/browser/flag-metadata.json
done
sed -i 's|newFlag(OmniboxFeatureList.OMNIBOX_SITE_SEARCH, FeatureState.ENABLED_IN_TEST);|newFlag(OmniboxFeatureList.OMNIBOX_SITE_SEARCH, FeatureState.ENABLED_IN_PROD);|' components/omnibox/common/android/java/src/org/chromium/components/omnibox/OmniboxFeatures.java # search
sed -i 's|BASE_FEATURE(kOmniboxSiteSearch, DISABLED);|BASE_FEATURE(kOmniboxSiteSearch, ENABLED);|' components/omnibox/common/omnibox_features.cc # search

# accessibility
sed -i 's|ChromeAccessibilityUtil.get().isAccessibilityEnabled()|org.chromium.ui.accessibility.AccessibilityState.isComplexUserInteractionServiceEnabled() \|\| org.chromium.ui.accessibility.AccessibilityState.isTouchExplorationEnabled()|' chrome/android/java/src/org/chromium/chrome/browser/tab/TabStateBrowserControlsVisibilityDelegate.java
sed -i 's|AccessibilityState.isPerformGesturesEnabled()|(AccessibilityState.isComplexUserInteractionServiceEnabled() \|\| AccessibilityState.isTouchExplorationEnabled())|' chrome/browser/ui/messages/android/java/src/org/chromium/chrome/browser/ui/messages/snackbar/SnackbarManager.java

# playback
sed -i 's|#if BUILDFLAG(IS_ANDROID)|#if 0|' content/public/renderer/render_frame_media_playback_options.cc

# crbug.com/445475304: incognito back
sed -i 's|private void onTabChanged(@Nullable Tab tab) {|private void onTabChanged(@Nullable Tab tab) { if (tab != null \&\& tab.isIncognitoBranded()) { mSystemBackPressSupplier.set(true); return; }|' chrome/browser/back_press/android/java/src/org/chromium/chrome/browser/back_press/MinimizeAppAndCloseTabBackPressHandler.java

# crbug.com/431004500: incognito uaf
sed -i '/for (int i = 0; i < tab_list->GetTabCount(); ++i) {/i if (!tab_list) { continue; }' chrome/browser/extensions/api/tabs/tabs_api.cc

# crbug.com/40274462: incognito uaf
sed -i '/CONTENT_EXPORT static WebContents\* FromRenderFrameHost(RenderFrameHost\* rfh);/a\CONTENT_EXPORT static bool HasLiveWebContentsForBrowserContext(BrowserContext* browser_context);' content/public/browser/web_contents.h
sed -i '/^WebContentsImpl::WebContentsImpl(BrowserContext\* browser_context)/i\ bool WebContents::HasLiveWebContentsForBrowserContext(BrowserContext* browser_context) { for (WebContentsImpl* web_contents : WebContentsImpl::GetAllWebContents()) { if (web_contents->GetBrowserContext() == browser_context) { return true; } } return false; }' content/browser/web_contents/web_contents_impl.cc
sed -i '/#include "content\/public\/browser\/render_process_host.h"/a#include "content/public/browser/web_contents.h"' chrome/browser/profiles/profile_destroyer.cc
sed -i '/^void ProfileDestroyer::DestroyOTRProfileWhenAppropriateWithTimeout($/,/MaybeSendDestroyedNotification/{/  profile->MaybeSendDestroyedNotification();/i\
if (content::WebContents::HasLiveWebContentsForBrowserContext(profile)) { return; }
}' chrome/browser/profiles/profile_destroyer.cc

# crbug.com/444024982: api 31
sed -i 's/|| mSupportedProfileType == SupportedProfileType.REGULAR) {/|| mSupportedProfileType == SupportedProfileType.REGULAR || mSupportedProfileType == SupportedProfileType.MIXED) {/' chrome/android/java/src/org/chromium/chrome/browser/ChromeTabbedActivity.java
sed -i 's/|| mSupportedProfileType == SupportedProfileType.OFF_THE_RECORD) {/|| mSupportedProfileType == SupportedProfileType.OFF_THE_RECORD || mSupportedProfileType == SupportedProfileType.MIXED) {/' chrome/android/java/src/org/chromium/chrome/browser/ChromeTabbedActivity.java


# Yttrium

# bottom: menu
sed -i 's|mModelList = mDelegate.getMenuItems();|&\n        if (isFromBottomBar \|\| mBrowserControlsStateProvider.getControlsPosition() == BrowserControlsStateProvider.ControlsPosition.BOTTOM) { for (int i = 0; i < mModelList.size(); i++) mModelList.move(mModelList.size() - 1, i); }|' chrome/browser/ui/android/appmenu/internal/java/src/org/chromium/chrome/browser/ui/appmenu/AppMenuHandlerImpl.java # reverse in place
sed -i 's|mListView = contentView.findViewById(R.id.app_menu_list);|&\n        mListView.setStackFromBottom(isFromBottomBar \|\| controlsPosition == ControlsPosition.BOTTOM);|' chrome/browser/ui/android/appmenu/internal/java/src/org/chromium/chrome/browser/ui/appmenu/AppMenu.java
sed -i 's|getInitialHeightForView(i)|getInitialHeightForView(mListView != null \&\& mListView.isStackFromBottom() ? itemCount - 1 - i : i)|;s|canBeLastVisibleInitialView(i)|canBeLastVisibleInitialView(mListView != null \&\& mListView.isStackFromBottom() ? itemCount - 1 - i : i)|' chrome/browser/ui/android/appmenu/internal/java/src/org/chromium/chrome/browser/ui/appmenu/AppMenu.java # size from bottom

# bottom: ntp
sed -i 's|        super.onMeasure(widthMeasureSpec, heightMeasureSpec);|&\n        maybeAlignContentToBottom(widthMeasureSpec);|' chrome/android/java/src/org/chromium/chrome/browser/ntp/NewTabPageLayout.java
sed -i '/\/\*\* Sets the delegate instance. \*\//i\
    private boolean mBottomAlignListenerAdded;\
\
    /** Aligns the content to the bottom of the viewport when the toolbar is configured at the bottom. */\
    private void maybeAlignContentToBottom(int widthMeasureSpec) {\
        if (!org.chromium.chrome.browser.toolbar.ToolbarPositionController.isToolbarPositionCustomizationEnabled(getContext(), false)\
                || org.chromium.chrome.browser.toolbar.ToolbarPositionController.shouldShowToolbarOnTop(null)) {\
            return;\
        }\
        android.view.ViewParent parent = getParent();\
        while (parent != null && !(parent instanceof androidx.recyclerview.widget.RecyclerView)) parent = parent.getParent();\
        if (parent == null) return;\
        androidx.recyclerview.widget.RecyclerView recyclerView = (androidx.recyclerview.widget.RecyclerView) parent;\
        // Leave the layout alone when the feed follows the header.\
        if (recyclerView.getAdapter() == null || recyclerView.getAdapter().getItemCount() > 1) return;\
        if (!mBottomAlignListenerAdded) {\
            mBottomAlignListenerAdded = true;\
            recyclerView.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> { if (b - t != ob - ot) post(this::requestLayout); });\
        }\
        int height = recyclerView.getHeight() - recyclerView.getPaddingTop() - recyclerView.getPaddingBottom();\
        if (height <= getMeasuredHeight()) return;\
        setGravity(android.view.Gravity.CENTER_HORIZONTAL | android.view.Gravity.BOTTOM);\
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY));\
    }\

' chrome/android/java/src/org/chromium/chrome/browser/ntp/NewTabPageLayout.java

# disable-external-intent-requests
sed -i '/ExternalNavigationParams params, Intent intent) {/,/^    }$/s#return false;#if ("tel".equals(params.getUrl().getScheme())) return false;\n        return !org.chromium.chrome.browser.TabPreferencesUtils.shouldOpenLinksInIncognito();#' chrome/android/java/src/org/chromium/chrome/browser/externalnav/ExternalNavigationDelegateImpl.java
sed -i '/public boolean shouldDisableAllExternalIntents() {/a\            if (!org.chromium.chrome.browser.TabPreferencesUtils.shouldOpenLinksInIncognito()) return true;' chrome/android/java/src/org/chromium/chrome/browser/customtabs/CustomTabDelegateFactory.java

export PATCHED=1