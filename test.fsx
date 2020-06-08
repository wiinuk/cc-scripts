
open System
open System.Diagnostics
open System.IO
open System.Text
open System.Text.RegularExpressions


type StartOptions<'encoding,'workingDirectory,'onOutput,'onError> = {
    encoding: 'encoding
    workingDirectory: 'workingDirectory
    onOutput: 'onOutput
    onErrorOutput: 'onError
}

exception ProcessExitException of exitCode: int * errorLines: string seq * fileName: string * arguments: string

let startProcessWithAsync withOptions command = async {
    let options = withOptions {
        encoding = Encoding.UTF8
        workingDirectory = ""
        onOutput = fun x -> stdout.WriteLine(x + "")
        onErrorOutput = fun data ->
            let c = Console.ForegroundColor
            Console.ForegroundColor <- ConsoleColor.Red
            stderr.WriteLine(data + "")
            Console.ForegroundColor <- c
    }
    let fileName, arguments =
        let i = (command + "").IndexOf ' '
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
            UseShellExecute = false,
            WorkingDirectory = options.workingDirectory
        )

    let e = options.encoding
    i.StandardOutputEncoding <- e
    i.StandardErrorEncoding <- e

    use p = new Process(StartInfo = i, EnableRaisingEvents = true)
    p.OutputDataReceived.Add <| fun x ->
        match x.Data with
        | null -> ()
        | data -> options.onOutput data

    let errorLines = ResizeArray()
    p.ErrorDataReceived.Add <| fun x ->
        match x.Data with
        | null -> ()
        | data ->
            options.onErrorOutput data
            errorLines.Add data

    let exited = p.Exited
    if p.Start() then
        p.BeginOutputReadLine()
        p.BeginErrorReadLine()
        let! _ = Async.AwaitEvent exited
        p.WaitForExit()

        if p.ExitCode <> 0 then raise <| ProcessExitException(exitCode = p.ExitCode, errorLines = errorLines, fileName = fileName, arguments = arguments)
}
let startWithAsync withOptions = Printf.ksprintf <| startProcessWithAsync withOptions

let (/) a b = Path.Combine(a, b)
let files dir pattern = Directory.EnumerateFiles(__SOURCE_DIRECTORY__/dir, pattern, SearchOption.AllDirectories)

let luaPath = Seq.head <| seq {
    for ext in [null; ".exe"] do
        yield! files "." <| Path.ChangeExtension("lua5.1.EXTENSION", ext)
}

(*
Total tests: 4, Passed: 4,      Failed: 0
Test Run Successful.
starting tests
        evaluateWhenError
        evaluateActionError
        parameter       [FAIL]
        evaluationOrder [FAIL]
finished
Failed  parameter
ErrorMessage:
../sources/rules.lua:108: attempt to call field 'sleep' (a nil value)
Failed  evaluationOrder
ErrorMessage:
../sources/rules.lua:108: attempt to call field 'sleep' (a nil value)

Total tests: 4, Passed: 2,      Failed: 2
Test Run Failed.
*)

let raiseUnknownTestResultFormat lines =
    failwithf "unknown test result format: %s" <| String.concat "\n" lines

type TestResult<'passed,'failed> = {
    passed: 'passed
    failed: 'failed
}
let parseTestOutput lines =
    let lines = Seq.toArray lines
    if lines.Length < 3 then raiseUnknownTestResultFormat lines else

    // `Total tests: 4, Passed: 2,      Failed: 2`
    let summary = lines.[lines.Length - 2]

    let m = Regex.Match(summary, pattern = @"^\s*Total\s*tests\s*:\s*\d+,\s*Passed\s*:\s*(\d+)\s*,\s*Failed\s*:\s*(\d+)")
    if not m.Success then raiseUnknownTestResultFormat lines else

    {
        passed = int m.Groups.[1].Value
        failed = int m.Groups.[2].Value
    }
let mergeTestResult a b = {
    passed = a.passed + b.passed
    failed = a.failed + b.failed
}
let parseAndMerge result outputs =
    mergeTestResult result <| parseTestOutput outputs

async {
    let mutable result = { passed = 0; failed = 0 }

    for file in files "tests" "*.tests.lua" do
        let outputs = ResizeArray()
        let options c =
            { c with
                workingDirectory = Path.GetDirectoryName file
                onOutput = outputs.Add
                onErrorOutput = outputs.Add
            }
        try
            do! startWithAsync options "%s \"%s\"" luaPath file
            result <- parseAndMerge result outputs
        with
        | ProcessExitException _ ->
            result <- parseAndMerge result outputs
            for line in outputs do
                stdout.WriteLine line

    printfn "All tests: %d, Passed: %d, Failed: %d" (result.passed + result.failed) result.passed result.failed
    if 0 < result.failed then
        printfn "Any Test Run Failed."
        return -1
    else
        printfn "All Test Run Successful."
        return 0
}
|> Async.RunSynchronously
|> exit
