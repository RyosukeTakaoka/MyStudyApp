#!/bin/bash
# =====================================================================
# release.sh … TestFlight(内部テスト)に上げるまでを、ターミナルだけで行うスクリプト
#
# 使い方(ターミナルで):
#   cd ~/Desktop/MyStudyApp
#   ./scripts/release.sh            ← 最新のコードを取りこんでからアップロード
#   ./scripts/release.sh --no-pull  ← 今の手元のコードのままアップロード
#
# やること:
#   1. 準備の確認(Xcode・秘密の設定ファイル)
#   2. 最新のコードを取りこむ(git pull)
#   3. ビルド番号を決める(日時から自動で決めるので、毎回ちがう番号になる)
#   4. Archive(提出用のアプリを作る)
#   5. App Store Connect にアップロード(TestFlight 内部テスト専用)
# =====================================================================

# どこかでエラーが起きたら、そこで止める
set -euo pipefail

# このスクリプトの1つ上のフォルダ(リポジトリのいちばん上)に移動する
cd "$(dirname "$0")/.."

PROJECT="MyStudyApp.xcodeproj"
SCHEME="MyStudyApp"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/MyStudyApp.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
LOG_DIR="$BUILD_DIR/logs"

step() { printf "\n\033[1;34m▶ %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m✗ %s\033[0m\n" "$1"; exit 1; }

# ---------------------------------------------------------------------
step "1/5 準備を確認しています"
# ---------------------------------------------------------------------
if ! xcode-select -p | grep -q "Xcode.app"; then
  fail "コマンドラインの Xcode が「Xcode.app」を向いていません。
次を実行してから、もう一度ためしてください(Mac のパスワードを聞かれます):
  sudo xcode-select -s /Applications/Xcode.app"
fi
if [ ! -f "Config/Secrets.xcconfig" ]; then
  fail "Config/Secrets.xcconfig がありません。docs/SETUP_GUIDE.md のステップ2を見て作ってください。"
fi
echo "Xcode: $(xcodebuild -version | head -1)"

# ---------------------------------------------------------------------
step "2/5 最新のコードを取りこみます"
# ---------------------------------------------------------------------
if [ "${1:-}" = "--no-pull" ]; then
  echo "--no-pull が指定されたので、取りこみはしません"
else
  # Xcode が自動で書きかえたプロジェクトファイルを元に戻してから取りこむ
  git checkout -- "$PROJECT" Config
  git pull --ff-only
fi
echo "コード: $(git log --oneline -1)"

# ---------------------------------------------------------------------
step "3/5 ビルド番号を決めます"
# ---------------------------------------------------------------------
# 例: 202611131530(2026年11月13日15時30分)。あとから上げるほど大きくなるので、重ならない
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
echo "ビルド番号: $BUILD_NUMBER"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------
step "4/5 Archive を作っています(数分かかります)"
# ---------------------------------------------------------------------
# 細かいログはファイルに書き、画面にはエラーだけを出す
if ! xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    > "$LOG_DIR/archive.log" 2>&1; then
  echo "---- エラーの部分 ----"
  grep -E "error:|\*\* ARCHIVE FAILED" "$LOG_DIR/archive.log" | head -20 || true
  fail "Archive に失敗しました。全部のログ: $LOG_DIR/archive.log"
fi
echo "Archive できました: $ARCHIVE_PATH"

# ---------------------------------------------------------------------
step "5/5 App Store Connect にアップロードしています"
# ---------------------------------------------------------------------
if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -allowProvisioningUpdates \
    > "$LOG_DIR/upload.log" 2>&1; then
  echo "---- エラーの部分 ----"
  grep -E "error:|Error|\*\* EXPORT FAILED" "$LOG_DIR/upload.log" | head -20 || true
  fail "アップロードに失敗しました。全部のログ: $LOG_DIR/upload.log"
fi

printf "\n\033[1;32m✓ アップロードできました(ビルド番号 %s)\033[0m\n" "$BUILD_NUMBER"
echo "App Store Connect の処理が終わると(5〜30分)、TestFlight アプリに届きます。"
