# cc-gc-review - Legacy tmux-based Documentation

## 📚 フル機能版（tmux連携）

**使い分けガイド**:
- **シンプル版**: まずはgemini-review-hook.shを試してください。レビュー結果がClaude Codeに直接表示されます
- **フル機能版（以下）**: より高度な連携が必要な場合（tmux経由でのレビュー送信、カスタムコマンド、レビュー数制限など）

レビュー結果をtmux経由でClaude Codeに自動送信したい場合は、以下のフル機能版を使用してください。

## 概要

このツールは、Claude Codeのstop hookから呼び出され、作業内容をGeminiでレビューし、その結果をtmuxセッションに自動送信することで、継続的なフィードバックを実現します。

## 機能

- Claude Codeのstop hookからの自動起動
- 作業内容の自動抽出とGeminiレビュー
- tmuxセッションへの自動フィードバック送信
- ファイル監視による非同期処理
- 柔軟なオプション設定
- **セキュリティ強化**: 安全な一時ファイル管理とコマンドインジェクション対策
- **改善されたレビューカウント**: 送信後カウント、リミット到達時パス＆リセット
- **包括的テスト**: 堅牢なテストスイートと自動クリーンアップ

## 必要な環境

- Bash
- tmux
- jq
- gemini-cli（オプション、なくても動作可能）
- inotifywait または fswatch（オプション、なければポーリング）
- timeout コマンド（coreutilsの一部、なければ手動タイムアウト処理）

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

レビューファイルは安全な一時ディレクトリに出力されます（環境変数`CC_GC_REVIEW_WATCH_FILE`で指定、なければデフォルトの`/tmp/gemini-review`）。

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
3. Geminiでレビューを実行し、結果を安全な一時ファイルに保存
4. **cc-gc-review.sh**がレビューファイルを監視（inotify/fswatch/polling）
5. ファイルの更新を検出したら、tmuxセッションに内容を送信
6. **レビューカウント管理**: 送信後にカウント+1、リミット到達時は次回をパス＆リセット
7. Claudeが自動的にレビュー内容を受け取る

## ログ出力

実行中は以下のようなリアルタイムログが表示されます：

```
🔔 New review detected via polling!
📝 Review received (1250 characters)
⚡ Custom command enabled - prepending '/refactor'
🤔 Think mode enabled - appending 'think' command
📤 Sending review to tmux session: claude
✅ Review sent successfully
📊 Review count: 2/4
⚠️  Review limit will be reached. Next review will be passed and count will be reset.
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

### レビューカウント管理と無限ループ防止

新しいレビューカウント仕様により、効率的で予測可能な動作を実現：

#### レビューカウントの動作
1. **送信時カウント**: tmux送信後にカウント+1
2. **リミット到達時**: 次回レビューをパス（送信しない）
3. **自動リセット**: パス時にカウントを0にリセット
4. **継続動作**: リセット後は通常通りレビューを再開

#### 無限ループ防止機能
1. **hook-handler.sh**は`stop_hook_active`フラグをチェック
2. **レビュー数制限**: デフォルトで4回までレビューを実行
3. **インタラクティブ確認**: 各レビュー後に10秒タイムアウト付き確認
4. **セキュアなカウント管理**: アトミックファイル操作で競合状態を回避

#### オプション
- `--max-reviews N`: レビュー数の上限を設定（デフォルト: 4）
- `--infinite-review`: レビュー数の制限を無効化
- レビュー後の確認プロンプト: 10秒以内に「n」で停止、それ以外は継続

#### セキュリティ機能
- **安全な一時ファイル**: `mktemp`による予測不可能なファイル名
- **コマンドインジェクション対策**: カスタムコマンドの入力検証
- **アトミック操作**: ファイル競合状態の回避