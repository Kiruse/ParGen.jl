export Parser, Rule, rule!

"""An intermittent representation of the internal state network intended for human readability.
A rule is usually comprised of a series of patterns that must all be met, lest the whole rule is considered unmet and
the source thus invalid."""
struct Rule
    name::Symbol
    pattern::AbstractPattern
end
Rule(name::Symbol) = Rule(name, EmptyPattern())
Rule(name::Symbol, arg) = Rule(name, pattern(arg))
Rule(name::Symbol, patterns...) = Rule(name, andvein(pattern.(patterns)...))


"""An abstract representation of the rules & patterns of a parser.
The gathered information will be used to generate an internal compact state graph capable of parsing these same rules."""
mutable struct Parser <: AbstractParser
    rules::Dict{Symbol, Vector{Rule}}
end
Parser() = Parser(Dict())

function rule!(parser::Parser, rule::Rule)
    if !haskey(parser.rules, rule.name)
        parser.rules[rule.name] = Rule[]
    end
    push!(parser.rules[rule.name], rule)
    parser
end
rules(parser::Parser, rulename::Symbol) = parser.rules[rulename]


function consume!(source::SourceString, parser::Parser)
    if isempty(rules(parser, :pargen_blank))
        throw(ParsingError(parser, "undefined blank rule"))
    end
    
    result = consume!(source, parser, :pargen_blank)
    
    if !isa(result, ASTNode)
        throw(result) # SyntaxError or CompositeSyntaxError
    end
    if !isempty(source)
        throw(ParsingError(parser, "unexpected source past terminal state"))
    end
    
    result
end

function consume!(source::SourceString, parser::Parser, rulename::Symbol)
    if isempty(rules(parser, rulename))
        throw(ParsingError(parser, "undefined rule $rulename"))
    end
    
    errors = ParGenError[]
    for rule ∈ rules(parser, rulename)
        result = consume!(source, parser, rule)
        if isa(result, ASTNode)
            return result
        else
            push!(errors, result)
        end
    end
    CompositeSyntaxError(errors) # No rule matched, throw
end

function consume!(source::SourceString, parser::Parser, rule::Rule)
    consume!(source, parser, rule.pattern, rule.name)
end


function Base.show(io::IO, rule::Rule)
    write(io, "Rule $(rule.name)")
end
