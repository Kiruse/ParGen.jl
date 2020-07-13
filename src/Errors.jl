export ParGenError, ParsingError, SyntaxError, RuleError, CompositeSyntaxError

abstract type ParGenError <: Exception end

struct ParsingError <: ParGenError
    parser::Parser
    msg::String
end

function Base.show(io::IO, error::ParsingError)
    write(io, "Parsing error: $(error.msg)")
end


struct SyntaxError <: ParGenError
    line::Int
    column::Int
    rule::Symbol
    msg::String
end

function Base.show(io::IO, error::SyntaxError)
    write(io, "Syntax error (rule $(error.rule))")
    if !isempty(error.msg)
        write(io, ": $(error.msg) on line $(error.line):$(error.column)")
    end
end


struct RuleError <: ParGenError
    rule::Rule
    syntaxerror::SyntaxError
    msg::String
end
RuleError(rule::Rule, syntaxerror::SyntaxError) = RuleError(rule, syntaxerror, "")

function Base.show(io::IO, error::RuleError)
    write(io, "Rule $(error.rule.name) failed to parse wholly: ")
    if !isempty(error.msg)
        write(io, "$(error.msg) - ")
    end
    show(io, error.syntaxerror)
end


struct CompositeSyntaxError <: ParGenError
    errors::Vector{SyntaxError}
end
CompositeSyntaxError(error::CompositeSyntaxError) = error
CompositeSyntaxError(errors::AbstractVector) = CompositeSyntaxError(flattensyntaxerrors(errors))

function Base.show(io::IO, error::CompositeSyntaxError)
    write(io, "Composite syntax error ($(length(error.errors)) possible syntaxes)")
end


struct StateGraphError <: ParGenError
    state::AbstractState
    fsm::AbstractStateMachine
    msg::String
end
StateGraphError(state::AbstractState, fsm::AbstractStateMachine) = StateGraphError(state, fsm, "")

function Base.show(io::IO, error::StateGraphError)
    write(io, "State graph error")
    if !isempty(error.msg)
        write(io, ": $(error.msg)")
    end
end


function flattensyntaxerrors(errors)
    flat = SyntaxError[]
    for error ∈ errors
        if isa(error, SyntaxError)
            push!(flat, error)
        elseif isa(error, CompositeSyntaxError)
            append!(flat, flattensyntaxerrors(error.errors))
        else
            throw(ArgumentError("Unknown error type $(typeof(error))"))
        end
    end
    flat
end
