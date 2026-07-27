#!/data/data/com.termux/files/usr/bin/bash
# =============================================================
#  اضافه کردن ادبلاکر سبک (لیست دامنه) به مرورگر ساده
#  توکن رو موقع اجرا میپرسه، توی فایل ذخیره نمیشه
# =============================================================
set -e

GITHUB_USERNAME="mmadmehdi"
REPO_NAME="simple-browser"

read -s -p "GitHub Token رو وارد کن (نمایش داده نمیشه): " GITHUB_TOKEN
echo ""

if [ -z "$GITHUB_TOKEN" ]; then
  echo "!! توکن خالیه، دوباره اجرا کن."
  exit 1
fi

PKG="com.simple.browser"
PKG_PATH=$(echo "$PKG" | tr '.' '/')
PROJECT_DIR="$HOME/$REPO_NAME"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "!! پوشه پروژه پیدا نشد ($PROJECT_DIR). اول باید پروژه اصلی رو ساخته باشی."
  exit 1
fi

cd "$PROJECT_DIR"

# ------------------------- لیست دامنه‌های تبلیغاتی --------------------------
mkdir -p app/src/main/assets
cat > app/src/main/assets/adblock_list.txt << 'EOF'
doubleclick.net
googlesyndication.com
googleadservices.com
adservice.google.com
googletagservices.com
googletagmanager.com
adnxs.com
taboola.com
outbrain.com
criteo.com
scorecardresearch.com
moatads.com
adsafeprotected.com
pubmatic.com
rubiconproject.com
openx.net
casalemedia.com
adform.net
media.net
mopub.com
applovin.com
ads.yahoo.com
amazon-adsystem.com
bidswitch.net
smartadserver.com
yieldmo.com
zedo.com
adroll.com
EOF

# ------------------------------ MainActivity.java (به‌روزرسانی) ---------------
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

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class MainActivity extends Activity {

    private FrameLayout webContainer;
    private LinearLayout tabBar;
    private EditText addressBar;

    private final List<WebView> tabs = new ArrayList<>();
    private int currentTab = -1;
    private final Set<String> adDomains = new HashSet<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        loadAdBlockList();

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

    private void loadAdBlockList() {
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(getAssets().open("adblock_list.txt")))) {
            String line;
            while ((line = br.readLine()) != null) {
                line = line.trim();
                if (!line.isEmpty() && !line.startsWith("#")) {
                    adDomains.add(line);
                }
            }
        } catch (Exception e) {
            // اگه فایل نبود، سکوت میکنیم و بدون ادبلاک ادامه میدیم
        }
    }

    private boolean isAdRequest(String url) {
        if (url == null) return false;
        for (String domain : adDomains) {
            if (url.contains(domain)) return true;
        }
        return false;
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
                if (isAdRequest(url)) {
                    // جواب خالی برمیگردونیم تا درخواست تبلیغ بارگذاری نشه
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
        deleteDatabase("webview.db");
        super.onDestroy();
    }
}
EOF

# =================================================================
#  گیت: کامیت و پوش
# =================================================================
git add -A
git commit -q -m "Add lightweight domain-based ad blocking (no Rust/NDK needed)"

REMOTE_URL="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"
git push -u origin main

unset GITHUB_TOKEN

echo ""
echo "=================================================================="
echo "✅ پوش شد. برو به تب Actions تا بیلد جدید با ادبلاکر انجام بشه:"
echo "   https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/actions"
echo "=================================================================="
