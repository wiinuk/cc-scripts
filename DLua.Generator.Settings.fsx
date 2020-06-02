
#load "DLua.Generator.fsx"
open DLua.Generator
open System


let rowInfo _ r = async {
    return {
        return' = cellText 1 r
        methodSign = cellText 0 r
        description = cellText 2 r
        minVersion = "?"
        linkParent = cell 0 r
        kind = All
    }
}
let settings thisName = {
    thisName = thisName
    summarySelector = querySelectorAll "#mw-content-text > p:nth-child(1)" >> Seq.map id
    trSelector = querySelectorAll "#mw-content-text > table:first-of-type > tbody > tr" >> Seq.skip 2
    rowInfo = rowInfo
    convertText = async.Return
}

let source address = {
    address = address
    path = ""
}

let declares() = [
    { settings "turtle" with
        trSelector = querySelectorAll "#mw-content-text > table:nth-child(5) > tbody > tr" >> Seq.skip 1
        rowInfo = fun _ r -> async {
            return {
                return' = cellText 0 r
                methodSign = cellText 1 r
                description = cellText 2 r
                minVersion = cellText 3 r
                linkParent = cell 1 r
                kind = styleToKind r
            }
        }
    },
    source "wiki/Turtle_(API)"
    settings "commands", source "wiki/Commands_(API)"
    settings "shell", source "wiki/Shell_(API)"
    { settings "http" with
        summarySelector = querySelectorAll "#mw-content-text > p" >> Seq.truncate 2
        trSelector = querySelectorAll "#mw-content-text > table:nth-child(3) > tbody > tr" >> Seq.skip 2
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
        trSelector = querySelectorAll "#mw-content-text > table:nth-child(7) > tbody > tr" >> Seq.skip 2
    },
    source "wiki/Peripheral_(API)"
    settings "rednet", source "wiki/Rednet_(API)"
    { settings "redstone" with
        rowInfo = fun s r -> async {
        let! return' = parseReturnFromDetailPage s r
        return {
            return' = return'
            methodSign = cellText 0 r
            description = cellText 1 r
            minVersion = "?"
            linkParent = cell 0 r
            kind = All
        }
    }
    },
    source "wiki/Redstone_(API)"
    settings "settings", source "wiki/Settings_(API)"
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
