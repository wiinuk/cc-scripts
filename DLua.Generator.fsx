
#r "nuget: AngleSharp.Css"
#r "nuget: FParsec"
#r "System.Net.Http.dll"
open AngleSharp
open AngleSharp.Css.Dom
open AngleSharp.Css.Parser
open AngleSharp.Dom
open AngleSharp.Html.Dom
open AngleSharp.Html.Parser
open AngleSharp.Io
open FParsec
open System
open System.IO
open System.Security.Cryptography
open System.Text
open System.Text.RegularExpressions

type ReturnType<'a,'b> = { name: 'a; comment: 'b }
type Parameter<'``type'``,'name> = { type': '``type'``; name: 'name }
type Parameters<'reqs,'opts,'varArg> = { reqs: 'reqs; opts: 'opts; varArg: 'varArg }
type MethodSign<'a,'b,'c> = { this: 'a; name: 'b; ps: 'c }

let random = Random()
let rec range() =
    let r = (random.NextDouble() + random.NextDouble() + random.NextDouble() + random.NextDouble() + random.NextDouble()) / 5.
    if r < 0.5 then range() else (r - 0.5) * 2.

let wait min max = async {
    let waitTime = int (min + range() * (max - min))
    printfn "wait: %dms" waitTime
    do! Async.Sleep waitTime
}

let config = Configuration.Default.WithDefaultLoader(LoaderOptions(IsResourceLoadingEnabled = true)).WithCss()
let parseHtml address = async {
    do! wait 500. 20000.
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

type Type<'namedType,'functionType,'unknownType> =
    | NamedType of 'namedType
    | FunctionType of 'functionType
    | UnknownType of 'unknownType
    | OrType of Type<'namedType,'functionType,'unknownType> list

type CompositeType<'T> =
    | Sum of 'T CompositeType list
    | Or of 'T CompositeType list
    | Prim of 'T

let rec merge f = function
    | x::xs, y::ys -> f x y::merge f (xs, ys)
    | xs, []
    | [], xs -> xs

let rec flatten = function
    | Prim x -> [[x]]

    | Sum [] -> []
    | Sum(t::ts) -> flatten t @ flatten (Sum ts)

    | Or [] -> [[]]
    | Or(t::ts) -> merge (@) (flatten t, flatten (Or ts))

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
    let sepBy p sep = opt (sepBy1 p sep) |>> Option.defaultValue []

    /// backtracking version
    let choice ps = choice <| List.map attempt ps

module Parsers =
    open BacktrackingParsers

    let trivia0 = spaces
    let token p = p .>> trivia0

    let s = pstring
    let t p = s p |> token

    let keywords = Set ["or"]
    let knownTypeNames = Set ["nil"; "boolean"; "number"; "string"; "table"]

    let letter = letter <|> pchar '_'
    let notKeyword p = p >>= fun n -> if Set.contains n keywords then fail "keyword" else preturn n
    let name =
        many1Chars2 letter (letter <|> digit)
        |> notKeyword
        |> token

    let typeName = name

    let any = skipMany1Satisfy (function ' ' | '(' | ')' | '/' | '.' | ',' -> false | _ -> true) |> skipped |> notKeyword
    let returnParamComment = many1 <| token any
    let returnPrimType, private _returnPrimType = createParserForwardedToRef()
    let returnOrType = sepBy1 returnPrimType (t"/" <|> t"or") |>> Or
    let returnSumType = sepBy1 returnOrType (t",") |>> Sum
    let returnType = returnSumType
    _returnPrimType := choice [
        t"(" >>. returnType .>> t")"
        typeName .>>. returnParamComment |>> fun (a, b) -> Prim { name = a; comment = Some <| String.concat " " b }
        typeName |>> fun n -> Prim { name = n; comment = None }
    ]
    // `boolean success, table data/string error message`
    let returnParameter = returnType .>>. (opt (t"," >>. t"...") |>> Option.isSome)

    let typeSign = sepBy1 typeName (t"/" <|> t"or") |>> function
        | [t] -> NamedType t
        | ts -> OrType <| List.map NamedType ts

    let parameterFull = choice [
        // peripheral.find(string type [, function fnFilter( name, object )])
        t"function" >>. name .>> t"(" .>>. sepBy name (t",") .>> t")" |>> fun (a, b) -> { name = a; type' = FunctionType b }
        typeSign .>>. many1 name |>> fun (a, b) -> { type' = a; name = String.concat "_" b }
    ]
    /// `name type` 形式の完全なパラメーターと共に
    /// `nameOrType` 形式の不完全なパラメーターも認識する
    let parameterPrim = choice [
        parameterFull
        name |>> fun x ->
            if Set.contains x knownTypeNames
            then { type' = NamedType x; name = "" }
            else { type' = UnknownType(); name = x }
    ]

    /// 全ての内部のパラメーターが完全な時だけ、選択パラメーターとする
    let parameterOr = choice [
        sepBy1 parameterFull (t"/" <|> t"or")
        parameterPrim |>> List.singleton
    ]
    let parameter = parameterOr

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
        let start = choice [
            t"[" >>. t","
            t"," >>. t"["
        ]
        start >>. requiredParameters1 .>>. opt tail .>> t"]" |>> function
            | head, None -> [head], false
            | head, Some(tail, varArg) -> head::tail, varArg

    let optionalParametersTail0 =
        many optionalParametersTail1
        |>> fun opts -> List.collect fst opts, List.exists snd opts

    let optionalParametersHead1 = t"[" >>. requiredParameters1 .>> t"," .>> t"]"
    let optionalParametersHead0 = opt optionalParametersHead1 |>> Option.defaultValue []
    let optionalParameters1 =
        between (t"[") (t"]") (opt optionalParametersHead1 .>>. requiredParameters1 .>>. optionalParametersTail0)
        // TODO:
        |>> fun ((h, p), (ps, v)) ->
            let ps = p::ps
            let ps = match h with None -> ps | Some h -> h::ps
            ps, v

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

        let param (t, n) = { type' = t; name = n }
        let named (t, n) = param(NamedType t, n)
        let p (t, n) = [named(t, n)]
        let req1 p1 = { reqs = [p1]; opts = []; varArg = false }
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

        parse "t1 p1 / t2 p2" =? req1 [named("t1", "p1"); named("t2", "p2")]
        parse "number / nil p1" =? req1 [param(OrType [NamedType "number"; NamedType "nil"], "p1")]

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

type FunctionExtension<'returnSign,'methodSign> = {
    returnSign: 'returnSign
    methodSign: 'methodSign
}
type FieldExtension<'fieldThis,'fieldName,'fieldType> = {
    fieldName: 'fieldName
    fieldThis: 'fieldThis
    fieldType: 'fieldType
}

type MemberExtension<'function_,'field> =
    | Function of 'function_
    | Field of 'field

type MemberInfo<'description,'link,'minVersion,'kind,'extension> = {
    description: 'description
    link: 'link
    minVersion: 'minVersion
    kind: 'kind
    extension: 'extension
}

type Definition<'thisName,'summarySelector,'parseMembers,'convertText> = {
    thisName: 'thisName
    summarySelector: 'summarySelector
    parseMembers: 'parseMembers
    convertText: 'convertText
}

type WriteSettings<'baseDomain,'cacheDir,'outDir,'getName> = {
    baseDomain: 'baseDomain
    cacheDir: 'cacheDir
    outDir: 'outDir
    getName: 'getName
}

let querySelectorAll s (n: #IParentNode) = n.QuerySelectorAll s
let anchors =
    querySelectorAll "a"
    >> Seq.map (fun a -> a :?> IHtmlAnchorElement)

let anchorRefs =
    anchors
    >> Seq.map (fun a -> a.Href)

let parseMember f =
    let {
        description = description
        minVersion = minVersion
        link = link
        kind = kind
        extension = extension
        } = f

    let link = anchorRefs link |> Seq.tryHead


    let extension =
        match extension with
        | Function { returnSign = return'; methodSign = methodName } ->
            let returnSign =
                match return' with
                | Match @"^([\w\d]+)\s+([\w\d]+)$" (Group 1 returnType & Group 2 returnName) ->
                    [[{ name = returnType; comment = Some returnName }]], false

                | Parse Parsers.returnParameter (st, varReturn) -> flatten st, varReturn
                | "" -> [], false
                | _ -> failwithf "unknown return format: %A" return'

            let methodSign =
                match methodName with
                | Parse Parsers.methodSign s -> s
                | _ -> failwithf "unknown methodName: %A" methodName
            Function {
                returnSign = returnSign
                methodSign = methodSign
            }
        | Field f -> Field f
    {
        description = description
        link = link
        minVersion = minVersion
        kind = kind
        extension = extension
    }

module Member =
    let mapExtension f m =
        {
            extension = f m.extension
            description = m.description
            link = m.link
            minVersion = m.minVersion
            kind = m.kind
        }
    let withExtension x = mapExtension <| fun _ -> x

    let this = function
        | { extension = Function f } -> f.methodSign.this
        | { extension = Field f } -> f.fieldThis

    let ofFunction m = mapExtension Function m
    let ofField m = mapExtension Field m

let parseMembers settings definition (doc: IParentNode) = async {
    let! members = definition.parseMembers settings doc
    return seq {
        for m in members do
            parseMember m
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

let formatDescription source =
    Regex.Replace(input = source, pattern = @"[\s\r\n]+", replacement = " ", options = RegexOptions.Multiline).Trim()

let makeAbsolute (baseDomain: Uri) address =
    let address = Uri(address, UriKind.RelativeOrAbsolute)
    if address.IsAbsoluteUri then
        if address.Scheme = "about" then Uri(baseDomain, address.AbsolutePath)
        else address
    else Uri(baseDomain, address)

let writeFunction w f =
    let {
        methodSign = methodSign
        returnSign = returnSign, varReturn
        } = f

    let sign = methodSign.ps
    for r in returnSign do
        let typeName = String.concat "|" <| seq {
            for { ReturnType.name = n } in r -> n
        }
        let comments = String.concat "" <| seq {
            for { comment = c } in r do
                match c with
                | Some c -> yield " " + c
                | _ -> ()
        }
        fprintfn w "---@return %s%s" typeName comments

    if varReturn then
        let (|IdN|_|) x =
            let m = Regex.Match(x, pattern = @"^([\w_][\d\w_]*)(\d)")
            if m.Success then Some(m.Groups.[1].Value, m.Groups.[2].Value)
            else None

        let varReturnId returnSign =
            let length = List.length returnSign
            if length < 2 then None else

            match List.item (length - 2) returnSign, List.item (length - 1) returnSign with
            | [{ name = t1; comment = Some(IdN(id1, n1)) }], [{ name = t2; comment = Some(IdN(id2, n2)) }]
                when t1 = t2 && id1 = id2 && int n1 + 1 = int n2 ->
                Some(t1, id1)
            | _ -> None

        match varReturnId returnSign with
        | None -> fprintfn w "---@return any _varReturns"
        | Some(typeName, id) -> fprintfn w "---@return %s %sN" typeName id

    let concat reqs opts = List.concat (reqs::opts)
    let rec showType = function
        | UnknownType() -> "any"
        | NamedType t -> t
        | FunctionType ts ->
            ts
            |> Seq.map (sprintf "%s: any")
            |> String.concat ", "
            |> sprintf "fun(%s): any"

        | OrType ts ->
            ts
            |> Seq.map showType
            |> String.concat "|"

    let mergeParameter parameterOrs =
        let typeName = parameterOrs |> List.map (fun p -> p.type') |> OrType
        let paramName = parameterOrs |> Seq.map (fun p -> p.name) |> String.concat "_or_"
        { type' = typeName; name = paramName }

    for p in concat sign.reqs sign.opts do
        let { type' = t; name = n } = mergeParameter p
        fprintfn w "---@param %s %s" n <| showType t

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
            |> parametersSign (fun p ->
                let p = mergeParameter p
                sprintf "%s: %s" p.name (showType p.type')
            ) sign.varArg

        let returnType = String.concat ", " <| seq {
            for ot in returnSign do
                String.concat "|" <| seq {
                    for t in ot do t.name
                }
        }
        fprintfn w "---@overload fun(%s): %s" sign returnType

    let methodParameters =
        concat sign.reqs sign.opts
        |> parametersSign (fun p -> mergeParameter(p).name) sign.varArg

    let body =
        match sign with
        | { reqs = []; opts = []; varArg = false } -> ""
        | _ -> sprintf "local _ = { %s } " methodParameters

    fprintfn w "function %s.%s(%s) %send" methodSign.this methodSign.name methodParameters body
    fprintfn w ""

let writeField w f =
    let { fieldName = name; fieldThis = this; fieldType = fieldType } = f

    fprintfn w "---@type %s" fieldType
    fprintfn w "%s.%s = print()" this name

let writeMember w { baseDomain = baseDomain } { convertText = convertText } m = async {
    let {
        description = description
        minVersion = minVersion
        kind = kind
        link = link
        extension = extension
        } = m

    match link with
    | None -> ()
    | Some link ->
        let link = makeAbsolute baseDomain link
        fprintfn w "--- [■](%s)" <| string link

    let! description = convertText <| formatDescription description
    fprintfn w "--- %s" description

    if minVersion <> "?" then
        let! title = convertText "Min version"
        fprintfn w "--- (%s: %s)" title minVersion

    match kind with
    | All -> ()
    | AnyTool | Crafty | Digging as kind ->
        let! only = convertText "Only"
        fprintfn w "--- (%s: %A)" only kind

    match extension with
    | Function f -> writeFunction w f
    | Field f -> writeField w f
}
let writeLuaDeclarationSource w settings definition doc = async {
    let { baseDomain = baseDomain } = settings
    let { convertText = convertText } = definition

    let summaries =
        definition.summarySelector(doc: IParentNode)
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
        let! s = convertText <| formatDescription s
        fprintfn w "--- %s" s
    

    let mutable thisNames = Set.empty
    let! ms = parseMembers settings definition doc
    for m in ms do
        let thisName = Member.this m
        if not <| Set.contains thisName thisNames then
            fprintfn w "%s = {}" thisName
            fprintfn w ""
        do! writeMember w settings definition m
        thisNames <- Set.add thisName thisNames

    fprintfn w ""
}
let cell n (r: #IHtmlTableRowElement) =
    try r.Cells.[index = n]
    with :? ArgumentOutOfRangeException ->
        eprintfn "textContent: %A" r.TextContent
        reraise()

let cellText n r = (cell n r).TextContent.Trim()
let (/) a b = Path.Combine(a, b)

type DocSource<'address,'path> = {
    address: 'address
    path: 'path
}
let downloadDocCached cacheDir path (address: Uri) = async {
    let path =
        match path with
        | Some path ->
            if Path.IsPathRooted(path + "")
            then path
            else cacheDir/path

        | _ ->

        let name =
            address
            |> string
            |> Encoding.UTF8.GetBytes
            |> SHA256.Create().ComputeHash
            |> Seq.map (sprintf "%02x")
            |> String.concat ""

        cacheDir/Path.ChangeExtension(name, ".html")

    if not <| File.Exists path then
        printfn "download from: %A" address
        let! doc = parseHtml <| string address
        use file = File.OpenWrite path
        use writer = new StreamWriter(file)
        do! doc.Prettify() |> writer.WriteAsync |> Async.AwaitTask
        printfn "saved: %A" path
        return doc
    else
        printfn "read from: %A" path
        let! doc = parseHtmlOfFile path
        return upcast doc
}
let getAndWriteLuaDeclarationSource writer settings (definition, source) = async {
    let! doc = downloadDocCached settings.cacheDir (Some source.path) (Uri source.address)
    do! writeLuaDeclarationSource writer settings definition doc
}
let parseReturnFromDetailPage s r = async {
    let link = cell 0 r

    let link = anchorRefs link |> Seq.tryHead

    match link with
    | None -> return ""
    | Some url ->

    let url = makeAbsolute s.baseDomain url
    let! doc = downloadDocCached s.cacheDir None url
    let td =
        doc
        |> querySelectorAll "#mw-content-text > table:nth-child(2) > tbody > tr:nth-child(4) > td:nth-child(2)"
        |> Seq.head
        :?> IHtmlTableDataCellElement
        
    match td.TextContent with
    | Parse Parsers.returnParameter _ as r -> return r
    | t ->

    let firstAnchorText = anchors td |> Seq.map (fun a -> a.TextContent) |> Seq.tryHead
    match firstAnchorText with
    | Some t -> return t
    | _ -> return t
}

type TableParserConfig<'trSelector,'rowInfo> = {
    trSelector: 'trSelector
    rowInfo: 'rowInfo
}
let rowInfo _ r = async {
    return {
        description = cellText 2 r
        minVersion = "?"
        link = cell 0 r
        kind = All
        extension = Function {
            returnSign = cellText 1 r
            methodSign = cellText 0 r
        }
    }
}
let tableParserConfig() = {
    trSelector = querySelectorAll "#mw-content-text > table:first-of-type > tbody > tr" >> Seq.skip 2
    rowInfo = rowInfo
}
let parseMembersOfTable withConfig settings doc = async {
    let config = withConfig <| tableParserConfig()
    return! Async.Sequential <| seq {
        for r: IElement in config.trSelector doc do
            async {
                return! r :?> IHtmlTableRowElement |> config.rowInfo settings
            }
    }
}
let colorFields doc = seq {
    let rows =
        doc
        |> querySelectorAll "#mw-content-text > table.wikitable > tbody > tr"
        |> Seq.skip 1

    for r in rows do
        let r = r :?> IHtmlTableRowElement
        let sign = cell 0 r

        let thisName, name =
            match sign.TextContent with
            | Match "(\w+)\.(\w+)" (Group 1 this & Group 2 name) -> this, name
            | x -> failwithf "unknown field format: %A" x

        let description =
            sprintf "decimal: %s, hexadecimal: %s, paint: %s, web: %s"
                (cellText 1 r)
                (cellText 2 r)
                (cellText 3 r)
                (cellText 4 r)
        {
            description = description
            kind = All
            link = cell 0 r
            minVersion = "?"
            extension = Field {
                fieldName = name
                fieldThis = thisName
                fieldType = "number"
            }
        }
}
let writeDeclarationFiles settings declares = async {
    for s, p in declares do
        let path =
            match p.path with
            | "" ->
                let name = Uri(p.address).Segments |> Seq.last
                Path.ChangeExtension(name, ".html")
            | p -> p
        let p = { p with path = settings.cacheDir/path }

        if not <| Directory.Exists settings.outDir then
            Directory.CreateDirectory settings.outDir |> ignore

        let path = settings.outDir/settings.getName s.thisName
        do! async {
            use w = new StreamWriter(path)
            printfn "writing %A" path
            do! getAndWriteLuaDeclarationSource w settings (s, p)
        }
        printfn "done %A" path
}

#if TEST
do
#else
lazy
#endif
    Parsers.test()
