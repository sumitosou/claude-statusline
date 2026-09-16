# claude-statusline

Claude Code 用の2行ステータスラインです。特殊なフォント(Nerd Font)を使わず、どのターミナルでも文字化けしない一般的な記号だけで表示します。

```
◆ Fable 5.1 │ ctx ★ ★ ★ ★ ☆ ☆ ☆ ☆ ☆ ☆ 42% │ $1.23 │ 5h ★ ★ ★ ★ ☆ ☆ ☆ ☆ ☆ ☆  37% 3h30m/5h reset 00:17
▸ my-project │ ⎇ main +1 ~2 │ ◷ 1h0m +10/-2           │ 7d ★ ☆ ☆ ☆ ☆ ☆ ☆ ☆ ☆ ☆  12%      reset 9/9 17:40
```

## 表示している内容

| 位置 | 項目 | 意味 |
|---|---|---|
| 1行目 | ◆ モデル名 | 使用中のモデル |
| 1行目 | ctx ★☆ % | コンテキスト使用率(星1つ = 10%) |
| 1行目 | $ | このセッションの料金 |
| 1行目 右 | 5h ★☆ % 経過/5h reset 時刻 | 5時間枠の使用率、経過時間、リセット時刻 |
| 2行目 | ▸ フォルダ名 | 作業ディレクトリ |
| 2行目 | ⎇ ブランチ +n ~n ?n | Git ブランチと staged / 変更 / 未追跡の数 |
| 2行目 | py / vi | venv と Vim モード(該当時のみ) |
| 2行目 | ◷ 時間 +n/-n | セッション経過時間、追加/削除行数 |
| 2行目 右 | 7d ★☆ % reset 日時 | 7日枠の使用率とリセット日時 |

- 使用率の色は 50% 未満が緑、50〜79% が黄、80% 以上が赤です。
- 5時間枠が 80% を超えると、1行目の左端に赤い警告バッジが出ます。
- 5h / 7d の値は Claude Code 本体が渡す値を使います。本体が値を渡さない場合だけ、Anthropic の使用量 API から取得します(60秒キャッシュ)。

## 必要なもの

- bash (Windows は Git for Windows に付属の Git Bash)
- jq
  - Windows: `winget install jqlang.jq`
  - macOS: `brew install jq`
  - Ubuntu: `sudo apt install jq`

## インストール

```bash
git clone https://github.com/sumitosou/claude-statusline.git
cd claude-statusline
bash install.sh
```

Windows では Git Bash で実行してください。`install.sh` は次のことをします。

1. `statusline-command.sh` を `~/.claude/` にコピー
2. `~/.claude/settings.json` に `statusLine` 設定を追記(元ファイルはバックアップ)

その後 Claude Code を再起動すると表示されます。

## 手動で設定する場合

`~/.claude/settings.json` に次を追加します。

Windows (ユーザー名の部分は自分のものに変える):

```json
"statusLine": {
  "type": "command",
  "command": "\"C:/Program Files/Git/bin/bash.exe\" C:/Users/ユーザー名/.claude/statusline-command.sh",
  "padding": 1,
  "refreshInterval": 5000
}
```

macOS / Linux:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline-command.sh",
  "padding": 1,
  "refreshInterval": 5000
}
```

## 設定の切り替え

環境変数を Claude Code の `settings.json` の `env` に書くと切り替えられます。

| 変数 | 値 | 効果 |
|---|---|---|
| `STATUSLINE_NERD_FONT` | `1` | Nerd Font のアイコンを使う(対応フォントが必要) |
| `STATUSLINE_THEME` | `light` / `dark` | 背景色に合わせた配色。既定は自動判定 |

星の数はスクリプト内の `STAR_SEGMENTS=10` を変えると調整できます。

## 元にしたもの

[tzengyuxio/claude-statusline](https://github.com/tzengyuxio/claude-statusline) (MIT) をベースに、Windows(Git Bash)対応、星ゲージ、5h/7d の右列配置、Claude Code 本体の使用量値の利用などを加えたものです。
