---
title: "Claude CodeとGeminiを連携させて自動コードレビューを実現する"
emoji: "🤖"
type: "tech"
topics: ["claude", "gemini", "bash", "tmux", "automation"]
published: false
---

# はじめに

プログラミング中に「今書いたコード、第三者の視点でレビューしてもらいたい」と思うことはありませんか？Claude Codeでコーディングしていると、作業が一段落したタイミングで別のAIの意見も聞きたくなることがあります。

この記事では、Claude Codeの作業終了時に自動的にGeminiでコードレビューを実行し、その結果をClaude Codeに戻すツール「cc-gen-review」を紹介します。

# 何ができるのか

cc-gen-reviewは以下のような流れで動作します：

1. Claude Codeで作業を行う
2. 作業が終了すると、stop hookが発動
3. 作業内容を自動的にGeminiに送信してレビュー
4. レビュー結果をtmux経由でClaude Codeに自動送信
5. Claude Codeがレビューを受けて追加の改善を実施

![flow](https://example.com/flow.png)

# 仕組み

## Claude Codeのhooks機能

Claude Codeには、特定のイベント時にカスタムスクリプトを実行できるhooks機能があります。今回は`stop hook`を使用して、作業終了時に自動的にレビュープロセスを開始します。

```json
{
  "hooks": {
    "stop": "/path/to/hook-handler.sh"
  }
}
```

## アーキテクチャ

システムは3つのコンポーネントで構成されています：

1. **hook-handler.sh**: Claude Codeから呼び出されるハンドラー
2. **cc-gen-review.sh**: ファイル監視とtmux制御を行うメインプロセス
3. **tmux**: Claude CodeとGeminiレビュー結果の橋渡し

```
Claude Code
    ↓ (stop hook)
hook-handler.sh
    ↓ (作業内容抽出)
Gemini API
    ↓ (レビュー結果をファイルに保存)
cc-gen-review.sh (ファイル監視)
    ↓ (tmux send-keys)
Claude Code (レビュー受信)
```

# 実装の詳細

## 1. hook-handler.sh

Claude Codeのstop hookから呼び出されるスクリプトです。

```bash
#!/bin/bash

# 標準入力からJSONを読み取る
input=$(cat)

# JSONパース
transcript_path=$(echo "$input" | jq -r '.transcript_path')
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active')

# 無限ループ防止
if [[ "$stop_hook_active" == "true" ]]; then
    exit 0
fi

# 最後のassistantメッセージを抽出
summary=$(jq -r 'select(.type == "assistant")' "$transcript_path" | \
         jq -sr '.[-1].message.content[-1].text')

# Geminiでレビュー
review_result=$(echo "$summary" | gemini -p "作業内容をレビューしてください")

# レビュー結果を一時ファイルに保存
echo "$review_result" > "/tmp/gemini-review"
```

## 2. cc-gen-review.sh

ファイル監視とtmuxセッション管理を行うメインスクリプトです。

```bash
#!/bin/bash

# tmuxセッション作成
setup_tmux_session() {
    local session="$1"
    
    if ! tmux has-session -t "$session" 2>/dev/null; then
        tmux new-session -d -s "$session"
        
        if [[ "$AUTO_CLAUDE_LAUNCH" == true ]]; then
            tmux send-keys -t "$session" "claude" Enter
        fi
    fi
}

# ファイル監視（ポーリング版）
watch_with_polling() {
    local session="$1"
    local watch_file="$2"
    local last_mtime="0"
    
    while true; do
        if [[ -f "$watch_file" ]]; then
            current_mtime=$(stat -f %m "$watch_file" 2>/dev/null)
            
            if [[ "$current_mtime" != "$last_mtime" ]]; then
                last_mtime="$current_mtime"
                content=$(cat "$watch_file")
                
                if [[ -n "$content" ]]; then
                    # レビュー内容をtmuxに送信
                    tmux send-keys -t "$session" "$content" Enter
                    sleep 5
                    tmux send-keys -t "$session" "" Enter
                fi
            fi
        fi
        sleep 2
    done
}
```

## 3. tmuxによる連携

tmuxを使用することで、Claude Codeのセッションに外部からテキストを送信できます。

```bash
# セッションにアタッチ
tmux attach-session -t claude

# 外部からテキスト送信
tmux send-keys -t claude "レビュー内容" Enter
```

# インストールと使い方

## 1. インストール

```bash
git clone https://github.com/yourusername/cc-gen-review.git
cd cc-gen-review
chmod +x *.sh
```

## 2. Claude Codeの設定

`~/.claude/settings.json`に以下を追加：

```json
{
  "hooks": {
    "stop": "/path/to/cc-gen-review/hook-handler.sh"
  }
}
```

**重要**: hook-handlerはcc-gen-reviewが設定した環境変数を使用するため、cc-gen-reviewを起動してからClaude Codeを使用してください。

## 3. 起動

```bash
# 基本的な使い方
./cc-gen-review.sh claude

# Claudeも自動起動
./cc-gen-review.sh -c claude

# thinkモードを有効化（レビュー後に深い思考を促す）
./cc-gen-review.sh --think claude
```

起動すると以下のような表示が出ます：

```
=== cc-gen-review starting ===
Session name: claude
Tmp directory: ./tmp
Think mode: true
Auto-launch Claude: true
=============================

✓ tmux session 'claude' is ready
✓ Watching for review file: ./tmp/gemini-review

To attach to the session, run:
  tmux attach-session -t claude

Press Ctrl+C to stop watching...
```

## 4. 使用例

手順：

1. cc-gen-reviewを起動（環境変数を設定）：
```bash
./cc-gen-review.sh --tmp-dir /tmp/reviews -c claude
```

2. 別ターミナルでtmuxセッションにアタッチ：
```bash
tmux attach-session -t claude
```

3. Claude Codeで作業を行い、終了すると自動的にレビューが実行されます。

# 技術的な工夫点

## 1. 無限ループの防止

stop hookから新たな入力があると、それがまたstop hookを発動させる可能性があります。これを防ぐため、`stop_hook_active`フラグをチェックしています。

```bash
if [[ "$stop_hook_active" == "true" ]]; then
    exit 0
fi
```

## 2. 複数のファイル監視方式

環境によって使える監視ツールが異なるため、3つの方式を実装しています：

1. **inotifywait** (Linux)
2. **fswatch** (macOS)
3. **ポーリング** (フォールバック)

```bash
if command -v inotifywait >/dev/null 2>&1; then
    watch_with_inotify "$session" "$watch_pattern"
elif command -v fswatch >/dev/null 2>&1; then
    watch_with_fswatch "$session" "$watch_pattern"
else
    watch_with_polling "$session" "$watch_pattern"
fi
```

## 3. macOS互換性

macOSの古いbashでは連想配列がサポートされていないため、文字列結合で処理済みファイルを追跡しています。

```bash
# 連想配列の代わりに文字列結合を使用
if [[ ! "$processed_files" =~ "$file_key" ]]; then
    processed_files="${processed_files}${file_key}|"
fi
```

# カスタマイズ

## 環境変数による設定

```bash
export CC_GEN_REVIEW_TMP_DIR="/tmp/reviews"
export CC_GEN_REVIEW_VERBOSE="true"
```

## レビュープロンプトのカスタマイズ

`hook-handler.sh`内のプロンプトを変更することで、レビューの観点を調整できます：

```bash
local prompt="以下の作業内容をレビューして、改善点や注意点があれば日本語で簡潔に指摘してください。良い点も含めてフィードバックをお願いします。

作業内容:
$summary

レビュー結果:"
```

# トラブルシューティング

## tmuxセッションが見つからない

```bash
tmux list-sessions  # 既存のセッションを確認
```

## レビューが送信されない

- 一時ディレクトリの権限を確認
- verboseモードで詳細ログを確認: `./cc-gen-review.sh -v claude`
- gemini-cliがインストールされているか確認

## "open terminal failed: not a terminal"エラー

このエラーは非対話型環境で実行した場合に発生します。別ターミナルでtmuxにアタッチしてください。

# まとめ

cc-gen-reviewを使うことで、Claude Codeでの開発中に自動的にGeminiのレビューを受けることができます。異なるAIの視点を取り入れることで、コード品質の向上が期待できます。

また、このツールは他のAIツールとの連携にも応用できます。例えば：

- 別のレビューツールとの連携
- テスト実行結果の自動フィードバック
- セキュリティチェックツールとの統合

皆さんもぜひ、AIツール同士を連携させて、より効率的な開発環境を構築してみてください！

# リポジトリ

https://github.com/azumag/cc-gc-review

# 参考資料

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [tmux manual](https://man7.org/linux/man-pages/man1/tmux.1.html)
- [jq manual](https://stedolan.github.io/jq/manual/)