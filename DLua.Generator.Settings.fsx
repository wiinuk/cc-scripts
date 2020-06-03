
#load "DLua.Generator.fsx"
open DLua.Generator


let settings thisName = {
    thisName = thisName
    summarySelector = querySelectorAll "#mw-content-text > p:nth-child(1)" >> Seq.map id
    parseMembers = parseMembersOfTable id
    convertText = async.Return
}

let source address = {
    address = address
    path = ""
}

let declares() = [
    { settings "turtle" with
        parseMembers = parseMembersOfTable <| fun c ->
        { c with
            trSelector = querySelectorAll "#mw-content-text > table:nth-child(5) > tbody > tr" >> Seq.skip 1
            rowInfo = fun _ r -> async {
                return {
                    extension = Function {
                        returnSign = cellText 0 r
                        methodSign = cellText 1 r
                    }
                    description = cellText 2 r
                    minVersion = cellText 3 r
                    link = cell 1 r
                    kind = styleToKind r
                }
            }
        }
    },
    source "wiki/Turtle_(API)"
    settings "commands", source "wiki/Commands_(API)"
    settings "shell", source "wiki/Shell_(API)"
    { settings "http" with
        summarySelector = querySelectorAll "#mw-content-text > p" >> Seq.truncate 2
        parseMembers = parseMembersOfTable <| fun c ->
        { c with
            trSelector = querySelectorAll "#mw-content-text > table:nth-child(3) > tbody > tr" >> Seq.skip 2
        }
    },
    source "wiki/HTTP_(API)"

    settings "fs", source "wiki/Fs_(API)"
    settings "parallel", source "wiki/Parallel_(API)"
    settings "multishell", source "wiki/Multishell_(API)"
    settings "term", source "wiki/Term_(API)"
    settings "bit", source "wiki/Bit_(API)"
    settings "disk", source "wiki/Disk_(API)"
    settings "gps", source "wiki/Gps_(API)"
    { settings "peripheral" with
        parseMembers = parseMembersOfTable <| fun c ->
        { c with
            trSelector = querySelectorAll "#mw-content-text > table:nth-child(7) > tbody > tr" >> Seq.skip 2
        }
    },
    source "wiki/Peripheral_(API)"
    settings "rednet", source "wiki/Rednet_(API)"
    { settings "redstone" with
        parseMembers = parseMembersOfTable <| fun c ->
        { c with
            rowInfo = fun s r -> async {
            let! return' = parseReturnFromDetailPage s r
            return {
                extension = Function {
                    returnSign = return'
                    methodSign = cellText 0 r
                }
                description = cellText 1 r
                minVersion = "?"
                link = cell 0 r
                kind = All
            }
        }
    }
    },
    source "wiki/Redstone_(API)"
    settings "settings", source "wiki/Settings_(API)"
    { settings "colors" with
        parseMembers = fun settings doc -> async {
            let! functions = parseMembersOfTable id settings doc
            return [|
                yield! functions
                yield! colorFields doc
            |]
        }
    },
    source "wiki/Colors_(API)"
    settings "window", source "wiki/Window_(API)"
    settings "textutils", source "wiki/Textutils_(API)"
]

let writeAllDeclarationFiles convertText writeSettings declares =
    declares
    |> List.map (fun (d, s) ->
        { d with
            convertText = Option.defaultValue d.convertText convertText
        },
        { s with
            address =
                makeAbsolute writeSettings.baseDomain s.address
                |> string
        }
    )
    |> writeDeclarationFiles writeSettings
