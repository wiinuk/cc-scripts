
#load ".paket/load/netstandard2.1/AngleSharp.fsx"
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
type Parameter<'a,'b> = { type': 'a; name: 'b }
type Parameters<'a,'b> = { reqs: 'a; opts: 'b }
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

module Parsers =
    let trivia0 = spaces
    let token p = p .>> trivia0

    let s = pstring
    let t = s >> token

    let name = token <| many1Chars2 letter (letter <|> digit)
    let typeName = name

    let returnParamComment = skipMany1Satisfy (function '/' | ',' -> false | _ -> true) |> skipped |> token
    let returnType = pipe2 typeName returnParamComment <| fun a b -> { name = a; comment = b }
    let returnOrType = sepBy1 returnType (t"/")
    let returnSumType = sepBy1 returnOrType (t",")
    // `boolean success, table data/string error message`
    let returnParameter = returnSumType

    let parameter = pipe2 typeName name <| fun a b -> { type' = a; name = b }

    /// `[, a b [, c d]]`
    let optionalParametersTail1, _optionalParametersTail1 = createParserForwardedToRef()
    do _optionalParametersTail1 := pipe5 (t"[") (t",") parameter (opt optionalParametersTail1) (t"]") (fun _ _ p ps _ -> p::List.concat (Option.toList ps))
    let optionalParametersTail0 = opt optionalParametersTail1 |>> (Option.toList >> List.concat)

    let optionalParameters1 = pipe4 (t"[") parameter optionalParametersTail0 (t"]") <| fun _ p ps _ -> p::ps
    let requiredParameters1 = sepBy1 parameter (t",")
    let parameters1 =
        attempt (optionalParameters1 |>> fun a -> { reqs = []; opts = a }) <|>
        pipe2 requiredParameters1 optionalParametersTail0 (fun a b -> { reqs = a; opts = b })

    let parameters = opt parameters1 |>> function None -> { reqs = []; opts = [] } | Some x -> x

    // `turtle.craft(number quantity)`
    // `turtle.getItemCount([number slotNum])`
    // `turtle.getItemCount([number slotNum [, number slotNum2]])`
    // `turtle.transferTo(number slot [, number quantity])`
    // `turtle.transferTo(number slot [, number quantity [, number quantity2]])`
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
        let link = link.QuerySelectorAll "a" |> Seq.map (fun a -> a :?> IHtmlAnchorElement) |> Seq.tryHead |> Option.map (fun a -> a.Href)

        let returnSign =
            match return' with
            | Match @"^([\w\d]+)\s+([\w\d]+)$" (Group 1 returnType & Group 2 returnName) ->
                [[{ name = returnType; comment = returnName }]]

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

type Settings<'baseDomain,'thisName,'trSelector,'rowInfo> = {
    baseDomain: 'baseDomain
    thisName: 'thisName
    trSelector: 'trSelector
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
    let link = m.link |> Option.map (fun l -> Uri(baseDomain, l + ""))
    let ps = methodSign.ps

    match link with
    | None -> ()
    | Some link -> fprintfn w "--- [■](%s)" <| string link

    fprintfn w "--- %s" description
    if minVersion <> "?" then
        fprintfn w "--- (Min version: %s)" minVersion

    match kind with
    | All -> ()
    | AnyTool | Crafty | Digging as kind ->
        fprintfn w "--- (Only: %A)" kind

    for r in returnSign do
        seq { for { comment = c; name = n } in r -> n + " " + c }
        |> String.concat "|"
        |> fprintfn w "---@return %s"

    for { type' = t; name = n } in Seq.append ps.reqs ps.opts do
        fprintfn w "---@param %s %s" n t

    for i in 1..List.length ps.opts-1 do
        let opts, _ = List.splitAt (i + 1) ps.opts
        let ps = seq { for p in Seq.append ps.reqs opts do sprintf "%s: %s" p.name p.type' } |> String.concat ", "
        let returnType = seq { for ot in returnSign do seq { for t in ot do t.name }|> String.concat "|" } |> String.concat ", "
        fprintfn w "---@overload fun(%s): %s" ps returnType

    let methodParameters = seq { for p in Seq.append ps.reqs ps.opts do p.name } |> String.concat ", "
    fprintfn w "function %s.%s(%s) end" methodSign.this methodSign.name methodParameters
    fprintfn w ""

let writeLuaDeclarationSource w settings (doc: IParentNode) =
    let { baseDomain = baseDomain; thisName = thisName; trSelector = trSelector; rowInfo = rowInfo } = settings

    let summary =
        let summary = doc.QuerySelector "#mw-content-text > p:nth-child(1)" :?> IHtmlParagraphElement
        summary.ChildNodes
        |> Seq.map (function
            | :? IHtmlAnchorElement as a when String.IsNullOrEmpty a.Relation -> anchorToMd baseDomain a
            | n -> n.TextContent
        )
        |> String.concat ""

    fprintfn w "--- %s" <| summary.Trim()
    fprintfn w "%s = {}" thisName
    fprintfn w ""
    for m in parseMembers trSelector rowInfo doc do
        writeMember w settings m

let cell n (r: #IHtmlTableRowElement) = r.Cells.[index = n]
let cellText n r = (cell n r).TextContent.Trim()
let querySelectorAll s (n: #IParentNode) = n.QuerySelectorAll s
let (/) a b = Path.Combine(a, b)
