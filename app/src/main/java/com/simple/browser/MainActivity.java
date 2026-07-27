package com.simple.browser;

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
