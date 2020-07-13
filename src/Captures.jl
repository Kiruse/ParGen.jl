abstract type AbstractCapture end

struct CaptureSequence <: AbstractCapture
    subcaptures::Vector{AbstractCapture}
end
CaptureSequence() = CaptureSequence([])

struct StringCapture <: AbstractCapture
    match::String
end

struct RuleCapture <: AbstractCapture
    rule::Symbol
    captures::Vector{CaptureSequence}
end
