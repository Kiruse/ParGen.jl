# Optimizers Submodule
# Copyright (c) Skye Cobile 2020 Germany
# SEE LICENSE IN LICENSE
# --------------------------------------
# Defines various `optimize` methods for each applicable type of state, partially depending on entire sequences of states.

struct Optimizer
    optimatches::Dict{Type{<:AbstractState}, Vector{AbstractOptiMatch}}
end
Optimizer() = Optimizer(Dict())

function pargenoptimizer()
    opti = Optimizer()
    rule!(opti, TypeSeqOptiMatch{Tuple{AbstractState, VanityState}}())
    rule!(opti, TypeSeqOptiMatch{Tuple{StaticState, StaticState}}())
    opti
end

function rule!(optimizer::Optimizer, optimatch::AbstractOptiMatch)
    T = firstapplicabletype(optimatch)
    if !haskey(optimizer.optimatches, T)
        optimizer.optimatches[T] = []
    end
    push!(optimizer.optimatches[T], optimatch)
    optimizer
end

Base.match(optimizer::Optimizer, states) = Base.match(optimizer, iterable(states))
Base.match(optimizer::Optimizer, states::Iterable{AbstractState}) = map(state->match(optimizer, state), states)
function Base.match(optimizer::Optimizer, state::S) where {S<:AbstractState}
    if haskey(optimizer.optimatches, S)
        for optimatch ∈ optimizer.optimatches[S]
            if (result = match(optimatch, state)) !== nothing
                return result
            end
        end
    end
    nothing
end

optimize(optimizer::Optimizer, fsm::StateMachine) = fsm.currstate = optimize(optimizer, fsm.currstate)
function optimize(optimizer::Optimizer, state::AbstractState)
    first = state
    while (optimized = dooptimize(optimizer, first)) !== nothing
        first = optimized
    end
    first
end

"""Do the actual optimization.
Only one optimization per execution must occur. This is ruled because this single optimization may trigger another
optimization on an ancestor node. Accordingly, optimizations must be designed in order to not cause an infinite loop.
The only exemption from the one-optimization rule is the starting state as obviously it has no ancestors."""
function dooptimize(optimizer::Optimizer, state::AbstractState)
    first = state
    while (optires = optimatch(optimizer, first)) !== nothing
        first = optimize(optires)
    end
    
    pending = NTuple{2, AbstractState}[] # Stores pairs of parents and states-to-test
    append!(pending, map(succ->(first, succ), collect(successors(first))))
    visited = Set{AbstractState}([state]) # Infinite loop prevention
    
    while !isempty(pending)
        parent, subject = splice!(pending, 1)
        if subject ∈ visited continue end
        
        optires = optimatch(optimizer, state)
        
        # Optimization found - terminate, return & reattempt another optimization from start
        if optires !== nothing
            replacesuccessor!(parent, subject, optimize(optires))
            return first
            
        # No optimization found - proceed with successors
        else
            push!(visited, subject)
            append!(pending, map(curr->(subject, curr), collect(successors(subject))))
        end
    end
    
    nothing
end

function optimatch(optimizer::Optimizer, state::T) where {T<:AbstractState}
    if !haskey(optimizer.optimatches, T)
        return nothing
    end
    
    for curr ∈ optimizer.optimatches[T]
        res = optimatch(curr, state)
        if res !== nothing
            return res
        end
    end
    nothing
end


struct TypeOptiMatch{S<:AbstractState} <: AbstractOptiMatch end
struct TypeOptiResult{S<:AbstractState} <: AbstractOptiResult
    state::S
    successors::Vector{AbstractState}
end
firstapplicabletype(::TypeOptiMatch{S}) where S = S
optimatch(::TypeOptiMatch{S}, state::S) where {S<:AbstractState} = TypeOptiResult(state, successors(state))


"""A sequence of nodes of a specific type, optionally enforcing linearity."""
struct TypeSeqOptiMatch{T<:Tuple{Vararg}, B} <: AbstractOptiMatch end
struct TypeSeqOptiResultRow
    states::Vector{AbstractState}
    successors::Set{AbstractState}
end
struct TypeSeqOptiResult{T<:Tuple{Vararg}, B} <: AbstractOptiResult
    results::Vector{TypeSeqOptiResultRow}
end
TypeSeqOptiMatch{T}() where T = TypeSeqOptiMatch{T, true}()
TypeSeqOptiResult{T}() where T = TypeSeqOptiResult{T}([])
TypeSeqOptiResultRow() = TypeSeqOptiResultRow([], [])
TypeSeqOptiResultRow(states) = TypeSeqOptiResultRow(states, [])

firstapplicabletype(seq::TypeSeqOptiMatch{T, B}) where {T<:Tuple{Vararg{<:AbstractState}}, B} = T.types[1]

"""TypeSeqOptiMatch recursive kickoff"""
optimatch(seq::TypeSeqOptiMatch{T}, state::S) where {S<:AbstractState, T<:Tuple{Type{S}, Vararg}} = optimatch!(TypeSeqOptiResult(), TypeSeqOptiResultRow(), collect(T.types), state)

"""Recursive TypeSeqOptiMatch for branching sequences"""
function optimatch!(res::TypeSeqOptiResult{T, true}, row::TypeSeqOptiResultRow, types, state::AbstractState) where T
    if isempty(types)
        throw(ArgumentError("no types provided"))
    end
    
    # Purpose of the algorithm
    if typeof(state) !== splice!(types, 1)
        return nothing
    end
    push!(row.states, state)
    
    # Successful termination condition
    if isempty(types)
        union!(row.successors, state.successors)
        push!(res.results, row)
    else
        # Unsuccessful termination condition
        if isempty(state.successors)
            return nothing
            
        # Sequential recursion
        elseif length(state.successors) == 1
            # Not needlessly copying the row saves some memory & performance
            optimatch!(res, row, types, first(state.successors))
            
        # Branching recursion
        else
            for successor ∈ state.successors
                optimatch!(res, copy(row), types, successor)
            end
        end
    end
    
    isempty(res.results) ? nothing : res
end

"""Sequential TypeSeqOptiMatch for non-branching sequences"""
function optimatch!(res::TypeSeqOptiResult{T, false}, row::TypeSeqOptiResultRow, types, state::AbstractState) where T
    if isempty(types)
        throw(ArgumentError("no types provided"))
    end
    
    curr = state
    while !isempty(types)
        if typeof(curr) !== splice!(types, 1)
            return nothing
        end
        push!(row.states, curr)
        
        if (!isempty(types) && isempty(state.successors)) || length(state.successors) > 1
            return nothing
        else
            curr = first(state.successors)
        end
    end
    
    union!(row.successors, curr.successors)
    push!(res.results, row)
    res
end

Base.copy(optires::TypeSeqOptiResultRow) = TypeSeqOptiResultRow(copy(optires.states), copy(optires.successors))

"""Optimize intermittent vanity state by removing it entirely.
Such a state is generated e.g. through `state(::OrConjunctionPattern)`."""
function optimize(optires::TypeSeqOptiResult{Tuple{<:AbstractState, VanityState}})
    parent, vanity = optires.subresults
    replacesuccessor!(parent, vanity, vanity.successors)
    parent
end

function optimize(optires::TypeSeqOptiResult{Tuple{StaticState, StaticState}, false})
    first, second = first(optires.results)
    StaticState(first.static * second.static, second.successors)
end


"""A simple graph matcher to detect multiple sequential similar states."""
struct RepeatOptiMatch <: AbstractOptiMatch
    subject::AbstractOptiMatch
end
struct RepeatOptiResult <: AbstractOptiResult
    subresults::Vector{AbstractOptiResult}
    count::Int
end

firstapplicabletype(rep::RepeatOptiMatch) = firstapplicabletype(rep.subject)
function optimatch(rep::RepeatOptiMatch, state::AbstractState)
    tmp = match(rep.subject, state)
    if tmp === nothing
        return nothing
    end
    
    results = AbstractOptiResult[]
    while currstate !== nothing && tmp !== nothing
        subresult, currstate = tmp
        push!(results, subresult)
        tmp = match(rep.subject, currstate)
    end
    RepeatOptiResult(results)
end
