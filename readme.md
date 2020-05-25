`*.fsx` スクリプトを使いたいとき

- [.NET Core SDK](https://dotnet.microsoft.com/download) をインストールする
-
    スクリプトの依存関係をインストールする
    ```powershell
    dotnet tool restore
    dotnet paket install
    ```

-
    `*.fsx` スクリプトを実行する
    ```powershell
    dotnet fsi <スクリプト名>.fsx
    ```
