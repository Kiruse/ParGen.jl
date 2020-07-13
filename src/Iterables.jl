# Iterables microlibrary
# Copyright (c) Skye Cobile 2020 Germany
# SEE LICENSE IN LICENSE
# --------------------------------------
# A simple wrapper to distinguish iterable from non-iterable types, providing Base proxy methods for commonly used methods.

"""Create a simple proxy method forwarding Iterable types to their boxed type.
Assumes the ::Iterable is always first such that listing it in `args` is not needed."""
macro proxymethod(method, args...)
    esc(:(Base.$method(it::Iterable, $(args...)) = Base.$method(it.value, $(args...))))
end

struct Iterable{T, A}
    value::A
end
iterable(x::T) where T = isiterable(T) ? Iterable{eltype(x), typeof(x)}(x) : nothing
Base.eltype(::Iterable{T}) where T = T
@proxymethod iterate
@proxymethod iterate state
@proxymethod length
@proxymethod ndims
@proxymethod size
@proxymethod size n
@proxymethod axes
@proxymethod axes n
@proxymethod eachindex
@proxymethod stride k
@proxymethod strides
@proxymethod getindex idx
@proxymethod setindex! value idx
@proxymethod firstindex
@proxymethod firstindex d
@proxymethod lastindex
@proxymethod lastindex d


@generated function isiterable(::Type{T}) where T
    if !isempty(methods(iterate, Tuple{T}))
        :(true)
    else
        :(false)
    end
end
