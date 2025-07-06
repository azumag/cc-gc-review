# cc-gc-review

Claude CodeとGeminiをstop hook連携させるサポートツール

## 概要

このツールは、Claude Codeのstop hookから呼び出され、作業内容をGeminiでレビューし、その結果をClaude Codeに直接表示する自動レビューシステムです。

**注意**: この文書は現在推奨されている`gemini-review-hook.sh`の使用方法を説明しています。tmux連携を使用したフル機能版をお探しの場合は、[レガシー版のドキュメント](deprecated/README-legacy.md)を参照してください。

## 🚀 クイックスタート

### 1. 設定

`~/.claude/settings.json` に以下を追加する：

```json
{
  "hooks": {
    "stop": "/path/to/cc-gc-review/gemini-review-hook.sh"
  }
}
```

**注意**: `/path/to/cc-gc-review/` の部分は、実際にクローンした場所のパスに置き換えてください。


### 2. 必要な環境

- Bash
- jq
- gemini-cli

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