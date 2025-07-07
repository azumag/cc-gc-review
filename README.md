# cc-gc-review

Claude Code と Gemini を stop hook 連携する。
Claude Code での作業完了時に自動的に Gemini がレビューを実行し、結果を Claude Code に直接指示します。

## 概要

このツールは、Claude Codeのstop hookから呼び出され、作業内容をGeminiでレビューし、その結果をClaude Codeに直接表示する自動レビューシステムです。

**注意**: この文書は現在推奨されている`gemini-review-hook.sh`の使用方法を説明しています。

## ✨ 最新の改善点 (2025年7月更新)

### 🛡️ セキュリティ・品質向上
- **ShellCheck完全対応**: 全スクリプトがShellCheckの静的解析をパス、コーディングベストプラクティスに準拠
- **セキュアな一時ファイル管理**: `/tmp`への直接書き込みを廃止、`mktemp -d`による安全な一時ディレクトリを使用
- **改善されたエラーハンドリング**: より堅牢なエラー処理とリソース管理

### 🔍 CI監視機能の強化
- **包括的ワークフロー監視**: 最新1件ではなく、全アクティブワークフローの状態を監視
- **正確な成功判定**: 全てのワークフローが完了し、いずれも失敗していない場合のみ成功と判定
- **詳細なエラー報告**: 失敗したワークフローの具体的な情報とアクションガイドを提供

### 🧪 堅牢なテスト環境
- **多環境テスト**: Node.js 18/20/22、bash/dash、高負荷/低負荷条件での検証
- **日次品質チェック**: スケジュール実行による環境ドリフトの早期発見
- **セキュリティテスト**: コマンドインジェクション脆弱性の自動検証
- **パフォーマンス監視**: レビュー品質とレスポンス時間の継続的な測定

### 📊 品質保証の自動化
- **レビュー品質メトリクス**: 文字数、具体的参照数、改善提案数の自動測定
- **一貫したカウント手法**: 本番環境とCI環境での動作一致を保証
- **継続的改善**: 品質閾値の動的調整と改善点の追跡

**プロジェクト構造について**: フックスクリプトは `./hooks` ディレクトリに整理されており、以下のファイルが含まれています：
- `gemini-review-hook.sh` - Claude Code作業完了時にGeminiでレビューを実行し結果を表示するメインフック
- `self-review.sh` - SubAgentによる厳格なコードレビューを実行し、必要に応じて修正を行うスクリプト
- `notification.sh` - Claude Code作業完了時にDiscordへ通知メッセージを送信するスクリプト
- `push-review-complete.sh` - レビュー完了後に未コミット変更を自動的にコミット・プッシュするスクリプト
- `ci-monitor-hook.sh` - プッシュ後にGitHub Actions CIの状態を**包括的に**監視し、CI失敗時に詳細な通知を提供するスクリプト
- `shared-utils.sh` - トランスクリプト解析、ログ機能などの共通機能を提供するユーティリティライブラリ

**tmux連携機能について**: 以前提供していたtmux連携機能は、設定の複雑さとメンテナンスコストを考慮し、現在は非推奨となっています。シンプルで安定した動作を重視し、Claude Codeの標準的なhook機能のみを使用する現在の方式を推奨します。tmux連携が必要な場合（例：tmuxセッション内でのインタラクティブな操作や、複数セッション間での結果共有が必須の場合）は、[レガシー版のドキュメント](deprecated/README-legacy.md)を参照してください。

## 📋 既存ユーザー向け移行手順

既にこのプロジェクトを使用している場合、以下の手順でスクリプトの新しい構造に移行してください：

1. **リポジトリの更新**
   ```bash
   git pull origin main
   git rm gemini-review-hook.sh notification.sh push-review-complete.sh shared-utils.sh
   git add hooks/
   git commit -m "migrate: Move scripts to hooks directory and update documentation"
   ```

2. **Claude Code設定の更新**
   `~/.claude/settings.json` のパスを更新：
   ```json
   {
     "hooks": {
       "Stop": [
         {
           "command": "/絶対パス/to/cc-gc-review/hooks/gemini-review-hook.sh"
         }
       ]
     }
   }
   ```

3. **Discord通知設定の更新**（使用している場合）
   ```json
   {
     "hooks": {
       "Stop": [
         {
           "command": "/絶対パス/to/cc-gc-review/hooks/notification.sh"
         }
       ]
     }
   }
   ```

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
            "command": "/path/to/cc-gc-review/hooks/gemini-review-hook.sh",
            "timeout": 300
          }
        ]
      }
    ]
  }
}
```

**注意**: `/path/to/cc-gc-review/hooks/gemini-review-hook.sh` の部分は、`cc-gc-review` リポジトリのルートディレクトリへの絶対パスに `hooks/gemini-review-hook.sh` を追加したパスに置き換えてください。例：`/Users/username/cc-gc-review/hooks/gemini-review-hook.sh`

### 2. 必要な環境

- Bash
- jq
- Node.js (gemini-cli のインストールに必要)
- gemini-cli

#### インストール方法

**jq (JSONパーサー)**
```bash
# macOSの場合
brew install jq
# Ubuntuの場合
sudo apt-get install jq
```

**gemini-cli (Gemini AI CLI)**
```bash
# 事前にNode.jsがインストールされている必要があります
# Node.jsのインストール方法については、公式ドキュメント（https://nodejs.org/）を参照してください
npm install -g gemini-cli
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
- **要約の切り詰めアルゴリズム**: 1000文字を超える要約は切り詰められます。800文字を超える場合は先頭400文字と末尾400文字を保持し、801文字から1000文字の場合は先頭1000文字を保持します。

## オプショナルツール

### notification.sh - Discord通知スクリプト

作業完了時にDiscordへ通知を送信するオプショナルなスクリプトです。`notification.sh`は`gemini-review-hook.sh`とは独立した機能であり、個別に設定が必要です。

#### 機能

- **スマートなタイトル抽出**: 詳細は[通知内容](#通知内容)セクションを参照
- **リトライ機能とエラーハンドリング**: 通知送信失敗時に自動リトライし、hookチェーンを中断せずにエラーログを出力します。詳細は[通知内容](#通知内容)セクションを参照

#### 必要な環境

- terminal-notifier (macOS通知用、オプション)
- libnotify-bin (Ubuntu通知用、オプション)

**注意**: お使いのOSに合わせていずれか一方をインストールしてください。

```bash
# macOSの場合
brew install terminal-notifier

# Ubuntuの場合
sudo apt-get install libnotify-bin
```

#### Discord通知の設定

**重要**: `notification.sh`は`gemini-review-hook.sh`とは別に、Claude CodeのStop hookに設定する必要があります。

1. Claude CodeのStop hookに`notification.sh`を設定
   ```json
   {
     "hooks": {
       "Stop": [
         {
           "matcher": "",
           "hooks": [
             {
               "type": "command",
               "command": "/path/to/cc-gc-review/hooks/notification.sh",
               "timeout": 60  // ネットワーク遅延やDiscord APIの一時的な問題に対応するため増加
             }
           ]
         }
       ]
     }
   }
   ```
   
   **注意**: 
   - `/path/to/cc-gc-review/hooks/notification.sh`の部分は、`cc-gc-review` リポジトリのルートディレクトリへの絶対パスに `hooks/notification.sh` を追加したパスに置き換えてください。例：`/Users/username/cc-gc-review/hooks/notification.sh`
   - `matcher`は条件マッチング用（空文字列は全ての場合にマッチ）

2. プロジェクトのルートディレクトリに`.env`ファイルを作成
   ```bash
   cp .env.example .env
   ```
   
   `.env.example`を参考に必要な環境変数を設定してください。このファイルは設定のテンプレートとして提供されており、必要な環境変数とその説明がコメントとして記載されています。
   
3. Discord WebhookのURLを設定：
   ```
   DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
   ```
   
   **⚠️ セキュリティ警告**: `.env`ファイルは機密情報を含むため、Gitにコミットしないでください。このファイルは既に`.gitignore`に追加されています。

#### 通知の動作

- `notification.sh`は`gemini-review-hook.sh`とは完全に独立したスクリプトです
- Claude CodeのStop hookに設定することで、作業完了時に自動実行されます
- `gemini-review-hook.sh`からは呼び出されません - 別々のhookとして動作します
- `CLAUDE_TRANSCRIPT_PATH`は自動的に設定され、`notification.sh`がClaudeの作業トランスクリプトからサマリーを抽出します
- 手動実行する場合：
  ```bash
  /absolute/path/to/cc-gc-review/hooks/notification.sh [branch_name]
  ```

#### 通知内容

通知には以下の情報が含まれます：
- **タイトル**: 作業サマリーの最後の行から自動抽出（短く意味のある内容）
- **リポジトリ名**: 作業中のGitリポジトリ名
- **ブランチ名**: 現在のGitブランチ
- **作業サマリー**: Claude Codeのトランスクリプトから自動抽出（完全な内容）
- **デスクトップ通知**: タイトルと基本情報のみの簡潔な通知

Discord通知の例：
```
🎉 **Enhanced timeout settings** 🎉

Repository: cc-gc-review
Branch: fix/ci-error
Work Summary: Work Summary: Fixed Discord notification issues

1. Added retry logic for failed notifications
2. Improved error handling and logging
3. Fixed hook chain continuation
4. Enhanced timeout settings
```


### push-review-complete.sh - 自動コミット・プッシュスクリプト

Geminiのレビューで改善点がない場合（`REVIEW_COMPLETED`）に、未コミットの変更を自動的にコミットしてプッシュするスクリプトです。このスクリプトは、`gemini-review-hook.sh` が正常に完了し、かつレビュー結果が `REVIEW_COMPLETED` であった場合にのみ実行されることを想定しています。CIワークフローの最終段階で使用されます。

**注意**: このスクリプトは自動的にコミット・プッシュを行うため、意図しない変更が含まれていないか事前に確認することを推奨します。また、`gemini-review-hook.sh` との実行順序に依存関係があるため、hookの設定には注意が必要です。

### ci-monitor-hook.sh - CI監視フック（オプション）

プッシュ後にGitHub Actions CIの状態を監視し、CI失敗時にユーザーに通知するオプショナルなスクリプトです。

**前提条件**: このスクリプトは`push-review-complete.sh`が実行され、`REVIEW_COMPLETED && PUSH_COMPLETED`のマークが付いた作業のみを対象とします。単独では機能しません。

**注意**: この機能はオプションです。CI監視により処理時間が最大5分延長されるため、必要性を慎重に検討してください。

#### 機能

- **包括的ワークフロー監視**: 最新1件ではなく、ブランチの全アクティブワークフローを同時監視
- **正確な成功判定**: 全てのワークフローが完了し、かつ全てが成功した場合のみ成功と判定
- **詳細な失敗通知**: 失敗したワークフローの詳細（名前、ステータス、URL）を提供
- **決定ブロック**: CI失敗時に`decision: block`を返し、具体的な修正アクションガイドを提供
- **タイムアウト処理**: 最大5分間の監視後、自動的に終了
- **堅牢なエラー処理**: ネットワークエラー、認証エラー、APIレート制限に対する適切な処理
- **セキュアなログ管理**: 安全な一時ディレクトリを使用したログ出力

#### 必要な環境

- GitHub CLI (gh) - GitHub APIアクセス用
- git - リポジトリ情報の取得用
- GitHub認証 - `gh auth login`で認証済みである必要がある

#### 使用場面

このフックは以下の場合に有用です：
- CI/CDパイプラインが重要なプロジェクト
- CIの成功/失敗を即座に知りたい場合
- チーム開発でのCI状態共有が必要な場合

#### フック設定

**実用的な設定は[複数のhookを同時に使用する場合](#複数のhookを同時に使用する場合)セクションの推奨構成を参照してください。**

**注意**: 
- CI監視フックはネットワーク通信を伴うため、他のローカルで完結するフックと比較して処理時間が大幅に長くなる傾向があります
- タイムアウト値は最大監視時間（300秒）より長めに設定することを推奨

#### 決定ブロック動作

CI失敗時、以下の形式で詳細情報を提供します：

```
## CI Check Failed

**Workflow:** テスト名
**Status:** failure
**URL:** https://github.com/user/repo/actions/runs/123456

The GitHub Actions CI check has failed. Please review the failure details and fix any issues before continuing.

### Next Steps:
1. Click the URL above to view the detailed failure logs
2. Fix the identified issues in your code
3. Commit and push the fixes
4. The CI will automatically re-run

Would you like me to help analyze and fix the CI failures?
```

### 複数のhookを同時に使用する場合

#### 構成選択の判断基準

- **基本構成**: 通常の開発ワークフロー（推奨）
- **CI監視付き構成**: CI/CDが重要で即座のフィードバックが必要な場合

#### 推奨構成

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "afplay /System/Library/Sounds/Funk.aiff"  // macOS: 作業完了の音声通知（オプション）
          },
          {
            "type": "command",
            "command": "/path/to/cc-gc-review/hooks/gemini-review-hook.sh",
            "timeout": 300
          },
          {
            "type": "command",
            "command": "/path/to/cc-gc-review/hooks/push-review-complete.sh"
          },
          // CI監視が必要な場合のみ以下をコメントアウト
          // {
          //   "type": "command",
          //   "command": "/path/to/cc-gc-review/hooks/ci-monitor-hook.sh",
          //   "timeout": 360
          // },
          {
            "type": "command",
            "command": "/path/to/cc-gc-review/hooks/notification.sh",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

#### 依存関係と実行タイミング

- **`ci-monitor-hook.sh`の依存関係**: `push-review-complete.sh`の完了が前提条件
- **実行時間**: CI監視フックのタイムアウト値が360秒であるため、処理は最大で360秒（6分）延長される可能性があります
- **並列実行の注意**: hooksは並列実行されるため、依存関係のあるCI監視フックは適切なタイミング制御が重要

#### 設定時の注意事項

- hookは**並列実行**されます（順番に実行されるわけではありません）
- 各hookは独立して動作し、前のhookの失敗は次のhookの実行を妨げません
- `timeout`は各hookごとに設定可能です（デフォルト60秒）
- いずれかのhookがタイムアウトした場合、実行中の全てのhookがキャンセルされます

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

### 基本テスト

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

### 🧪 堅牢な検証テスト

プロジェクトには包括的な品質保証のための追加テストが含まれています：

```bash
# 多環境での包括的テスト（CI環境で自動実行）
./test/comprehensive_validation.sh

# リアルタイム品質評価テスト
cd test && bats test_quality_assessment_fix.bats

# セキュリティ検証
./scripts/validate-scripts.sh
```

#### 自動CI検証

- **マルチ環境テスト**: Node.js 18/20/22、bash/dash環境での検証
- **負荷テスト**: 高負荷条件でのパフォーマンステスト
- **セキュリティテスト**: コマンドインジェクション脆弱性の検証
- **日次検証**: スケジュール実行による環境ドリフトの監視

#### 品質メトリクス

以下の品質閾値が自動的に監視されています：
- **レビュー文字数**: 200文字以上
- **具体的参照**: 2回以上（line、function、メソッド、行）
- **改善提案**: 2回以上（改善、実装、追加、見直し）

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

## 📈 バージョン情報

### v2.0.0 (2025年7月) - 品質・セキュリティ強化版
- **セキュリティ**: ShellCheck完全対応、安全な一時ファイル管理
- **CI監視**: 包括的ワークフロー監視による正確な成功判定
- **テスト**: 多環境・負荷・セキュリティの包括的検証
- **品質**: 自動品質メトリクス監視と継続的改善

### 互換性
- Claude Code: 最新版で動作確認済み
- Shell: Bash 4.0+ (macOS/Linux)
- Node.js: 18/20/22で検証済み
- OS: macOS、Ubuntu/Debian Linux

---
**🔗 関連リンク**
- [変更履歴とCI修正の詳細](CI_QUALITY_ASSESSMENT_FIX.md)
- [レガシー版ドキュメント](deprecated/README-legacy.md)
- [開発者向けドキュメント](docs/)