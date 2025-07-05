# cc-gc-review

Claude CodeとGeminiをstop hook連携させるサポートツール

## 概要

このツールは、Claude Codeのstop hookから呼び出され、作業内容をGeminiでレビューし、その結果をtmuxセッションに自動送信することで、継続的なフィードバックを実現します。

## 機能

- Claude Codeのstop hookからの自動起動
- 作業内容の自動抽出とGeminiレビュー
- tmuxセッションへの自動フィードバック送信
- ファイル監視による非同期処理
- 柔軟なオプション設定

## 必要な環境

- Bash
- tmux
- jq
- gemini-cli（オプション、なくても動作可能）
- inotifywait または fswatch（オプション、なければポーリング）

## インストール

```bash
git clone https://github.com/yourusername/cc-gc-review.git
cd cc-gc-review
chmod +x *.sh
```

## 使い方

### 1. メインプロセスの起動

```bash
# 基本的な使い方
./cc-gc-review.sh claude

# 自動でClaudeも起動
./cc-gc-review.sh -c claude

# thinkモードを有効化
./cc-gc-review.sh --think claude

# 詳細ログを表示
./cc-gc-review.sh -v claude

# オプション組み合わせ
./cc-gc-review.sh --think -c -v claude

# 既存ファイル再送信付き
./cc-gc-review.sh --resend --think --custom-command "optimize" claude

# カスタムコマンド付き
./cc-gc-review.sh --custom-command "refactor" claude

# 起動時に既存のレビューファイルを再送信
./cc-gc-review.sh --resend claude

# レビュー数を制限
./cc-gc-review.sh --max-reviews 10 claude

# 無制限にレビュー
./cc-gc-review.sh --infinite-review claude
```

起動後、別のターミナルで以下を実行してセッションにアタッチ：
```bash
tmux attach-session -t claude
```

### 2. Claude Codeのhooks設定

`~/.claude/settings.json`に以下を追加：

基本的な設定：
```json
{
  "hooks": {
    "stop": "/path/to/cc-gc-review/hook-handler.sh"
  }
}
```

git diff を確認する設定：
```json
{
  "hooks": {
    "stop": "/path/to/cc-gc-review/hook-handler.sh --git-diff --yolo"
  }
}
```

git commitを確認する設定：
```json
{
  "hooks": {
    "stop": "/path/to/cc-gc-review/hook-handler.sh --git-commit --yolo"
  }
}
```
#### hook-handler.shのオプション

| オプション | 説明 |
|-----------|------|
| `--git-diff` | Geminiに「git diffを実行して作業ファイルの変更内容を把握する」指示を追加 |
| `--git-commit` | Geminiに「git commitを確認し、ファイルの変更内容を把握する」指示を追加 |
| `--yolo`, `-y` | Geminiをyoloモード（-y）で実行 |

**注意**: `--git-diff`や`--git-commit`オプションを使用すると、自動的に`--yolo`モードも有効になります。これはGeminiがgitコマンドを実行する際に確認プロンプトを表示させないためです。
安全のため、`-s` のサンドボックスモードはデフォルトでオンにしています。

レビューファイルは固定で`/tmp/gemini-review`に出力されます。

詳細ログを有効にする場合：

```bash
export CC_GC_REVIEW_VERBOSE="true"
```

## cc-gc-review のオプション

| オプション | 説明 |
|-----------|------|
| `-c, --auto-claude-launch` | 自動でClaudeを起動 |
| `--think` | レビュー内容の後に'think'を追加 |
| `--custom-command COMMAND` | レビュー内容の先頭にカスタムコマンド（/COMMAND）を付加 |
| `--resend` | 起動時に既存のレビューファイルがあれば再送信 |
| `--max-reviews N` | レビュー数の上限を設定（デフォルト: 4） |
| `--infinite-review` | レビュー数の制限を無効化 |
| `-v, --verbose` | 詳細ログを出力 |
| `-h, --help` | ヘルプを表示 |

## 動作の仕組み

1. **hook-handler.sh**がClaude Codeのstop hookから呼び出される
2. トランスクリプトファイルから最新の作業内容を抽出
3. Geminiでレビューを実行し、結果を`/tmp/gemini-review`に保存
4. **cc-gc-review.sh**が`/tmp/gemini-review`ファイルを監視
5. ファイルの更新を検出したら、tmuxセッションに内容を送信
6. Claudeが自動的にレビュー内容を受け取る

## テスト

```bash
./test.sh
```

## ログ出力

実行中は以下のようなリアルタイムログが表示されます：

```
🔔 New review detected via polling!
📝 Review received (1250 characters)
⚡ Custom command enabled - prepending '/refactor'
🤔 Think mode enabled - appending 'think' command
📤 Sending review to tmux session: claude
✅ Review sent successfully
```

verboseモード（`-v`オプション）を使用すると、さらに詳細なログが表示されます。

## トラブルシューティング

### tmuxセッションが見つからない

```bash
tmux list-sessions  # 既存のセッションを確認
```

### レビューが送信されない

- 一時ディレクトリの権限を確認
- verboseモードで詳細ログを確認: `./cc-gc-review.sh -v claude`
- gemini-cliがインストールされているか確認

### 無限ループの防止

複数の仕組みで無限ループを防止しています：

1. **hook-handler.sh**は`stop_hook_active`フラグをチェックして、既にstop hookが実行中の場合は処理をスキップします。
2. **レビュー数制限**: デフォルトで4回までレビューを実行し、それ以上は自動停止します。
3. **インタラクティブ確認**: 各レビュー後に「続行します」と表示され、10秒以内に「n」を入力すると停止します。
4. **カウントファイル**: `/tmp/cc-gc-review-count`でレビュー数を追跡し、新しいファイル更新時にリセットされます。

#### 無限ループ防止のオプション

- `--max-reviews N`: レビュー数の上限を設定（デフォルト: 4）
- `--infinite-review`: レビュー数の制限を無効化
- レビュー後の確認プロンプト: 10秒以内に「n」で停止、それ以外は継続

## ライセンス

MIT

## 貢献

プルリクエストを歓迎します。大きな変更の場合は、まずissueを開いて変更内容について議論してください。
