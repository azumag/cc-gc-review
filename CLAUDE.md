## Project Structure
- testは ./test 以下に作成すること
- 全てのテストは pre-commit と CI に含むこと

## Test Environment Management
- テストでは mktemp -d を使用して安全な一時ディレクトリを作成
- 全テストファイルで cleanup_test_env 関数による統一クリーンアップ
- trap を使用してテスト異常終了時も確実にクリーンアップ実行
- test-tmp-* 形式の固定名ディレクトリは使用禁止