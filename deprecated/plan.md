# overview
Claude Code と gemini を stop hook 連携させるサポートツール

# 想定
- Claude Code の hooks でツールを呼び出す
- ツールは受け取った JSON の transcript_path から取得した会話ログを分解し、作業サマリーを取得し、レビュー依頼を gemini に依頼し、結果を一時ファイルに書き出す
- 本ツールはそのファイルを監視し、内容を tmux で claude に渡して結果を伝達する

# 前提制約
- hooks によっていったんプロンプトやりとりは終わっているので、claude への通信方法は tmux による key 送信しかなさそう
- Stop hooks に gemini -p を仕込んでも、返答をただ得るだけで、Claude 側処理は終わってるので特に何もできない
- gemini に tmux sendkey を頼んでも、実行したりしなかったりして確度が低いので、hooksの意味がない
- local test, pre-commit, ci どれも絶対実行
- send-keys で送信しても、そのあと enter が押されないので、明示的に少し待ってから再度送信する必要がある

# 仕様
- 引数で session 名をうけとる
- session が指定されている場合は、 session が立ち上がってなければ立ち上げ
- --auto-attach が指定されてる場合は、自動でそのセッションをアタッチし、tmux 画面を表示する
- さらに --auto-claude-launch なら自動で claude も立ち上げる
- 一時ファイル領域 ./tmp を監視し、 ./tmp/gemini-review-{num} に更新があったら session にたいして sendkey する
- ./tmp がない場合は /tmp を利用する
- 一時ファイル領域は --tmp-dir で指定できる様にする
- --think が指定されている場合、レビュー内容の後に think をつけて送信する

## Stop and SubagentStop Input
stop_hook_active is true when Claude Code is already continuing as a result of a stop hook. Check this value or process the transcript to prevent Claude Code from running indefinitely.
```
{
  "session_id": "abc123",
  "transcript_path": "~/.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
  "stop_hook_active": true
}
```

## 入力の例
```bash
# 標準入力からJSONを読み取る
INPUT=$(cat)
```

## send-keys example
```
tmux send-keys -t 'claude' "レビュー内容" Enter && sleep 5 && tmux send-keys -t "claude" "" Enter
```

## 作業サマリーの取得方法
```
jq -r '.transcript_path' | xargs cat | jq -r 'select(.type == "assistant")' | jq -sr '.[-1].message.content[-1].text'
```

# 技術スタック
- 監視が動かしやすく、インストール不要なものでいい
- 最初はBASHでいい？

# 作業チェックリスト