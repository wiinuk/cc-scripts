# *.fsx スクリプトを使いたいとき

- [.NET Core SDK](https://dotnet.microsoft.com/download) をインストールする
-
    下記コマンドでスクリプトの依存関係をインストールする
    ```powershell
    dotnet tool restore
    dotnet paket install
    ```
