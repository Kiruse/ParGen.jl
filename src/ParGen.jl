# ParGen main module
# Copyright (c) Skye Cobile 2020 Germany
# SEE LICENSE IN LICENSE
# --------------------------------------
# TODO: Implement case insensitive matching
# TODO: A smarter way of dealing with exhausted source, probably
# TODO: Ensure consumed source is reverted upon failure

module ParGen
export pargen, pargenfile, parsefile

const Optional{T} = Union{T, Nothing}

include("./Iterables.jl")
include("./Abstracts.jl")
include("./SourceStrings.jl")
include("./CharSets.jl")
include("./Captures.jl")
include("./Patterns.jl")
include("./Parsers.jl")
include("./StateMachines.jl")
include("./ParGenParsers.jl")
include("./Errors.jl")

# Newline characters: LF, VT, FF, CR (U+000A-000D), NEL (U+0085), LS (U+2028), PS (U+2029)
# Whitespaces (hexcodes): 9-D, 20, 85, A0, 1680, 2000-200A, 2028, 2029, 202F, 205F, 3000, 180E, 200B-200D, 2060, FEFF

"""Generate a ParGen parser capable of parsing the LDef language."""
pargen() = pargenparser()

"""Generate a ParGen parser by the given language definition source."""
function pargen(ldef::AbstractString)
    captures = parse(pargen(), ldef)
    # TODO: Process captures to generate a new pargen instance
    error("Not implemented")
end

"""Generate a ParGen parser by the given LDef formatted file."""
function pargenfile(ldef::AbstractString)
    open(ldef, "r") do file
        pargen(read(file, String))
    end
end

Base.parse(parser::Parser, source::AbstractString) = consume!(SourceString(source), parser)
Base.parse(ldef::AbstractString, source::AbstractString) = parse(pargen(ldef), source)

"""Parse a source file given the specified LDef file."""
function parsefile(ldef::AbstractString, source::AbstractString)
    open(ldef, "r") do file
        parse(pargenfile(ldef), read(file, String))
    end
end


function findnextrange(cb, arr, idx::Integer)
    idx1 = findnext(cb, arr, idx)
    if idx1 !== nothing
        idx2 = findnext(elem->!cb(elem), arr, idx1)
        if idx2 !== nothing
            idx1:idx2-1
        else
            idx1:lastindex(arr)
        end
    else
        nothing
    end
end

struct BubblePairIter
    arr
    excludelast::Bool
end
bubblepairs(arr; excludelast::Bool = false) = BubblePairIter(arr, excludelast)
function Base.iterate(iter::BubblePairIter, idx::Integer = 1)
    if idx > length(iter.arr)
        nothing
        
    elseif idx == length(iter.arr)
        if iter.excludelast
            nothing
        else
            (iter.arr[idx], nothing), idx+1
        end
        
    elseif idx < length(iter.arr)
        iter.arr[idx:idx+1], idx+1
    end
end


"""Strict mode is intended for debugging of the parser itself.
Enabling strict mode has few effects:
* Maximum compactness, including uniqueness of states, is enforced at gentime.
* Distinctness of rules is enforced at gentime. This means two distinctly named rules must not consume the same source string.
* (Non-compiled) parser ensures enforces that only single transition may occur. Two distinct transitions from the same node at the same time are considered suboptimal.

Generally strict mode should not be necessary and left disabled to improve performance, but it can be helpful to
identify a possible reason for ill-behaving generated parsers."""
strictmode(value::Bool) = (global _strict; strict = value)
isstrict() = _strict
_strict = true

end # module ParGen
