package com.simple.browser;

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
