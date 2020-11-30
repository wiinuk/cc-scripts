# cc-scripts

## 動作環境

- Forge 1.12.2
- CC: Tweaked 1.88.0

## タートル内でこのリポジトリのスクリプトを使う方法

1. lacc ( 依存関係マネージャー ) をインストールする

    ```sh
    pastebin run W13jSN37 remote-setup
    ```

1. 依存関係を初期化する

    ```sh
    lacc/lacc.lua init
    ```

1. このリポジトリを依存関係に追加する

    ```sh
    lacc/lacc.lua github add wiinuk/cc-scripts sources
    ```

1. ( オプション ) `PATH` にディレクトリを登録して再起動する

    ```sh
    packages/github/wiinuk/cc-scripts/sources/add-startup-script.lua

    reboot
    ```

1. このリポジトリの任意のスクリプトが実行できる
    - 例 `packages/github/wiinuk/cc-scripts/sources/echo.lua aaa`
    - 例 `echo.lua aaa` ( `PATH` にディレクトリを登録した場合 )

## `*.fsx` スクリプトを使いたいとき

- [.NET Core SDK](https://dotnet.microsoft.com/download) をインストールする
- `*.fsx` スクリプトを実行する

    ```powershell
    dotnet fsi <スクリプト名>.fsx
    ```
