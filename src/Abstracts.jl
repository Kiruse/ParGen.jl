abstract type AbstractStateMachine end
abstract type AbstractState end
abstract type AbstractConcreteState <: AbstractState end
abstract type AbstractGatewayState  <: AbstractState end
abstract type AbstractVanityState   <: AbstractState end

abstract type AbstractParser end
abstract type AbstractPattern end

abstract type AbstractOptiMatch end
abstract type AbstractOptiResult end
Base.match(::Type{AbstractOptiMatch}, ::Any) = nothing
