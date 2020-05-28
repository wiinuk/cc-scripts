
#load ".paket/load/netstandard2.1/AngleSharp.Css.fsx"
#load ".paket/load/netstandard2.1/FParsec.fsx"
#r "System.Net.Http.dll"
open AngleSharp
open AngleSharp.Css.Dom
open AngleSharp.Css.Parser
open AngleSharp.Dom
open AngleSharp.Html.Dom
open AngleSharp.Html.Parser
open AngleSharp.Io
open FParsec
open System.IO
open System
open System.Text.RegularExpressions

type ReturnType<'a,'b> = { name: 'a; comment: 'b }
type Parameter<'``type'``,'name> = { type': '``type'``; name: 'name }
type Parameters<'reqs,'opts,'varArg> = { reqs: 'reqs; opts: 'opts; varArg: 'varArg }
type MethodSign<'a,'b,'c> = { this: 'a; name: 'b; ps: 'c }
type Row<'description,'link,'minVersion,'kind,'returnSign,'methodSign> = {
    description: 'description
    link: 'link
    minVersion: 'minVersion
    kind: 'kind
    returnSign: 'returnSign
    methodSign: 'methodSign
}
let config = Configuration.Default.WithDefaultLoader(LoaderOptions(IsResourceLoadingEnabled = true)).WithCss()
let parseHtml address = async {
    let context = BrowsingContext.New config
    let! cancel = Async.CancellationToken
    return! context.OpenAsync(address = address, cancellation = cancel) |> Async.AwaitTask
}

let parseHtmlOfFile path = async {
    let context = BrowsingContext.New config
    let parser = HtmlParser(HtmlParserOptions(), context)
    use reader = new StreamReader(path = path)
    let! source = reader.ReadToEndAsync() |> Async.AwaitTask
    let! cancel = Async.CancellationToken
    return! parser.ParseDocumentAsync(source, cancel) |> Async.AwaitTask
}

module BacktrackingParsers =
    /// backtracking version
    let opt p = opt (attempt p)

    /// backtracking version
    let many p =
        let aux, _aux = createParserForwardedToRef()
        _aux := opt (p .>>. aux) |>> function None -> [] | Some(x, xs) -> x::xs
        aux

    /// backtracking version
    let sepBy1 p sep = p .>>. many (attempt (sep >>. p)) |>> fun (x, xs) -> x::xs

    /// backtracking version
    let choice ps = choice <| List.map attempt ps

module Parsers =
    open BacktrackingParsers

    let trivia0 = spaces
    let token p = p .>> trivia0

    let s = pstring
    let t = s >> token

    let name = token <| many1Chars2 letter (letter <|> digit)
    let typeName = name

    let returnParamComment = skipMany1Satisfy (function '/' | ',' -> false | _ -> true) |> skipped |> token
    let returnType = choice [
        typeName .>>. returnParamComment |>> fun (a, b) -> { name = a; comment = Some b }
        typeName |>> fun n -> { name = n; comment = None }
    ]
    let returnOrType = sepBy1 returnType (t"/")
    let returnSumType = sepBy1 returnOrType (t",")
    // `boolean success, table data/string error message`
    let returnParameter = returnSumType

    let parameter = typeName .>>. many1 name |>> fun (a, b) -> { type' = a; name = String.concat "_" b }

    /// e.g. `a b, c d`
    let requiredParameters1 = sepBy1 parameter (t",")
    /// `, ...`
    let tailVarArg = t"," .>> t"..." >>% ([], true)

    /// `[, a b, c d [, e f]]`, `[, a b, c d, [, e f, g h, ...]]`
    let optionalParametersTail1, _optionalParametersTail1 = createParserForwardedToRef()
    do _optionalParametersTail1 :=
        let tail = choice [
            tailVarArg
            optionalParametersTail1
        ]
        between (t"[" >>. t",") (t"]") (requiredParameters1 .>>. opt tail) |>> function
            | head, None -> [head], false
            | head, Some(tail, varArg) -> head::tail, varArg

    let optionalParametersTail0 =
        many optionalParametersTail1
        |>> fun opts -> List.collect fst opts, List.exists snd opts

    let optionalParameters1 = between (t"[") (t"]") (requiredParameters1 .>>. optionalParametersTail0) |>> fun (p, (ps, v)) -> p::ps, v
    let requiredParameterTail0 = choice [tailVarArg; optionalParametersTail0]
    let parameters1 = choice [
        // `...`
        t"..." >>% { reqs = []; opts = []; varArg = true }
        optionalParameters1 |>> fun (opts, var) -> { reqs = []; opts = opts; varArg = var }
        requiredParameters1 .>>. requiredParameterTail0 |>> fun (reqs, (opts, var)) -> { reqs = reqs; opts = opts; varArg = var }
    ]
    let parameters = opt parameters1 |>> function None -> { reqs = []; opts = []; varArg = false } | Some x -> x

    let parse p =
        runParserOnString (trivia0 >>. p .>> eof) () ""
        >> function Success(x, _, _) -> x | Failure _ as r -> failwithf "%A" r

    let test() =
        let (=?) l r = if not (l = r) then failwithf "%A =? %A" l r
        let parse = parse parameters

        let p (p, n) = { type' = p; name = n }
        let sign va rs os = { reqs = List.map p rs; opts = List.map (List.map p) os; varArg = va }
        let varSign = sign true
        let sign = sign false

        parse "" =? sign [] []
        parse "..." =? varSign [] []
        parse "a b" =? sign ["a","b"] []
        parse "a b, ..." =? varSign ["a","b"] []
        parse "[a b]" =? sign [] [["a","b"]]
        parse "[a b [, c d, e f, ...]]" =? varSign [] [["a","b"]; ["c","d"; "e","f"]]
        parse "a b [, c d]" =? sign ["a","b"] [["c","d"]]
        parse "a b, c d [, e f [, g h, i f, ...]]" =? varSign ["a","b"; "c","d"] [["e","f"]; ["g","h";"i","f"]]

        parse "a b [, c d] [, e f]" =? sign ["a","b"] [["c","d"];["e","f"]]
        parse "a b [, c d, ...] [, e f]" =? varSign ["a","b"] [["c","d"];["e","f"]]

    let methodSign = pipe4 name (t".") name (between (t"(") (t")") parameters) <| fun this _ name ps ->
        { this = this; name = name; ps = ps }

let (|Match|_|) pattern input = let m = Regex.Match(input, pattern) in if m.Success then Some m else None
let (|Group|_|) n (m: Match) =
    let g = m.Groups.[groupnum = n]
    if g.Success then Some g.Value else None

let (|Parse|_|) p source =
    match runParserOnString (Parsers.trivia0 >>. p .>> eof) () "" source with
    | ParserResult.Success(r, _, _) -> Some r
    | ParserResult.Failure _ -> None

type Kind =
    | All
    | AnyTool
    | Crafty
    | Digging

type RowInfo = {
    return': string
    methodSign: string
    description: string
    minVersion: string
    linkParent: IHtmlTableCellElement
    kind: Kind
}
let parseMembers trSelector rowInfo (doc: IParentNode) = seq {
    let rows = trSelector doc
    for r: IElement in rows do
        let r = r :?> IHtmlTableRowElement
        let { return' = return'; methodSign = methodName; description = description; minVersion = minVersion; linkParent = link; kind = kind } = rowInfo r
        let link = link.QuerySelectorAll "a" |> Seq.map (fun a -> a :?> IHtmlAnchorElement) |> Seq.map (fun a -> a.Href) |> Seq.tryHead

        let returnSign =
            match return' with
            | Match @"^([\w\d]+)\s+([\w\d]+)$" (Group 1 returnType & Group 2 returnName) ->
                [[{ name = returnType; comment = Some returnName }]]

            | Parse Parsers.returnParameter st -> st
            | _ -> failwithf "unknown return format: %A" return'

        let methodSign =
            match methodName with
            | Parse Parsers.methodSign s -> s
            | _ -> failwithf "unknown methodName: %A" methodName

        {
            description = description
            link = link
            minVersion = minVersion
            kind = kind
            returnSign = returnSign
            methodSign = methodSign
        }
}

let anchorToMd baseDomain (a: IHtmlAnchorElement) =
    let h = Uri(a.Href, UriKind.RelativeOrAbsolute)
    let h = if h.IsAbsoluteUri then h else Uri(baseDomain, h)
    let t = match a.Title with null | "" -> "" | t -> sprintf " \"%s\"" t
    let c = a.TextContent
    sprintf "[%s](%s%s)" c (string h) t

let styleToKind (r: IElement) =
    match r.Attributes.["style"] with
    | null -> All
    | style ->

    let css = CssParser().ParseDeclaration style.Value
    match css.GetBackground() with
    | "rgba(255, 168, 183, 1)" -> AnyTool
    | "rgba(143, 255, 159, 1)" -> Crafty
    | "rgba(255, 254, 122, 1)" -> Digging
    | "" -> All
    | b -> failwithf "unknown background color: %A" b

type Settings<'baseDomain,'thisName,'trSelector,'summarySelector,'rowInfo> = {
    baseDomain: 'baseDomain
    thisName: 'thisName
    trSelector: 'trSelector
    summarySelector: 'summarySelector
    rowInfo: 'rowInfo
}
let writeMember w { baseDomain = baseDomain } m =
    let {
        methodSign = methodSign
        returnSign = returnSign
        description = description
        minVersion = minVersion
        kind = kind
        } = m
    let sign = methodSign.ps

    let makeAbsolute (baseDomain: Uri) address =
        let address = Uri(address, UriKind.RelativeOrAbsolute)
        if address.IsAbsoluteUri then
            if address.Scheme = "about" then Uri(baseDomain, address.AbsolutePath)
            else address
        else Uri(baseDomain, address)

    match m.link with
    | None -> ()
    | Some link ->
        let link = makeAbsolute baseDomain link
        fprintfn w "--- [■](%s)" <| string link

    let description = Regex.Replace(input = description, pattern = "\s+", replacement = " ")
    fprintfn w "--- %s" description

    if minVersion <> "?" then
        fprintfn w "--- (Min version: %s)" minVersion

    match kind with
    | All -> ()
    | AnyTool | Crafty | Digging as kind ->
        fprintfn w "--- (Only: %A)" kind

    for r in returnSign do
        seq {
            for { comment = c; name = n } in r ->
                match c with
                | None -> n
                | Some c -> n + " " + c
        }
        |> String.concat "|"
        |> fprintfn w "---@return %s"

    let concat reqs opts = List.concat (reqs::opts)
    for { type' = t; name = n } in concat sign.reqs sign.opts do
        fprintfn w "---@param %s %s" n t

    let parametersSign print varArg ps =
        match ps with
        | [] -> if varArg then "..." else ""
        | ps ->
            let ps = seq { for p in ps -> print p } |> String.concat ", "
            if varArg then ps + ", ..." else ps

    for i in 1..List.length sign.opts-1 do
        let opts, _ = List.splitAt (i + 1) sign.opts
        let sign =
            concat sign.reqs opts
            |> parametersSign (fun p -> sprintf "%s: %s" p.name p.type') sign.varArg

        let returnType = String.concat ", " <| seq {
            for ot in returnSign do
                String.concat "|" <| seq {
                    for t in ot do t.name
                }
        }
        fprintfn w "---@overload fun(%s): %s" sign returnType

    let methodParameters =
        concat sign.reqs sign.opts
        |> parametersSign (fun p -> p.name) sign.varArg

    fprintfn w "function %s.%s(%s) end" methodSign.this methodSign.name methodParameters
    fprintfn w ""

let writeLuaDeclarationSource w settings doc =
    let { baseDomain = baseDomain; thisName = thisName; trSelector = trSelector; rowInfo = rowInfo } = settings

    let summaries =
        settings.summarySelector(doc: IParentNode)
        |> Seq.map (fun (e: IElement) ->
            e.ChildNodes
            |> Seq.map (function
                | :? IHtmlAnchorElement as a when String.IsNullOrEmpty a.Relation -> anchorToMd baseDomain a
                | n -> n.TextContent
            )
            |> String.concat ""
        )
        |> Seq.map (fun s -> s.Trim())

    for s in summaries do
        fprintfn w "--- %s" <| s.Trim()
    fprintfn w "%s = {}" thisName
    fprintfn w ""
    for m in parseMembers trSelector rowInfo doc do
        writeMember w settings m
    fprintfn w ""

let cell n (r: #IHtmlTableRowElement) =
    try r.Cells.[index = n]
    with :? ArgumentOutOfRangeException ->
        eprintfn "textContent: %A" r.TextContent
        reraise()

let cellText n r = (cell n r).TextContent.Trim()
let querySelectorAll s (n: #IParentNode) = n.QuerySelectorAll s
let (/) a b = Path.Combine(a, b)

type DocSource<'address,'path> = {
    address: 'address
    path: 'path
}
let getAndWriteLuaDeclarationSource writer (config, source) = async {
    let path = source.path
    if not <| File.Exists path then
        printfn "download from: %A" source.address
        let! doc = parseHtml source.address
        use file = File.OpenWrite path
        use writer = new StreamWriter(file)
        do! doc.Prettify() |> writer.WriteAsync |> Async.AwaitTask
        writeLuaDeclarationSource writer config doc
    else
        printfn "read from: %A" path
        let! doc = parseHtmlOfFile path
        writeLuaDeclarationSource writer config doc
}

#if TEST
do
#else
lazy
#endif
    Parsers.test()
