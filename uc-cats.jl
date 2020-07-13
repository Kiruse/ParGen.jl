function findlastinrange(codes::AbstractVector{UInt32}, idx::Integer)
    code = codes[idx]
    for idx2 ∈ idx:length(codes)
        if codes[idx2] != code + idx2 - idx
            return idx2-1
        end
    end
    lastindex(codes)
end


contents = ""
open("./UnicodeData-14.0.0d1.txt", "r") do file
    global contents
    contents = read(file, String)
end

lines = split(contents, "\n")
categories = Dict{Symbol, Vector{UInt32}}()

for line ∈ lines
    if isempty(strip(line))
        continue
    end
    
    code, name, category, _ = split(line, ';', limit=4)
    symcat = Symbol(category)
    if !haskey(categories, symcat)
        categories[symcat] = UInt32[]
    end
    push!(categories[symcat], parse(UInt32, code, base=16))
end

# Unify consecutive ranges
open("./src/unicode_charsets.jl", "w") do file
    write(file, "# GENERATED FILE - DO NOT ALTER THIS FILE DIRECTLY\n\n")
    
    # Generate unicode category charsets
    for (category, codes) ∈ categories
        sort!(codes)
        
        tmp = Array{NTuple{2, UInt32}}(undef, length(codes))
        count = 0
        idx = 1
        while idx <= length(codes)
            count += 1
            idx2  = findlastinrange(codes, idx)
            code1 = codes[idx]
            code2 = codes[idx2]
            tmp[count] = (code1, code2)
            idx = idx2+1
        end
        resize!(tmp, count)
        
        write(file, "const unicode_$category = CharSet([$(join(map(tpl->"CharRange($(tpl[1]), $(tpl[2]))", tmp), ", "))])\n\n")
    end
    
    # Unify categories by first letter / level 1 category
    majors = Dict{Symbol, Vector{Symbol}}()
    for category ∈ keys(categories)
        firstletter = Symbol(string(category)[1])
        if !haskey(majors, firstletter)
            majors[firstletter] = Symbol[]
        end
        push!(majors[firstletter], category)
    end
    
    for (major, categories) ∈ majors
        write(file, "const unicode_$major = all_union!(CharSet(), $(join(map(cat->"unicode_$cat", categories), ", ")))\n")
    end
    write(file, "\n")
    
    exports = String[]
    for (major, categories) ∈ majors
        push!(exports, string(major))
        append!(exports, string.(categories))
        
        write(file, "unicode$major() = unicode_$major\n")
        for category ∈ categories
            write(file, "unicode$category() = unicode_$category\n")
        end
        write(file, "\n")
    end
    
    write(file, "export ")
    write(file, join(map(curr->"unicode"*curr, exports), ", "))
    write(file, '\n')
end
