local ok, item = turtle.inspectDown()
if ok and
    (
        item.name == "minecraft:wheat" or
        item.name == "minecraft:carrots"
    )
    and
    (
        7 <= item.state.age
    )
then
    turtle.digDown()
end
