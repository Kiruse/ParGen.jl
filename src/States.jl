# States Submodule
# Copyright (c) Skye Cobile 2020 Germany
# SEE LICENSE IN LICENSE
# --------------------------------------
# Contains definitions of various states and directly related methods.

isterminal(state::AbstractState) = isempty(state.successors)

testconsume(source::SourceString, states) = testconsume(source, iterable(states))
function testconsume(source::SourceString, states::Iterable{<:AbstractState})
    for curr ∈ states
        if testconsume(source, curr)
            return true
        end
    end
    return false
end
testconsume(source::SourceString, state::AbstractGatewayState) = testconsume(source, successors(state))

successors(state::AbstractState) = state.successors
replacesuccessor!(parent::AbstractState, replaceme::AbstractState, replacewith) = replacesuccessor!(parent, replaceme, Set(iterable(replacewith)))
replacesuccessor!(parent::AbstractState, replaceme::AbstractState, ::Nothing) = (delete!(parent.successors, replaceme); parent)
function replacesuccessor!(parent::AbstractState, replaceme::AbstractState, replacewith::AbstractState)
    delete!(parent.successors, replaceme)
    push!(parent.successors, replacewith)
    parent
end
function replacesuccessor!(parent::AbstractState, replaceme::AbstractState, replacewith::Set{<:AbstractState})
    delete!(parent.successors, replaceme)
    union!(parent.successors, replacewith)
    parent
end


"""A vanity state used for default initial and terminal states."""
struct VanityState <: AbstractState
    successors::Set{AbstractState}
end
VanityState() = VanityState(Set())

consume!(source::SourceString, state::VanityState, ::StateMachine) = state.successors
testconsume(source::SourceString, state::VanityState) = true

"""A simple state of consecutive characters."""
struct StaticState <: AbstractConcreteState
    static::String
    successors::Set{AbstractState}
end
StaticState(static::String) = StaticState(static, Set())

function consume!(source::SourceString, state::StaticState, ::StateMachine)
    if startswith(source, state.static)
        consume!(source, length(state.static))
        capture!(fsm, state.static)
        state.successors
    else
        nothing
    end
end
testconsume(source::SourceString, state::StaticState) = startswith(source, state.static)

"""A simple state of alternative characters."""
struct CharSetState <: AbstractConcreteState
    charset::CharSet
    successors::Set{AbstractState}
end
CharSetState(charset::CharSet) = CharSetState(charset, Set())

function consume!(source::SourceString, state::CharSetState, fsm::StateMachine)
    char = first(source)
    if char ∈ state.charset
        consume!(source, 1)
        capture!(fsm, char)
        state.successors
    else
        nothing
    end
end
testconsume(source::SourceString, state::CharSetState) = first(source) ∈ state.charset

"""A memory state requiring repetition of its subject n times before continuing to its actual successors."""
mutable struct RepeatState <: AbstractState
    min::Int
    max::Int
    counter::Int
    subject::AbstractState
    successors::Set{AbstractState}
end
function RepeatState(subject::AbstractState, min::Integer, max::Integer)
    if max < min && max != 0
        throw(ArgumentError("max ($max) < min ($min)"))
    end
    inst = RepeatState(min, max, 0, subject, Set())
    link!(leaves(subject), inst)
    inst
end

function consume!(source::SourceString, state::RepeatState, ::StateMachine)
    state.counter += 1
    if state.counter < state.min
        return state.subject
    else
        if state.counter < state.max && testconsume(state.subject)
            return state.subject
        else
            state.counter = 0
            return state.successor
        end
    end
end
testconsume(source::SourceString, state::RepeatState) = min > 0 ? testconsume(source, state.subject) : testconsume(source, state.subject) || testconsume(source, successors(state))

"""The exit gateway state popping the last state from the FSM's memory stack."""
struct RuleLeaveState <: AbstractGatewayState
    rule::Symbol # Used to ensure the popped state is the expected one.
    returnstates::Dict{Int, Set{AbstractState}}
    returnids::Dict{AbstractState, Int}
end
RuleLeaveState(rule::Symbol) = RuleLeaveState(rule, Dict(), Dict())

function consume!(source::SourceString, state::RuleLeaveState, fsm::StateMachine)
    scope = pop!(fsm.scopes)
    if isstrict() && !isa(scope, RuleMemory) || scope.rule != state.rule
        throw(StateGraphError(state, fsm, "current scope is not a rule scope, or bears the wrong name"))
    end
    amendrule!(fsm, scope)
    state.returnstates[pop!(fsm.rulereturns)]
end
testconsume(source::SourceString, state::RuleLeaveState) = true

function addreturnjump(state::RuleLeaveState, returnto::AbstractState, nxretid::Threads.Atomic{Int})
    if haskey(state.returnids, returnto)
        return state.returnids[returnto]
    end
    
    state.returnids[returnto] = retid = Threads.atomic_add!(nxretid, 1)
    
    if !haskey(state.returnstates, retid)
        state.returnstates[retid] = Set()
    end
    
    push!(state.returnstates[retid], returnto)
    retid
end

successors(state::RuleLeaveState) = keys(state.returnids)
function replacesuccessor!(parent::RuleLeaveState, replaceme::AbstractState, ::Nothing)
    if !haskey(parent.returnids, replaceme)
        return
    end
    
    retid = parent.returnids[replaceme]
    
    delete!(parent.returnids, replaceme)
    delete!(parent.returnstates[retid], replaceme)
    
    parent
end
function replacesuccessor!(parent::RuleLeaveState, replaceme::AbstractState, replacewith::AbstractState)
    if !haskey(parent.returnids, replaceme)
        throw(ArgumentError("state is not a successor"))
    end
    
    retid = parent.returnids[replaceme]
    
    delete!(parent.returnids, replaceme)
    delete!(parent.returnstates[retid], replaceme)
    
    parent.returnids[replacewith] = retid
    push!(parent.returnstates[retid], replacewith)
    
    parent
end
function replacesuccessor!(parent::RuleLeaveState, replaceme::AbstractState, replacewith::Set{AbstractState})
    if !haskey(parent.returnids, replaceme)
        throw(ArgumentError("state is not a successor"))
    end
    
    retid = parent.returnids[replaceme]
    
    delete!(parent.returnids, replaceme)
    delete!(parent.returnstates[retid], replaceme)
    
    foreach(state->parent.returnids[state] = retid, replacewith)
    union!(parent.returnstates[retid], replacewith)
    
    parent
end
replacesuccessor!(parent::AbstractState, replaceme::RuleLeaveState, _) = error("Cannot replace RuleLeaveState without further changes to the graph")

"""The entrance gateway state pushing a new state onto the FSM's memory stack.
This state may also be a placeholder to be updated later. This may occur when the successors belong to different rules."""
struct RuleEnterState <: AbstractGatewayState
    rule::Symbol
    isplaceholder::Bool
    partner::RuleLeaveState
    successors::Set{AbstractState}
end
RuleEnterState(rule::Symbol, partner::RuleLeaveState) = RuleEnterState(rule, false, partner, Set())
RuleEnterState(partner::RuleLeaveState) = RuleEnterState(:undefined, true, partner, Set())

function consume!(source::SourceString, state::RuleEnterState, fsm::StateMachine)
    if state.isplaceholder
        push!(fsm.scopes, RuleMemory())
    else
        push!(fsm.scopes, RuleMemory(state.rule))
    end
    state.successors
end

"""Pre-rule-entrance state required to properly return to the correct state after a rule concludes."""
struct RuleCallState <: AbstractGatewayState
    returnid::Int
    rule::AbstractState
    
    RuleCallState(returnid::Integer, rule::RuleEnterState) = new(returnid, rule)
end

function consume!(::SourceString, state::RuleCallState, fsm::StateMachine)
    push!(fsm.rulereturns, state.returnid)
    successors(state)
end
testconsume(source::SourceString, state::RuleCallState) = testconsume(source, state.rule)

successors(state::RuleCallState) = (state.rule,)
replacesuccessor!(::RuleCallState, ::AbstractState, _) = error("Illegal operation - RuleCallState must not change its assigned rule")

"""An intermittent gateway state filtering the possible states of the current rule.
When in strict mode, the current state must not be final and must currently contain all listed rules."""
struct RuleUpdateState <: AbstractGatewayState
    rule::Symbol
    successors::Set{AbstractState}
end
RuleUpdateState(rule::Symbol) = RuleUpdateState(rule, Set())

function consume!(source::SourceString, state::RuleUpdateState, fsm::StateMachine)
    idx = findlast(scope->isa(scope, RuleMemory), fsm.scopes)
    if idx === nothing
        StateGraphError(state, fsm, "no rule scope found on stack for updating")
    end
    fsm.scopes[idx] = RuleMemory(state.rule)
    state.successors
end

"""The entrance gateway state pushing captures onto the FSM's memory stack."""
struct CaptureEnterState <: AbstractGatewayState
    successors::Set{AbstractState}
end
CaptureEnterState() = CaptureEnterState(Set())

function consume!(source::SourceString, state::CaptureEnterState, fsm::StateMachine)
    push!(fsm.scopes, CaptureMemory())
    state.successors
end

"""An intermittent gateway state dropping the current capture scope.
Throws a StateGraphError if the current scope is not a capture scope."""
struct CaptureDropState <: AbstractGatewayState
    successors::Set{AbstractState}
end
CaptureDropState() = CaptureDropState(Set())

function consume!(source::SourceString, state::CaptureDropState, fsm::StateMachine)
    scope = pop!(fsm.scopes)
    if isstrict() && !isa(scope, CaptureMemory)
        throw(StateGraphError(state, fsm, "current scope to drop is not a capture scope"))
    end
    state.successors
end

"""The exit gateway state popping captures from the FSM's memory stack."""
struct CaptureLeaveState <: AbstractGatewayState
    successors::Set{AbstractState}
end
CaptureLeaveState() = CaptureLeaveState(Set())

function consume!(source::SourceString, state::CaptureLeaveState, fsm::StateMachine)
    scope = pop!(fsm.scopes)
    if isstrict() && !isa(scope, CaptureMemory)
        throw(StateGraphError(state, fsm, "current scope is not a capture scope"))
    end
    amendcapture!(fsm, scope)
    state.successors
end


# State copying & deepcopying
# Regular copying always deep-copies "subjects", e.g. of OptionsState or RepeatState.
# Deep-copying also deep-copies successor state.
Base.copy(state::VanityState)    = VanityState(copy(state.successors))
Base.copy(state::StaticState)    = StaticState(state.static, copy(state.successors))
Base.copy(state::CharSetState)   = CharSetState(state.charset, copy(state.successors))
Base.copy(state::RepeatState)    = RepeatState(state.min, state.max, state.counter, deepcopy(state.subject), copy(state.successors))
Base.copy(state::RuleEnterState) = RuleEnterState(state.rule, state.isplaceholder, copy(state.successors))
Base.copy(state::T) where {T<:Union{RuleUpdateState, RuleLeaveState}} = T(state.rule, copy(state.successors))
Base.copy(state::T) where {T<:Union{CaptureEnterState, CaptureDropState, CaptureLeaveState}} = T(copy(state.successors))
Base.deepcopy(state::VanityState)    = VanityState(deepcopy(state.successors))
Base.deepcopy(state::StaticState)    = StaticState(state.static, deepcopy(state.successors))
Base.deepcopy(state::CharSetState)   = CharSetState(state.charset, deepcopy(state.successors))
Base.deepcopy(state::RepeatState)    = RepeatState(state.min, state.max, state.counter, deepcopy(state.subject), deepcopy(state.successors))
Base.deepcopy(state::RuleEnterState) = RuleEnterState(state.rule, state.isplaceholder, deepcopy(state.successors))
Base.deepcopy(state::T) where {T<:Union{RuleUpdateState, RuleLeaveState}} = T(state.rule, deepcopy(state.successors))
Base.deepcopy(state::T) where {T<:Union{CaptureEnterState, CaptureDropState, CaptureLeaveState}} = T(deepcopy(state.successors))
