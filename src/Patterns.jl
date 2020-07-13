export pattern, capture, orvein, andvein, minmax, atleast, optional

pattern(inst::AbstractPattern) = inst

struct StaticPattern <: AbstractPattern
    static::String
end
pattern(static::AbstractString) = StaticPattern(static)
pattern(char::Char) = StaticPattern(string(char))

struct CharSetPattern <: AbstractPattern
    charset::CharSet
end
pattern(charset::CharSet) = CharSetPattern(charset)

struct CapturePattern <: AbstractPattern
    subject::AbstractPattern
end
capture(subject) = CapturePattern(pattern(subject))

struct OrConjunctionPattern <: AbstractPattern
    subjects::Vector{AbstractPattern}
end
orvein(patterns...) = OrConjunctionPattern(collect(pattern.(patterns)))

struct AndConjunctionPattern <: AbstractPattern
    subjects::Vector{AbstractPattern}
end
andvein(patterns...) = AndConjunctionPattern(collect(pattern.(patterns)))

struct RulePattern <: AbstractPattern
    name::Symbol
end
pattern(rule::Symbol) = RulePattern(rule)
rule(   rule::Symbol) = RulePattern(rule)

struct MultiplicityPattern <: AbstractPattern
    subject::AbstractPattern
    min::Int
    max::Int
    
    function MultiplicityPattern(subject, min, max)
        if isa(subject, MultiplicityPattern)
            throw(ArgumentError("Cannot multiply another multiplicity pattern - unify them instead!"))
        end
        if max < min && max != 0
            throw(ArgumentError("Invalid multiplicity range $min-$max: $max < $min"))
        end
        new(subject, min, max)
    end
end
minmax(subject, mincnt::Integer, maxcnt::Integer = mincnt) = MultiplicityPattern(pattern(subject), mincnt, maxcnt)
atleast(subject, count::Integer) = MultiplicityPattern(pattern(subject), count, 0)
optional(subject) = MultiplicityPattern(pattern(subject), 0, 1)

"""Dummy pattern for empty rules. Such rules are considered terminal."""
struct EmptyPattern <: AbstractPattern end
