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

# این کد دقیقاً بر اساس سورس واقعیِ دانلود شده‌ی adblock v0.9.8 نوشته شده،
# نه حدس از مستندات: add_filters + from_filter_set + Request::new(3 args)
# + check_network_request(&Request) + result.matched
cat > rust/adblock-jni/src/lib.rs << 'EOF'
use adblock::request::Request;
use adblock::lists::{FilterSet, ParseOptions};
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
git commit -q -m "Fix: use verified adblock 0.9.8 API (Request::new + check_network_request + matched), confirmed against actual crate source"

REMOTE_URL="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"
git push -u origin main

unset GITHUB_TOKEN

echo ""
echo "=================================================================="
echo "✅ پوش شد. تب Actions رو چک کن:"
echo "   https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/actions"
echo "=================================================================="
