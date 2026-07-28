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

sed -i 's/use adblock::engine::Engine;/use adblock::Engine;/' rust/adblock-jni/src/lib.rs

rm -f rust/adblock-jni/Cargo.lock

git add -A
git commit -q -m "Fix: correct Engine import path (adblock::Engine, not adblock::engine::Engine)"

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
