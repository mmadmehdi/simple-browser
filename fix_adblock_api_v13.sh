#!/data/data/com.termux/files/usr/bin/bash
# =============================================================
#  رفع خطای API adblock 0.13: تغییر نام توابع lib.rs
# =============================================================
set -e

GITHUB_USERNAME="mmadmehdi"
REPO_NAME="simple-browser"
PKG="com.simple.browser"

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

cat > rust/adblock-jni/src/lib.rs << 'EOF'
use adblock::lists::{FilterFormat, FilterSet};
use adblock::request::Request;
use adblock::Engine;
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

    let mut filter_set = FilterSet::new(false);
    filter_set.add_filter_list(&rules_str, FilterFormat::Standard);
    let engine = Engine::new_with_filter_set(filter_set);

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

    let request = match Request::new(&url_str, &source_str, &rtype_str) {
        Ok(r) => r,
        Err(_) => return JNI_FALSE,
    };

    let result = engine.check_network_request(&request);
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

rm -f rust/adblock-jni/Cargo.lock

git add -A
git commit -q -m "Fix: adapt Rust code to adblock 0.13 API (add_filter_list/new_with_filter_set/check_network_request)"

REMOTE_URL="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"
git push -u origin main

unset GITHUB_TOKEN

echo ""
echo "=================================================================="
echo "✅ پوش شد. برو تب Actions و بیلد جدید رو چک کن:"
echo "   https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/actions"
echo "اگه بازم API فرق داشت (adblock-rust مدام تغییر میکنه)، لاگ رو بفرست."
echo "=================================================================="
