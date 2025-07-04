# cc-gen-review

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
git clone https://github.com/yourusername/cc-gen-review.git
cd cc-gen-review
chmod +x *.sh
```

## 使い方

### 1. メインプロセスの起動

```bash
# 基本的な使い方
./cc-gen-review.sh claude

# 自動でClaudeも起動
./cc-gen-review.sh -c claude

# thinkモードを有効化
./cc-gen-review.sh --think claude

# 詳細ログを表示
./cc-gen-review.sh -v claude

# オプション組み合わせ
./cc-gen-review.sh --think -c -v claude
```

起動後、別のターミナルで以下を実行してセッションにアタッチ：
```bash
tmux attach-session -t claude
```

### 2. Claude Codeのhooks設定

`~/.claude/settings.json`に以下を追加：

```json
{
  "hooks": {
    "stop": "/path/to/cc-gen-review/hook-handler.sh"
  }
}
```

レビューファイルは固定で`/tmp/gemini-review`に出力されます。

詳細ログを有効にする場合：

```bash
export CC_GEN_REVIEW_VERBOSE="true"
```

## オプション

| オプション | 説明 |
|-----------|------|
| `-c, --auto-claude-launch` | 自動でClaudeを起動 |
| `--think` | レビュー内容の後に'think'を追加 |
| `-v, --verbose` | 詳細ログを出力 |
| `-h, --help` | ヘルプを表示 |

## 動作の仕組み

1. **hook-handler.sh**がClaude Codeのstop hookから呼び出される
2. トランスクリプトファイルから最新の作業内容を抽出
3. Geminiでレビューを実行し、結果を`/tmp/gemini-review`に保存
4. **cc-gen-review.sh**が`/tmp/gemini-review`ファイルを監視
5. ファイルの更新を検出したら、tmuxセッションに内容を送信
6. Claudeが自動的にレビュー内容を受け取る

## テスト

```bash
./test.sh
```

## トラブルシューティング

### tmuxセッションが見つからない

```bash
tmux list-sessions  # 既存のセッションを確認
```

### レビューが送信されない

- 一時ディレクトリの権限を確認
- verboseモードで詳細ログを確認
- gemini-cliがインストールされているか確認

### 無限ループの防止

hook-handler.shは`stop_hook_active`フラグをチェックして、既にstop hookが実行中の場合は処理をスキップします。

## ライセンス

MIT

## 貢献

プルリクエストを歓迎します。大きな変更の場合は、まずissueを開いて変更内容について議論してください。
