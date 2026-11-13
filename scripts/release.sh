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
#   5. App Store Connect にアップロード(ふつうの App Store Connect 向け。TestFlight の内部テストで使う)
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
if ! grep -Eq "^DEVELOPMENT_TEAM *= *[A-Z0-9]{10} *$" Config/Secrets.xcconfig; then
  fail "Config/Secrets.xcconfig に Team ID(DEVELOPMENT_TEAM)が書かれていません。
https://developer.apple.com/account の「メンバーシップの詳細」で「チーム ID」(英数字10文字)を調べて、
次のように1行足してください(ABCDE12345 の部分を自分の ID に変える):
  echo 'DEVELOPMENT_TEAM = ABCDE12345' >> Config/Secrets.xcconfig"
fi
if grep -Eq "^DEVELOPMENT_TEAM *= *ABCDE12345" Config/Secrets.xcconfig; then
  fail "Team ID が見本の「ABCDE12345」のままです。自分のチーム ID に書きかえてください:
  sed -i '' 's/^DEVELOPMENT_TEAM = .*/DEVELOPMENT_TEAM = 自分のチームID/' Config/Secrets.xcconfig"
fi
echo "Xcode: $(xcodebuild -version | head -1)"

# iPhone などから SSH でつないでいるときは、Mac のキーチェーン(パスワードや証明書の保管庫)が
# 閉じていて、Xcode のアカウントや署名の証明書が見えない。最初に開けておく
if [ -n "${SSH_CONNECTION:-}" ]; then
  echo "SSH でつながっているので、キーチェーンを開きます。Mac のログインパスワードを入れてください(画面には出ません)"
  security unlock-keychain "$HOME/Library/Keychains/login.keychain-db" \
    || fail "キーチェーンを開けませんでした。パスワードを確かめて、もう一度ためしてください。"
fi

# App Store Connect の API キーがあれば使う(Xcode にログインしていなくても署名・アップロードできる)
AUTH_ARGS=()
if [ -f scripts/asc-api-key.env ]; then
  # shellcheck disable=SC1091
  source scripts/asc-api-key.env
  ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
  [ -f "$ASC_KEY_PATH" ] || fail "API キーのファイルが見つかりません: $ASC_KEY_PATH"
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "App Store Connect API キーを使います(キー ID: $ASC_KEY_ID)"
fi

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
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    > "$LOG_DIR/archive.log" 2>&1; then
  echo "---- エラーの部分 ----"
  grep -E "error:|\*\* ARCHIVE FAILED" "$LOG_DIR/archive.log" | head -20 || true
  if grep -q "No Accounts" "$LOG_DIR/archive.log"; then
    echo ""
    echo "ヒント: ターミナルから Xcode のアカウントが見えていません。"
    echo "  ・Mac の前で、Xcode の 設定 → Accounts に Apple アカウントがあるか確かめる"
    echo "  ・それでもだめなら、App Store Connect の API キーを使う(docs/SETUP_GUIDE.md の「ターミナルからアップロード」)"
  fi
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
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    > "$LOG_DIR/upload.log" 2>&1; then
  echo "---- エラーの部分 ----"
  grep -E "error:|Error|\*\* EXPORT FAILED" "$LOG_DIR/upload.log" | head -20 || true
  fail "アップロードに失敗しました。全部のログ: $LOG_DIR/upload.log"
fi

printf "\n\033[1;32m✓ アップロードできました(ビルド番号 %s)\033[0m\n" "$BUILD_NUMBER"
echo "App Store Connect の処理が終わると(5〜30分)、TestFlight アプリに届きます。"
