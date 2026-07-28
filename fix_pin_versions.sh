#!/data/data/com.termux/files/usr/bin/bash
set -e

GITHUB_USERNAME="mmadmehdi"
REPO_NAME="simple-browser"

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

# پین کردن دقیق نسخه‌ها تا کارگو دیگه نسخه‌ی ناسازگار rmp رو انتخاب نکنه
cat > rust/adblock-jni/Cargo.toml << 'EOF'
[package]
name = "adblock_jni"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
adblock = "=0.9.8"
rmp = "=0.8.11"
rmp-serde = "=0.15.5"
jni = "0.21"

[profile.release]
opt-level = "z"
lto = true
EOF

# برگشت به API ساده و مستند نسخه 0.9 (add_filters / from_filter_set / check_network_urls)
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

rm -f rust/adblock-jni/Cargo.lock

git add -A
git commit -q -m "Fix: pin adblock=0.9.8 + rmp/rmp-serde exact versions, revert to documented stable API"

REMOTE_URL="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"
git push -u origin main

unset GITHUB_TOKEN

echo ""
echo "=================================================================="
echo "✅ پوش شد. تب Actions رو چک کن:"
echo "   https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/actions"
echo "اگه بازم ارور داد، لاگ رو بفرست."
echo "=================================================================="
