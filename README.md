# cc-gc-review

Claude Code と Gemini を stop hook 連携する。
Claude Code での作業完了時に自動的に Gemini がレビューを実行し、結果を Claude Code に直接指示します。

## 概要

このツールは、Claude Codeのstop hookから呼び出され、作業内容をGeminiでレビューし、その結果をClaude Codeに直接表示する自動レビューシステムです。

**注意**: この文書は現在推奨されている`gemini-review-hook.sh`の使用方法を説明しています。tmux連携を使用したフル機能版をお探しの場合は、[レガシー版のドキュメント](deprecated/README-legacy.md)を参照してください。

## 🚀 クイックスタート

### 1. 設定

`~/.claude/settings.json` に以下を追加する：
(既存設定がある場合は /hooks を使った方が無難)

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/cc-gc-review/gemini-review-hook.sh",
            "timeout": 300
          }
        ]
      }
    ]
  }
}
```

**注意**: `/path/to/cc-gc-review/` の部分は、実際にクローンした場所のパスに置き換えてください。

### 2. 必要な環境

- Bash
- jq (必須)
- gemini-cli (必須)
- terminal-notifier (macOS通知用、オプション)
- libnotify-bin (Ubuntu通知用、オプション)

#### 必須ツールのインストール方法

```bash
# jqのインストール
# macOSの場合
brew install jq
# Ubuntuの場合
sudo apt-get install jq
```

#### オプションツールのインストール方法 (通知機能を利用する場合)

```bash
# macOSの場合
brew install terminal-notifier
# Ubuntuの場合
sudo apt-get install libnotify-bin
```

## 機能

### 自動レビュー実行
- 作業完了時にGeminiが自動でコードレビューを実行
- Claude の最後の発言（作業まとめ）をプロンプトに含めることで、より文脈に沿ったレビューを実現

### Rate Limit対応
- Pro版がRate Limitに達した場合、自動的にFlash版にフォールバック
- タイムアウト（120秒）や各種Rate Limitエラーパターンを検出して適切に処理

### 堅牢性とセキュリティ
- **安全な一時ファイル管理**: `mktemp`による予測不可能なファイル名で一時ファイルを作成
- **確実なクリーンアップ**: `trap`コマンドによりスクリプト異常終了時も一時ファイルを削除
- **JSONL形式対応**: Claude Codeのトランスクリプト形式に正確に対応
- **エラーハンドリング**: jqパースエラー、ファイル読み込みエラー等を適切に処理

### レビュー品質向上
- **重複レビュー防止**: Claudeの最後の発言に「REVIEW_COMPLETED」「REVIEW_RATE_LIMITED」が含まれる場合はスキップ
- **Claude Summary の文字数制限**: 1000文字制限でGeminiのトークン制限に対応
- **賢い切り詰め**: 長文要約時は重要部分（先頭・末尾400文字ずつ）を保持、800文字以下は単純切り詰めで重複回避

## 📚 フル機能版（tmux連携）

**使い分けガイド**:
- **シンプル版（上記）**: まずはこちらから試してください。レビュー結果がClaude Codeに直接指示されます
- **フル機能版（以下）**: より高度な連携が必要な場合（tmux経由でのレビュー送信、カスタムコマンド、レビュー数制限など）

レビュー結果をtmux経由でClaude Codeに自動送信したい場合は、以下のフル機能版を使用してください。

### フル機能版の概要

このツールは、Claude Codeのstop hookから呼び出され、作業内容をGeminiでレビューし、その結果をtmuxセッションに自動送信することで、継続的なフィードバックを実現します。

### フル機能版の特徴

- Claude Codeのstop hookからの自動起動
- 作業内容の自動抽出とGeminiレビュー
- tmuxセッションへの自動フィードバック送信
- ファイル監視による非同期処理
- 柔軟なオプション設定
- **セキュリティ強化**: 安全な一時ファイル管理とコマンドインジェクション対策
- **改善されたレビューカウント**: 送信後カウント、リミット到達時パス＆リセット
- **包括的テスト**: 堅牢なテストスイートと自動クリーンアップ

### フル機能版の必要な環境

- Bash
- tmux
- jq
- gemini-cli（オプション、なくても動作可能）
- inotifywait または fswatch（オプション、なければポーリング）
- timeout コマンド（coreutilsの一部、なければ手動タイムアウト処理）
## インストール

```bash
git clone https://github.com/yourusername/cc-gc-review.git
cd cc-gc-review
chmod +x gemini-review-hook.sh
```

## 使い方

### 基本的な使い方

1. 上記のクイックスタートに従って設定を行う
2. Claude Codeで通常通り作業を行う
3. 作業が完了すると自動的にGeminiがレビューを実行
4. レビュー結果がClaude Codeに直接表示される

### Discord通知の設定

Discord通知を有効にする場合：

1. プロジェクトのルートディレクトリに`.env`ファイルを作成
   ```bash
   cp .env.example .env
   ```
   
   **`.env.example`について**: このファイルは設定のテンプレートとして提供されています。必要な環境変数とその説明がコメントとして記載されており、実際の値を入力する際のガイドとして利用できます。
   
2. Discord WebhookのURLを設定：
   ```
   DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
   ```
   
   **⚠️ セキュリティ警告**: `.env`ファイルは機密情報を含むため、Gitにコミットしないでください。このファイルは既に`.gitignore`に追加されています。

3. 作業サマリーの自動抽出について：
   - `CLAUDE_TRANSCRIPT_PATH`環境変数はClaude Codeのhook環境によって自動的に設定されます。
   - ユーザーが手動で設定する必要はありません。
   - `notification.sh`スクリプトは、このパスからClaudeの作業トランスクリプトを読み込み、作業サマリーを抽出するために利用します。

4. 通知のトリガー：
   - `notification.sh`スクリプトは、`gemini-review-hook.sh`から自動的に呼び出されます。
   - したがって、通常はユーザーが手動で実行する必要はありません。
   - ただし、テスト目的などで手動で実行する場合は、以下のようにします。
     ```bash
     ./notification.sh [branch_name]
     ```

通知には以下の情報が含まれます：
- リポジトリ名
- ブランチ名
- 作業サマリー（Claude Codeのトランスクリプトから自動抽出）
- デスクトップ通知（macOS: terminal-notifier、Ubuntu: notify-send）


### 詳細ログの有効化

詳細ログを有効にする場合：

```bash
export CC_GC_REVIEW_VERBOSE="true"
```

## 動作の仕組み

1. **gemini-review-hook.sh**がClaude Codeのstop hookから呼び出される
2. トランスクリプトファイルから最新の作業内容を抽出
3. Geminiでレビューを実行し、結果を安全な一時ファイルに保存
4. レビュー結果をClaude Codeに直接表示

## テスト

テストには`bats`フレームワークを使用しています。

```bash
# テスト環境をセットアップ
./test/setup_test.sh

# 全テストを実行
./test/run_tests.sh

# 特定のテストファイルを実行
./test/run_tests.sh -f test_gemini_review_hook.bats

# 詳細出力付きで実行
./test/run_tests.sh -v
```

テストは安全な一時ディレクトリを使用し、実行後は自動的にクリーンアップされます。

## トラブルシューティング

### レビューが実行されない

- gemini-cliがインストールされているか確認
- 詳細ログを有効にして問題を特定: `export CC_GC_REVIEW_VERBOSE="true"`
- トランスクリプトファイルの権限を確認

### gemini-cliのインストール

```bash
# gemini-cliをインストール
npm install -g gemini-cli
```

### Rate Limit エラー

- Pro版でRate Limitに達した場合、自動的にFlash版にフォールバックされます
- エラーが継続する場合は、時間をおいてから再試行してください