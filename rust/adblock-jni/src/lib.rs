use adblock::Engine;
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
