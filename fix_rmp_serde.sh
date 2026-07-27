#!/data/data/com.termux/files/usr/bin/bash
# =============================================================
#  رفع خطای rmp-serde: آپدیت نسخه adblock به 0.13
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

PROJECT_DIR="$HOME/$REPO_NAME"
if [ ! -d "$PROJECT_DIR" ]; then
  echo "!! پوشه پروژه پیدا نشد ($PROJECT_DIR)."
  exit 1
fi
cd "$PROJECT_DIR"

sed -i 's/adblock = "0.9"/adblock = "0.13"/' rust/adblock-jni/Cargo.toml

# لاک فایل قدیمی رو هم پاک میکنیم تا نسخه‌های جدید و سازگار resolve بشن
rm -f rust/adblock-jni/Cargo.lock

git add -A
git commit -q -m "Fix: bump adblock crate to 0.13 (rmp-serde incompatibility)"

REMOTE_URL="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"
git push -u origin main

unset GITHUB_TOKEN

echo ""
echo "=================================================================="
echo "✅ پوش شد. برو تب Actions و بیلد جدید رو چک کن:"
echo "   https://github.com/${GITHUB_USERNAME}/${REPO_NAME}/actions"
echo "=================================================================="
