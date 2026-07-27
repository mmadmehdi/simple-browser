#!/data/data/com.termux/files/usr/bin/bash
# =============================================================
#  بکاپ گرفتن از وضعیت فعلی پروژه، قبل از تلاش برای adblock-rust
#  یه برنچ و یه تگ جدا میسازه و پوش میکنه، کد فعلی main دست نمیخوره
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

REMOTE_URL="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"

BACKUP_TAG="stable-simple-adblock-$(date +%Y%m%d-%H%M%S)"

git add -A
git commit -q -m "checkpoint before adblock-rust attempt" --allow-empty
git tag "$BACKUP_TAG"

# یه برنچ هم میسازیم که راحت‌تر بشه ازش چک‌اوت گرفت
git branch -f backup-stable HEAD

git push origin main
git push origin "$BACKUP_TAG"
git push origin backup-stable -f

unset GITHUB_TOKEN

echo ""
echo "=================================================================="
echo "✅ بکاپ گرفته شد:"
echo "   تگ:    $BACKUP_TAG"
echo "   برنچ:  backup-stable"
echo ""
echo "اگه بعداً نسخه adblock-rust به مشکل خورد، برای برگشت کافیه:"
echo "   git checkout backup-stable"
echo "یا:"
echo "   git checkout $BACKUP_TAG"
echo "=================================================================="
