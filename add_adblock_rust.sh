#!/data/data/com.termux/files/usr/bin/bash
# =============================================================
#  اضافه کردن adblock-rust واقعی (موتور EasyList/EasyPrivacy) به مرورگر
#  از طریق JNI + کامپایل Rust برای اندروید داخل GitHub Actions
#  (بکاپ قبلاً گرفته شده: تگ/برنچ backup-stable)
# =============================================================
set -e

GITHUB_USERNAME="mmadmehdi"
REPO_NAME="simple-browser"
PKG="com.simple.browser"
PKG_PATH=$(echo "$PKG" | tr '.' '/')

read -s -p "GitHub Token رو وارد کن (نمایش داده نمیشه): " GITHUB_TOKEN
echo ""
if [ -z "$GITHUB_TOKEN" ]; then
  echo "!! توکن خالیه، دوباره اجرا کن."
  exit 1
fi

PROJECT_DIR="$HOME/$REPO_NAME"
if [ ! -d "$PROJECT_DIR" ]; then
  echo "!! پوشه پروژه پیدا نشد ($PROJECT_DIR)."
  exit 1
fi
cd "$PROJECT_DIR"

# =================================================================
#  1) کد Rust که adblock-rust رو با JNI wrap می‌کنه
# =================================================================
mkdir -p rust/adblock-jni/src

cat > rust/adblock-jni/Cargo.toml << 'EOF'
[package]
name = "adblock_jni"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
adblock = "0.9"
jni = "0.21"

[profile.release]
opt-level = "z"
lto = true
EOF

cat > rust/adblock-jni/src/lib.rs << 'EOF'
use adblock::engine::Engine;
use adblock::lists::{FilterSet, ParseOptions};
use jni::objects::{JClass, JString};
use jni::sys::{jboolean, jlong, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;

#[no_mangle]
pub extern "system" fn Java_com_simple_browser_AdBlockEngine_nativeCreate(
    mut env: JNIEnv,
    _class: JClass,
    rules: JString,
) -> jlong {
    let rules_str: String = match env.get_string(&rules) {
        Ok(s) => s.into(),
        Err(_) => return 0,
    };

    let lines: Vec<String> = rules_str.lines().map(|s| s.to_string()).collect();

    let mut filter_set = FilterSet::new(false);
    filter_set.add_filters(&lines, ParseOptions::default());
    let engine = Engine::from_filter_set(filter_set, true);

    Box::into_raw(Box::new(engine)) as jlong
}

#[no_mangle]
pub extern "system" fn Java_com_simple_browser_AdBlockEngine_nativeShouldBlock(
    mut env: JNIEnv,
    _class: JClass,
    handle: jlong,
    url: JString,
    source_url: JString,
    request_type: JString,
) -> jboolean {
    if handle == 0 {
        return JNI_FALSE;
    }
    let engine = unsafe { &*(handle as *const Engine) };

    let url_str: String = match env.get_string(&url) {
        Ok(s) => s.into(),
        Err(_) => return JNI_FALSE,
    };
    let source_str: String = match env.get_string(&source_url) {
        Ok(s) => s.into(),
        Err(_) => return JNI_FALSE,
    };
    let rtype_str: String = match env.get_string(&request_type) {
        Ok(s) => s.into(),
        Err(_) => return JNI_FALSE,
    };

    let result = engine.check_network_urls(&url_str, &source_str, &rtype_str);
    if result.matched {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

#[no_mangle]
pub extern "system" fn Java_com_simple_browser_AdBlockEngine_nativeDestroy(
    _env: JNIEnv,
    _class: JClass,
    handle: jlong,
) {
    if handle != 0 {
        unsafe {
            drop(Box::from_raw(handle as *mut Engine));
        }
    }
}
EOF

# =================================================================
#  2) کلاس جاوای AdBlockEngine که با JNI صحبت میکنه
# =================================================================
cat > "app/src/main/java/$PKG_PATH/AdBlockEngine.java" << EOF
package $PKG;

import android.content.Context;
import java.io.BufferedReader;
import java.io.InputStreamReader;

public class AdBlockEngine {

    static {
        System.loadLibrary("adblock_jni");
    }

    private long handle = 0;

    public AdBlockEngine(Context context) {
        String rules = loadRules(context);
        handle = nativeCreate(rules);
    }

    private String loadRules(Context context) {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(context.getAssets().open("easylist.txt")))) {
            String line;
            while ((line = br.readLine()) != null) {
                sb.append(line).append("\n");
            }
        } catch (Exception e) {
            // اگه فایل قوانین نبود، موتور با لیست خالی بالا میاد (بلاک نمیکنه)
        }
        return sb.toString();
    }

    public boolean shouldBlock(String url, String sourceUrl, String requestType) {
        if (handle == 0) return false;
        try {
            return nativeShouldBlock(handle, url, sourceUrl == null ? "" : sourceUrl,
                    requestType == null ? "other" : requestType);
        } catch (Throwable t) {
            return false;
        }
    }

    public void destroy() {
        if (handle != 0) {
            nativeDestroy(handle);
            handle = 0;
        }
    }

    private native long nativeCreate(String rules);
    private native boolean nativeShouldBlock(long handle, String url, String sourceUrl, String requestType);
    private native void nativeDestroy(long handle);
}
EOF

# =================================================================
#  3) MainActivity: استفاده از AdBlockEngine واقعی به‌جای لیست دامنه‌ی ساده
# =================================================================
cat > "app/src/main/java/$PKG_PATH/MainActivity.java" << EOF
package $PKG;

import android.app.Activity;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebStorage;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;

import java.io.ByteArrayInputStream;
import java.util.ArrayList;
import java.util.List;

public class MainActivity extends Activity {

    private FrameLayout webContainer;
    private LinearLayout tabBar;
    private EditText addressBar;

    private final List<WebView> tabs = new ArrayList<>();
    private int currentTab = -1;
    private AdBlockEngine adBlockEngine;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        adBlockEngine = new AdBlockEngine(this);

        webContainer = findViewById(R.id.webContainer);
        tabBar = findViewById(R.id.tabBar);
        addressBar = findViewById(R.id.addressBar);
        Button goButton = findViewById(R.id.goButton);

        goButton.setOnClickListener(v -> loadInput());
        addressBar.setOnEditorActionListener((v, actionId, event) -> {
            loadInput();
            return true;
        });

        addNewTab("https://www.google.com");
        addPlusButton();
    }

    private void loadInput() {
        String input = addressBar.getText().toString().trim();
        if (input.isEmpty() || currentTab == -1) return;
        tabs.get(currentTab).loadUrl(resolveUrl(input));
    }

    private String resolveUrl(String input) {
        boolean looksLikeUrl = input.contains(".") && !input.contains(" ");
        if (input.startsWith("http://") || input.startsWith("https://")) {
            return input;
        } else if (looksLikeUrl) {
            return "https://" + input;
        } else {
            return "https://www.google.com/search?q=" + android.net.Uri.encode(input);
        }
    }

    @SuppressWarnings("SetJavaScriptEnabled")
    private WebView createWebView() {
        WebView wv = new WebView(this);
        wv.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        WebSettings s = wv.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setSupportMultipleWindows(false);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);
        s.setSaveFormData(false);
        s.setDatabaseEnabled(false);

        wv.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                String url = request.getUrl().toString();
                String pageUrl = view.getUrl();
                String rtype = request.isForMainFrame() ? "document" : "other";

                if (adBlockEngine.shouldBlock(url, pageUrl, rtype)) {
                    return new WebResourceResponse("text/plain", "utf-8",
                            new ByteArrayInputStream(new byte[0]));
                }
                return super.shouldInterceptRequest(view, request);
            }
        });
        wv.setWebChromeClient(new WebChromeClient());
        return wv;
    }

    private void addNewTab(String url) {
        WebView wv = createWebView();
        tabs.add(wv);
        int index = tabs.size() - 1;

        Button tabButton = new Button(this);
        tabButton.setText("تب " + (index + 1));
        tabButton.setOnClickListener(v -> switchToTab(index));
        tabBar.addView(tabButton, tabBar.getChildCount() > 0 ? tabBar.getChildCount() - 1 : 0);

        switchToTab(index);
        wv.loadUrl(url);
    }

    private void addPlusButton() {
        Button plus = new Button(this);
        plus.setText("+");
        plus.setOnClickListener(v -> addNewTab("https://www.google.com"));
        tabBar.addView(plus);
    }

    private void switchToTab(int index) {
        webContainer.removeAllViews();
        currentTab = index;
        webContainer.addView(tabs.get(index));
        addressBar.setText(tabs.get(index).getUrl());
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK && currentTab != -1 && tabs.get(currentTab).canGoBack()) {
            tabs.get(currentTab).goBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    @Override
    protected void onDestroy() {
        CookieManager.getInstance().removeAllCookies(null);
        WebStorage.getInstance().deleteAllData();
        for (WebView wv : tabs) {
            wv.clearHistory();
            wv.clearCache(true);
            wv.destroy();
        }
        if (adBlockEngine != null) adBlockEngine.destroy();
        deleteDatabase("webview.db");
        super.onDestroy();
    }
}
EOF

# لیست دامنه‌ای قبلی دیگه لازم نیست (موتور جدید از easylist.txt استفاده میکنه)
rm -f app/src/main/assets/adblock_list.txt

# =================================================================
#  4) GitHub Actions: نصب Rust + NDK + cargo-ndk، دانلود EasyList، کامپایل و بیلد
# =================================================================
cat > .github/workflows/build.yml << 'EOF'
name: Build APK

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Set up Android SDK
        uses: android-actions/setup-android@v3

      - name: Install Android NDK
        run: sdkmanager --install "ndk;26.1.10909125"

      - name: Set up Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: aarch64-linux-android, armv7-linux-androideabi, i686-linux-android, x86_64-linux-android

      - name: Install cargo-ndk
        run: cargo install cargo-ndk

      - name: Download EasyList + EasyPrivacy
        run: |
          mkdir -p app/src/main/assets
          curl -sL https://easylist.to/easylist/easylist.txt -o app/src/main/assets/easylist.txt
          curl -sL https://easylist.to/easylist/easyprivacy.txt >> app/src/main/assets/easylist.txt

      - name: Build Rust library for Android (all ABIs)
        working-directory: rust/adblock-jni
        env:
          ANDROID_NDK_HOME: ${{ env.ANDROID_HOME }}/ndk/26.1.10909125
        run: |
          cargo ndk -t arm64-v8a -t armeabi-v7a -t x86 -t x86_64 -o ../../app/src/main/jniLibs build --release

      - name: Set up Gradle
        uses: gradle/actions/setup-gradle@v3

      - name: Assemble Debug APK
        run: gradle assembleDebug

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: simple-browser-debug
          path: app/build/outputs/apk/debug/app-debug.apk
EOF

# jniLibs رو از گیت‌ایگنور مستثنی نمیکنیم چون در بیلد ساخته میشن و لازم نیست کامیت بشن؛
# ولی مطمئن میشیم که در build/ (که ایگنور شده) نباشن مشکلی پیش نیاد
cat >> .gitignore << 'EOF'
rust/**/target/
app/src/main/jniLibs/
app/src/main/assets/easylist.txt
EOF

# =================================================================
#  5) کامیت و پوش
# =================================================================
git add -A
git commit -q -m "Attempt: real adblock-rust integration via JNI + cargo-ndk (EasyList/EasyPrivacy)"

REMOTE_URL="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"
git push -u origin main

unset GITHUB_TOKEN

echo ""
echo "=================================================================="
echo "پوش شد. این یه تلاش واقعیه و ممکنه اولین بار fail بشه، برو تب Actions:"
echo "   https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/actions"
echo "اگه ارور داد، خروجی لاگ رو برام بفرست تا دیباگ کنم."
echo "اگه خواستی برگردی به نسخه‌ی سبک قبلی:  git checkout backup-stable"
echo "=================================================================="
