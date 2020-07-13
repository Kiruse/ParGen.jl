# Parser-internal turing-like Finite State Machine (FSM) & state graph
# Copyright (c) Skye Cobile 2020 Germany
# SEE LICENSE IN LICENSE
# --------------------------------------------------------------------

"""An element in the state machine's scope memory stack."""
abstract type ScopeMemory end

const RuleStateMap = Dict{Symbol, AbstractState}

"""A ScopeMemory representing a rule scope. May be a placeholder if `isfinal == false` to be updated with the proper
rule name in a following node."""
struct RuleMemory <: ScopeMemory
    rule::Symbol
    isfinal::Bool
    captures::Vector{CaptureSequence}
end
RuleMemory() = RuleMemory(:pargen_placeholder, false, [])
RuleMemory(rule::Symbol) = RuleMemory(rule, true, [])

"""A ScopeMemory representing a capture scope."""
struct CaptureMemory <: ScopeMemory
    captures::CaptureSequence
end
CaptureMemory() = CaptureMemory(CaptureSequence())


"""A turing-like finite state machine."""
mutable struct StateMachine <: AbstractStateMachine
    currstate::AbstractState
    scopes::Vector{ScopeMemory}
    captures::Vector{CaptureSequence}
    rulereturns::Vector{Int}
end
StateMachine(initstate::AbstractState = VanityState()) = StateMachine(initstate, [], [], [])


include("./States.jl")
include("./StateGraphOptimizers.jl")


function parse(fsm::StateMachine, source::SourceString)
    next = parse(fsm, fsm.currstate, source)
    while next !== nothing
        fsm.currstate = next
        next = parse(fsm, fsm.currstate, source)
    end
    fsm.captures
end

"""Parse given source code by applying supplied state. Advances the FSM to exactly one of the state's successors."""
function parse(fsm::StateMachine, state::AbstractState, source::SourceString)
    successors = consume!(source, state, fsm)
    if successors === nothing
        throw(SyntaxError(source.line, source.column, currentrulename(fsm)))
    end
    
    # Find singular successor state
    # In strict mode, if more than one successor is technically applicable, this is considered a violation of the
    # deterministic state graph and hence raises an error.
    if isstrict()
        matches = filter!(x->x[1], map(next->(next, testconsume(source, next)), successors))
        if length(matches) > 1
            throw(StateGraphError(state, fsm, "ambiguous option resolution"))
        elseif length(matches) == 1
            return first(matches)[1]
        end
    else
        for next ∈ successors
            if testconsume(source, next)
                return next
            end
        end
    end
    nothing
end

function currentrulename(fsm::StateMachine)
    idx = findlast(scope->isa(scope, RuleMemory), fsm.scopes)
    if idx === nothing
        throw(StateGraphError(state, fsm, "no active rule scope in FSM"))
    end
    fsm.scopes[idx].rule
end


# State Graph Generation & Compaction

"""Generates a finite and deterministic state machine from the given parser's rules."""
function statemachine(parser::Parser)
    blankstate = VanityState()
    fsm = StateMachine(blankstate)
    if isempty(rules(parser, :pargen_blank))
        throw(ParsingError(parser, "no initial rule transition"))
    end
    
    fsm.currstate = states(:pargen_blank, RuleStateMap(), parser, Threads.Atomic{Int}())
    optimize(pargenoptimizer(), fsm)
    
    # Ensure all rules were found tracing the parser routes.
    if isstrict()
        checkrules(fsm, parser)
    end
    
    fsm
end

function compact!(fsm::StateMachine)
    # TODO: Generate compact graph that ensures uniqueness of states in order to achieve DFA
    fsm
end

function checkrules(fsm::StateMachine, parser::Parser)
    defined = keys(parser.rules)
    found   = Set{Symbol}()
    visited = Set{AbstractState}()
    
    pending = AbstractState[fsm.currstate]
    while !isempty(pending)
        curr = splice!(pending, 1)
        if curr ∈ visited continue end
        push!(visited, curr)
        
        if isa(curr, RuleEnterState)
            push!(found, curr.rule)
        end
        append!(pending, successors(curr))
    end
    
    miss = setdiff(defined, found)
    if !isempty(miss)
        throw(ParsingError(parser, "unused rules: $(join(miss, ", "))"))
    end
    nothing
end


states(pattern::StaticPattern,  ::RuleStateMap, ::Parser, ::Threads.Atomic{Int}) = StaticState(pattern.static)
states(pattern::CharSetPattern, ::RuleStateMap, ::Parser, ::Threads.Atomic{Int}) = CharSetState(pattern.charset)
states(::EmptyPattern, ::RuleStateMap, ::Parser, ::Threads.Atomic{Int}) = VanityState()

states(rulelist::Iterable{Rule}, rules::RuleStateMap, parser::Parser, nxretid::Threads.Atomic{Int}) = map(rule->states(rule, rules, parser, nxretid), rulelist)

function states(rulename::Symbol, rulemap::RuleStateMap, parser::Parser, nxretid::Threads.Atomic{Int})
    if haskey(rulemap, rulename)
        return rulemap[rulename]
    end
    
    leave = RuleLeaveState(rulename)
    enter = rulemap[rulename] = RuleEnterState(rulename, leave)
    for rule ∈ rules(parser, rulename)
        subject = states(rule.pattern, rulemap, parser, nxretid)
        link!(enter, subject)
        link!(leaves(subject), leave)
    end
    
    enter
end

function states(pattern::CapturePattern, rules::RuleStateMap, parser::Parser, nxretid::Threads.Atomic{Int})
    enter = CaptureEnterState()
    subject = states(pattern.subject, rules, parser, nxretid)
    leave = CaptureLeaveState()
    
    link!(enter, subject)
    link!(leaves(subject), leave)
    enter
end

function states(pattern::AndConjunctionPattern, rules::RuleStateMap, parser::Parser, nxretid::Threads.Atomic{Int})
    if isempty(pattern.subjects)
        throw(ArgumentError("empty AndConjunctionPattern"))
    end
    
    subjects = collect(map(subj->states(subj, rules, parser, nxretid), pattern.subjects))
    
    for (subj1, subj2) ∈ bubblepairs(subjects; excludelast=true)
        link!(leaves(subj1), subj2)
    end
    
    first(subjects)
end

function states(pattern::OrConjunctionPattern, rules::RuleStateMap, parser::Parser, nxretid::Threads.Atomic{Int})
    VanityState(Set(map(subj->states(subj, rules, parser, nxretid), pattern.subjects))) # VanityState will be optimized away
end

function states(pattern::RulePattern, rules::RuleStateMap, parser::Parser, nxretid::Threads.Atomic{Int})
    ruleenter = states(pattern.name, rules, parser, nxretid)
    ruleleave = ruleenter.partner
    returnto  = VanityState()
    RuleCallState(addreturnjump(ruleleave, returnto, nxretid), ruleenter)
end

function states(pattern::MultiplicityPattern, rules::RuleStateMap, parser::Parser, nxretid::Threads.Atomic{Int})
    RepeatState(states(pattern.subject, rules, parser, nxretid), pattern.min, pattern.max)
end

link!(lhs, rhs) = link!(iterable(lhs), rhs)
link!(lhs::AbstractState, rhs) = link!(lhs, Set(iterable(rhs)))
link!(lhs::AbstractState, rhs::AbstractState) = (push!(lhs.successors, rhs); lhs)
link!(lhs::AbstractState, rhs::Set{AbstractState}) = (union!(lhs.successors, rhs); lhs)
link!(lhs::Iterable{AbstractState}, rhs) = (foreach(state->link!(state, rhs), lhs); lhs)


function leaves(start::AbstractState)
    results = AbstractState[]
    visited = Set(AbstractState[])
    curr    = AbstractState[start]
    
    while !isempty(curr)
        # Shift item
        item = splice!(curr, 1)
        
        # Infinite loop prevention
        if item ∈ visited continue end
        push!(visited, item)
        
        # Has successors?
        succs = successors(item)
        if isempty(succs)
            push!(results, item)
        else
            append!(curr, succs)
        end
    end
    
    results
end


function amendcapture!(fsm::StateMachine, capture::CaptureMemory)
    if findfirst(scope->isa(scope, CaptureMemory), fsm.scopes) === nothing
        push!(fsm.captures, capture.captures)
    else
        amendcapture!(last(fsm.scopes), capture)
    end
    fsm
end
amendcapture!(parent::ScopeMemory, capture::CaptureMemory) = (push!(parent.captures, capture); parent)

function amendrule!(fsm::StateMachine, rule::RuleMemory)
    if !isempty(fsm.scopes)
        amendrule!(last(fsm.scopes), rule)
    end
    fsm
end
amendrule!(parent::CaptureMemory, rule::RuleMemory) = (push!(parent.captures, RuleCapture(rule.rule, rule.captures)); parent)
amendrule!(parent::RuleMemory, ::RuleMemory) = parent # Do not amend to parent rule scope
