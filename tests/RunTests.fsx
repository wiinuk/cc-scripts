open System.Diagnostics
open System.IO
open System.Text
open System


let private startProcessAsync (command: string) = async {
    let fileName, arguments =
        let i = command.IndexOf ' '
        if i < 0 then command, ""
        else command.[0..i-1], command.[i+1..]

    let i =
        ProcessStartInfo(
            FileName = fileName,
            Arguments = arguments,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            ErrorDialog = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        )

    let e = Encoding.UTF8
    i.StandardOutputEncoding <- e
    i.StandardErrorEncoding <- e

    use p = new Process(StartInfo = i, EnableRaisingEvents = true)
    p.OutputDataReceived.Add <| fun x ->
        match x.Data with
        | null -> ()
        | data -> stdout.WriteLine data

    let errorLines = ResizeArray()
    p.ErrorDataReceived.Add <| fun x ->
        match x.Data with
        | null -> ()
        | data ->
            let c = Console.ForegroundColor
            Console.ForegroundColor <- ConsoleColor.Red
            stderr.WriteLine data
            Console.ForegroundColor <- c
            errorLines.Add data

    let exited = p.Exited
    if p.Start() then
        p.BeginOutputReadLine()
        p.BeginErrorReadLine()
        let! _ = Async.AwaitEvent exited
        p.WaitForExit()

        if p.ExitCode <> 0 then failwithf "%A" {| ExitCode = p.ExitCode; errorLines = errorLines, fileName = fileName; arguments = arguments |}
}

let (/) a b = Path.Combine(a, b)
let luaPath = __SOURCE_DIRECTORY__/"../temp/lua-5.1.5_Win64_bin/lua5.1.exe"

async {
    for file in Directory.EnumerateFiles(__SOURCE_DIRECTORY__, "*.tests.lua", SearchOption.AllDirectories) do
        do! startProcessAsync <| sprintf "%s \"%s\"" luaPath file
}
|> Async.RunSynchronously
