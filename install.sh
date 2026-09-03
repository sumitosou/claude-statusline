#!/bin/bash
# Claude Code ステータスライン インストーラー
#   使い方:  bash install.sh
#   やること: スクリプトを ~/.claude/ にコピーし、~/.claude/settings.json に statusLine 設定を書き込む
set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
TARGET="$CLAUDE_DIR/statusline-command.sh"

# --- jq の確認 ---
if ! command -v jq >/dev/null 2>&1; then
    echo "jq が見つかりません。先にインストールしてください:"
    echo "  Windows : winget install jqlang.jq"
    echo "  macOS   : brew install jq"
    echo "  Ubuntu  : sudo apt install jq"
    exit 1
fi

# --- スクリプトのコピー ---
mkdir -p "$CLAUDE_DIR"
if [ -f "$TARGET" ]; then
    cp "$TARGET" "$TARGET.bak-$(date +%Y%m%d-%H%M%S)"
    echo "既存のスクリプトをバックアップしました"
fi
cp "$SRC_DIR/statusline-command.sh" "$TARGET"
chmod +x "$TARGET"
echo "コピー完了: $TARGET"

# --- statusLine の command を OS ごとに決める ---
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        # Windows: PATH 上の bash が WSL に取られないよう Git Bash をフルパスで指定
        GIT_BASH="C:/Program Files/Git/bin/bash.exe"
        WIN_HOME="$(cygpath -m "$HOME")"
        CMD="\"$GIT_BASH\" $WIN_HOME/.claude/statusline-command.sh"
        ;;
    *)
        CMD="bash ~/.claude/statusline-command.sh"
        ;;
esac

# --- settings.json に書き込む ---
if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
else
    echo '{}' > "$SETTINGS"
fi
tmp="$(mktemp)"
jq --arg cmd "$CMD" '.statusLine = {type: "command", command: $cmd, padding: 1, refreshInterval: 5000}' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"
echo "設定完了: $SETTINGS"
echo
echo "statusLine.command = $CMD"
echo "Claude Code を再起動するとステータスラインが表示されます。"
