module JLMake

export Target
export make
export @target
export @make
export @update!

using JLD2
using FileIO

mutable struct Target
    deps::Vector{Target}
    recipe
    timestamp
    cache
    name
    hash
end

function Target(name, recipe, deps::Vector{Target}, hash)
    @warn "Inner ctr called"
    t = Target(deps, recipe, 0.0, nothing, name, hash)
end

function make(target)
    for t in target.deps
        make(t)
    end

    varname = String(target.name)
    filename = String(target.name) * ".jld2"

    # No file means this is the first run ever
    !isfile(filename) && (update!(target); return target.cache)

    # Target was made in previous session. Is it up-to-date?
    deps_stamp = reduce(max, getfield.(target.deps, :timestamp), init=0.0)
    if target.cache == nothing
        d = load(filename)
        if d["timestamp"] < deps_stamp
            update!(target)
        else
            target.timestamp = d["timestamp"]
            target.cache = d[varname]
        end
        return target.cache
    end

    # Target was computed in this session. Is it up-to-date?
    if target.timestamp < deps_stamp
        update!(target)
    end

    return target.cache
end


function update!(target::Target)

    varname = String(target.name)
    filename = String(target.name) * ".jld2"

    target.cache = target.recipe(getfield.(target.deps, :cache)...)
    target.timestamp = time()
    save(filename, Dict(
        varname => target.cache,
        "timestamp" => target.timestamp))
end

function update!(target::Target, val)

    target.cache = val
    target.timestamp = time()

    varname = String(target.name)
    filename = String(target.name) * ".jld2"

    save(filename, Dict(
        varname => target.cache,
        "timestamp" => target.timestamp))
end


# Position independent hashing of expressions
pihash(x) = pihash(x, zero(UInt))
pihash(x::Expr,h) = pihash(x.args, pihash(x.head, h))
pihash(x::LineNumberNode,h) = h
function pihash(x::Array,h)
    for y in x
        h = pihash(y, h)
    end
    h
end
pihash(x::Any,h) = hash(x,h)

macro update!(var)
    :(update!($(esc(Symbol("target_",var)))))
end

macro update!(var, val)
    :(update!($(esc(Symbol("target_",var))), $(esc(val))))
end

macro target(out, recipe)

    @assert out isa Symbol
    @assert recipe.head == :->

    out_target = Symbol("target_", out)
    file_name = String(out) * ".jld2"

    vnames = [] # A, B, C
    tnames = [] # target, target_B, target_C

    tp = recipe.args[1]
    @assert tp.head == :tuple
    for arg in tp.args
        push!(vnames, arg)
        push!(tnames, esc(Symbol("target_", arg)))
    end

    exists = isdefined(__module__, out_target)
    recipe_hash = pihash(recipe)
    if exists
        xp = quote
            if $recipe_hash != $(esc(out_target)).hash
                $(esc(out_target)).deps = Target[$(tnames...)]
                $(esc(out_target)).recipe = $(esc(recipe))
                $(esc(out_target)).timestamp = 0.0
                $(esc(out_target)).cache = nothing
                $(esc(out_target)).hash = $recipe_hash
                isfile($file_name) && rm($file_name)
            end
        end
    else
        xp = :($(esc(out_target)) = Target($(QuoteNode(out)), $(esc(recipe)), Target[$(tnames...)], $recipe_hash))
    end
    return xp
end


macro make(vname)
    tname = Symbol("target_", vname)
    #:($(esc(vname)) = make($(esc(tname))))
    :(make($(esc(tname))))
end

end # module
