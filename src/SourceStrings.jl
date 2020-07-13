mutable struct SourceString{B<:AbstractString} <: AbstractString
    source::B
    cursor::Int
    line::Int
    column::Int
end
SourceString(source::AbstractString) = SourceString(source, 1, 1, 1)
SourceString(source::SourceString)   = copy(source)

function consume!(source::SourceString, n::Integer = 1)
    if n == 0 return end
    
    cursor1 = source.cursor
    cursor2 = source.cursor = nextind(source, cursor1, n)
    result = SubString(source.source, cursor1, cursor2-1)
    
    nlines = countnewlines(result)
    if nlines == 0
        source.column += length(result)
    else
        source.line += nlines
        idx = findlast('\n', result)
        if isvalid(result, idx+1) && result[idx+1] == '\r'
            idx += 1
        end
        source.column = length(result) - idx + 1
    end
    
    result
end

function countnewlines(str::AbstractString)
    lines = 0
    idx = 1
    while (matches = match(r"\r\n|\n\r|\n", str, idx)) !== nothing
        lines += 1
        idx = matches.offset + ncodeunits(matches.match)
    end
    lines
end

Base.sizeof(str::SourceString) = sizeof(str.source)
Base.length(str::SourceString) = length(str.source, str.cursor, sizeof(str.source))
Base.length(str::SourceString, i::Integer, j::Integer) = length(str.source, i, j)
Base.iterate(str::SourceString, idx::Integer = str.cursor) = idx > sizeof(str) ? nothing : (str.source[idx], nextind(str, idx))
Base.ncodeunits(str::SourceString) = ncodeunits(str.source)
Base.isvalid(str::SourceString, i::Integer) = isvalid(str.source, i)

Base.startswith(str::SourceString, needle::AbstractString) = first(str, length(needle)) == needle
Base.endswith(  str::SourceString, needle::AbstractString) = endswith(str.source, needle)
Base.getindex(str::SourceString, idx::Integer) = getindex(str.source, str.cursor + idx - 1)
Base.getindex(str::SourceString, range::UnitRange{<:Integer}) = getindex(str.source, str.cursor+range.start-1:str.cursor+range.stop-1)
Base.firstindex(str::SourceString) = str.cursor
Base.lastindex( str::SourceString) = lastindex(str.source)

Base.copy(source::SourceString) = SourceString(source.source, source.cursor, source.line, source.column)
