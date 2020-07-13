export CharRange, CharSet, charset, wscharset, nlcharset, wsnlcharset, allcharset

const CharValue = Union{Char, Integer}

struct CharRange
    start::UInt32
    stop::UInt32
end
CharRange(start::CharValue, stop::CharValue = start) = CharRange(UInt32(start), UInt32(stop))

struct CharSet
    ranges::Vector{CharRange}
end
CharSet() = CharSet([])
charset(start::Char, stop::Char = start) = CharSet([CharRange(start, stop)])
function charset(chars::AbstractString)
    result = CharSet(Vector())
    
    idx = 1
    while idx <= sizeof(chars)
        # Parse n-m ranges
        if addcharrange(result, chars, idx)
            idx = nextind(chars, idx, 3)
        else
            push!(result.ranges, CharRange(chars[idx], chars[idx]))
            idx = nextind(chars, idx)
        end
    end
    
    unify!(result)
end
function charset(args::Vararg{Union{CharValue, NTuple{2, CharValue}}})
    charset = CharSet([])
    for arg ∈ args
        if length(arg) > 1
            push!(charset.ranges, CharRange(arg[1], arg[2]))
        else
            push!(charset.ranges, CharRange(arg))
        end
    end
    charset
end

function unify!(charset::CharSet)
    # Merge individual ranges - sort by starting indices first to make
    # things easier as the list may collapse
    sort!(charset.ranges, alg=QuickSort, by=x->x.start)
    idx = 1
    while idx < length(charset.ranges)
        range1 = charset.ranges[idx]
        range2 = charset.ranges[idx+1]
        
        # Range 1 in range 2 or vice versa
        # As the array is sorted, range1 ∈ range2 may occur if and only if range1.start == range2.start
        if range1 ∈ range2
            splice!(charset.ranges, idx)
        elseif range1 ∋ range2
            splice!(charset.ranges, idx+1)
            
        # Range 1 ends in range 2
        elseif lintersects(range1, range2)
            splice!(charset.ranges, idx+1)
            charset.ranges[idx] = CharRange(range1.start, range2.stop)
            
        # Range 1 starts in range 2
        elseif rintersects(range1, range2)
            splice!(charset.ranges, idx+1)
            charset.ranges[idx] = CharRange(range2.start, range1.stop)
            
        # Merge adjacent ranges
        # Because the array is sorted, testing radjacent is unnecessary
        elseif ladjacent(range1, range2)
            splice!(charset.ranges, idx+1)
            charset.ranges[idx] = CharRange(range1.start, range2.stop)
            
        # Proceed to next range
        else
            idx += 1
        end
    end
    charset
end

function Base.push!(charset::CharSet, range::CharRange)
    for (idx, currrange) ∈ enumerate(charset.ranges)
        if currrange ∋ range
            break
            
        elseif currrange ∈ range
            charset.ranges[idx] = range
            break
            
        elseif lintersects(currrange, range) || ladjacent(currrange, range)
            charset.ranges[idx] = CharRange(currrange.start, range.stop)
            break
            
        elseif rintersects(currrange, range) || radjacent(currrange, range)
            charset.ranges[idx] = CharRange(range.start, currrange.stop)
            break
            
        elseif currrange.start > range.start
            splice!(charset.ranges, idx:0, [range])
        end
    end
    charset
end
Base.push!(charset::CharSet, start::Char, stop::Char = start) = push!(charset, CharRange(start, stop))

# TODO: Base.delete!(charset::CharSet, range::CharRange)

function Base.union!(lhs::CharSet, rhs::CharSet)
    append!(lhs.ranges, rhs.ranges)
    unify!(lhs)
end
Base.union(lhs::CharSet, rhs::CharSet) = union!(copy(lhs), rhs)

function Base.intersect!(lhs::CharSet, rhs::CharSet)
    error("Not implemented")
end
Base.intersect(lhs::CharSet, rhs::CharSet) = intersect!(copy(lhs), rhs)

function Base.setdiff!(lhs::CharSet, rhs::CharSet)
    idx = 1::Union{Nothing, Integer}
    for rangej ∈ rhs.ranges
        idxnx = idx
        
        while idxnx !== nothing
            idxnx = findnext(lhs.ranges, idx) do rangei
                intersects(rangei, rangej)
            end
            
            if idxnx !== nothing
                rangei = lhs.ranges[idxnx]
                lrange = CharRange(rangei.start, rangej.start-1)
                rrange = CharRange(rangej.stop+1, rangei.stop)
                
                if !isempty(lrange) && !isempty(rrange)
                    splice!(lhs.ranges, idx, (lrange, rrange))
                    idxnx += 1
                elseif !isempty(lrange)
                    lhs.ranges[idxnx] = lrange
                    idxnx += 1
                elseif !isempty(rrange)
                    lhs.ranges[idxnx] = rrange
                else
                    splice!(lhs.ranges, idxnx)
                    idxnx -= 1 # Re-test the *new* i'th range
                end
                
                idx = idxnx
            end
        end
    end
    lhs
end
Base.setdiff(lhs::CharSet, rhs::CharSet) = setdiff!(copy(lhs), rhs)

function getnextrange(charset::CharSet, min::Char, offset::Integer = 1)
    for i ∈ offset:length(charset.ranges)
        range = charset.ranges[i]
        if range.start > min
            return i, range
        end
    end
    return nothing, nothing
end

function addcharrange(charset::CharSet, str::AbstractString, idx::Integer)
    nextidx = nextind(str, idx)
    if nextidx <= sizeof(str)
        if str[nextidx] == '-'
            nextnextidx = nextind(str, nextidx)
            if nextnextidx <= sizeof(str)
                start = str[idx]
                stop  = str[nextnextidx]
                if stop < start
                    throw(ArgumentError("Invalid character range \"$start-$stop\": $stop ($(codepoint(stop))) < $start ($(codepoint(start)))"))
                end
                push!(charset.ranges, CharRange(UInt32(str[idx]), UInt32(str[nextnextidx])))
                return true
            end
        end
    end
    return false
end

Base.:+(lhs::CharSet, rhs::CharSet) = (union(lhs, rhs))
Base.:-(lhs::CharSet, rhs::CharSet) = (setdiff(lhs, rhs))

Base.copy(charset::CharSet) = CharSet(copy(charset.ranges))
Base.length(range::CharRange) = range.stop == typemax(UInt32) ? typemax(UInt32) : max(0, range.stop - range.start + 1)
Base.length(charset::CharSet) = sum(length.(charset.ranges))
Base.isempty(range::CharRange) = length(range) == 0
Base.isempty(charset::CharSet) = isempty(charset.ranges)
Base.:∈(lhs::CharRange, rhs::CharRange) = lhs.start <= rhs.stop && rhs.start <= lhs.stop
Base.:∈(lhs::Char, rhs::CharRange) = rhs.start <= UInt32(lhs) && UInt32(lhs) <= rhs.stop
function Base.:∈(lhs::Char, rhs::CharSet)
    for range ∈ rhs.ranges
        if lhs ∈ range
            return true
        end
    end
    return false
end
intersects( lhs::CharRange, rhs::CharRange) = lhs.stop >= rhs.start && lhs.start <= rhs.stop
lintersects(lhs::CharRange, rhs::CharRange) = lhs.stop >= rhs.start && lhs.stop <= rhs.stop
rintersects(lhs::CharRange, rhs::CharRange) = lhs.start >= rhs.start && lhs.start <= rhs.start
ladjacent(lhs::CharRange, rhs::CharRange) = lhs.stop + 1 == rhs.start
radjacent(lhs::CharRange, rhs::CharRange) = lhs.start == rhs.stop + 1

all_union!(lhs::CharSet, rhs::CharSet) = union!(lhs, rhs)
all_union!(args::Vararg{CharSet}) = all_union!(union!(args[1], args[2]), args[3:lastindex(args)]...)
all_setdiff!(lhs::CharSet, rhs::CharSet) = setdiff!(lhs, rhs)
all_setdiff!(args::Vararg{CharSet}) = all_setdiff!(setdiff!(args[1], args[2]), args[3:lastindex(args)]...)

function Base.show(io::IO, range::CharRange)
    try
        char1 = Char(range.start)
        char2 = Char(range.stop)
        write(io, "$char1-$char2")
    catch
        write(io, "[Char($(range.start))-Char($(range.stop))]")
    end
end
function Base.show(io::IO, charset::CharSet)
    write(io, "[")
    for range ∈ charset.ranges
        show(io, range)
    end
    write(io, "]")
end

wscharset()   = charset(0x9, 0x20, 0xA0, 0x1680, (0x2000, 0x200A), 0x202F, 0x205F, 0x3000)
nlcharset()   = charset((0xA, 0xD), 0x85, (0x2028, 0x2029))
wsnlcharset() = union(wscharset(), nlcharset())
allcharset()  = charset((typemin(UInt32), typemax(UInt32)))


# Generated Unicode Character Categories charsets
include("./unicode_charsets.jl")
