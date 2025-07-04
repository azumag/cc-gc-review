# Shell Script Testing with Bats

このディレクトリには、cc-gen-reviewプロジェクトのシェルスクリプトに対するテストスイートが含まれています。

## 概要

- **テストフレームワーク**: [Bats (Bash Automated Testing System)](https://github.com/bats-core/bats-core)
- **テストアプローチ**: TDD (Test-Driven Development) に基づいたテスト設計
- **対象スクリプト**: `cc-gen-review.sh`, `hook-handler.sh`

## セットアップ

### 必要な依存関係

- `bats-core` - テストフレームワーク
- `tmux` - セッション管理のテスト用
- `jq` - JSON処理のテスト用
- `timeout` - タイムアウト制御用

### インストール

```bash
# 自動インストール
./install_bats.sh

# または手動インストール
./setup_test.sh
```

### macOSでのインストール

```bash
brew install bats-core tmux jq coreutils
```

### Ubuntuでのインストール

```bash
sudo apt-get install bats tmux jq coreutils
```

## テストファイル

### `test_cc_gen_review.bats`

`cc-gen-review.sh` の包括的なテストスイート：

- コマンドライン引数の処理
- ヘルプ表示機能
- tmuxセッション管理
- ファイル監視機能
- オプション機能（think mode, custom command, etc.）

### `test_hook_handler.bats`

`hook-handler.sh` の包括的なテストスイート：

- JSON入力の処理
- トランスクリプトファイルの解析
- Geminiレビューの実行
- エラーハンドリング
- セキュリティチェック

## テストの実行

### 全テスト実行

```bash
# 基本実行
./run_tests.sh

# 詳細出力
./run_tests.sh --verbose

# 並列実行
./run_tests.sh --parallel
```

### 特定のテストファイル実行

```bash
# cc-gen-reviewのテストのみ
./run_tests.sh --file test_cc_gen_review.bats

# hook-handlerのテストのみ
./run_tests.sh --file test_hook_handler.bats
```

### 特定のテストケース実行

```bash
# パターンマッチでテスト選択
./run_tests.sh --test "help.*display"
./run_tests.sh --test "should fail when"
```

### 直接batsコマンドで実行

```bash
# 個別ファイル実行
bats test_cc_gen_review.bats
bats test_hook_handler.bats

# 全テスト実行
bats test_*.bats

# 詳細出力
bats --verbose-run test_*.bats
```

## CI/CD統合

### GitHub Actions

`.github/workflows/test.yml` で以下のテストが自動実行されます：

- **test**: 機能テスト（Ubuntu環境）
- **lint**: ShellCheckによる静的解析
- **security**: セキュリティチェック
- **compatibility**: 複数OS（Ubuntu, macOS）での互換性テスト

### Pre-commit Hooks

`.pre-commit-config.yaml` で以下のチェックが実行されます：

- ShellCheck による静的解析
- shfmt による コードフォーマット
- セキュリティチェック
- テスト実行

## TDD アプローチ

このテストスイートは以下のTDDプリンシパルに従って設計されています：

### 1. レッド・グリーン・リファクタサイクル

```bash
# 1. 失敗するテストを書く（Red）
@test "new feature should work" {
    run my_script --new-feature
    [ "$status" -eq 0 ]
}

# 2. 最小限の実装で通す（Green）
# スクリプトに機能を追加

# 3. リファクタリング（Refactor）
# コードを改善しながらテストが通ることを確認
```

### 2. テストケースの設計

- **境界値テスト**: 空文字列、最大値、最小値
- **エラーケース**: 不正な入力、ファイルが存在しない場合
- **正常ケース**: 典型的な使用シナリオ
- **統合テスト**: 複数の機能が連携する場合

### 3. テストデータの管理

```bash
setup() {
    # 各テスト前に実行
    export TEST_SESSION="test-$$"
    mkdir -p "./test-tmp-$$"
}

teardown() {
    # 各テスト後に実行
    rm -rf "./test-tmp-$$"
    tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
}
```

## ベストプラクティス

### テストの命名規則

```bash
# Good: 期待する動作を明確に記述
@test "should display help when -h option is provided"

# Bad: 実装詳細に依存
@test "test help flag"
```

### テストの独立性

```bash
# Good: 各テストは独立している
@test "should create new tmux session" {
    run "$SCRIPT_DIR/cc-gen-review.sh" "$TEST_SESSION"
    [ "$status" -eq 0 ]
}

# Bad: 他のテストに依存
@test "should use existing session created by previous test" {
    # 前のテストに依存している
}
```

### モッキングとスタブ

```bash
# 外部依存をモック
setup() {
    # geminiコマンドをモック
    echo '#!/bin/bash
    echo "Mocked gemini response"' > "$TEST_TMP_DIR/gemini"
    chmod +x "$TEST_TMP_DIR/gemini"
    export PATH="$TEST_TMP_DIR:$PATH"
}
```

## トラブルシューティング

### 一般的な問題

1. **tmuxセッションが残る**
   ```bash
   tmux kill-server  # 全セッションを終了
   ```

2. **一時ファイルが残る**
   ```bash
   rm -rf ./test-tmp-*
   rm -f /tmp/gemini-review*
   ```

3. **権限エラー**
   ```bash
   chmod +x *.sh test/*.sh
   ```

### デバッグ方法

```bash
# 詳細出力でテスト実行
./run_tests.sh --verbose

# 特定のテストのみ実行
./run_tests.sh --test "failing_test_name"

# batsデバッグモード
bats --verbose-run --trace test_file.bats
```

## 参考リンク

- [Bats Core Documentation](https://bats-core.readthedocs.io/)
- [Bats Tutorial](https://github.com/bats-core/bats-core#tutorial)
- [ShellCheck](https://www.shellcheck.net/)
- [Test-Driven Development](https://en.wikipedia.org/wiki/Test-driven_development)