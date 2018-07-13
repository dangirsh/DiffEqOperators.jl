"""
    DiffEqScalar(val[; update_func])

Represents a time-dependent scalar/scaling operator. The update function
is called by `update_coefficients!` and is assumed to have the following
signature:

    update_func(oldval,u,p,t) -> newval

You can also use `setval!(α,val)` to bypass the `update_coefficients!`
interface and directly mutate the scalar's value.
"""
mutable struct DiffEqScalar{T<:Number,F} <: AbstractDiffEqLinearOperator{T}
  val::T
  update_func::F
  DiffEqScalar(val::T; update_func=DEFAULT_UPDATE_FUNC) where {T} =
    new{T,typeof(update_func)}(val, update_func)
end

update_coefficients!(α::DiffEqScalar,u,p,t) = (α.val = α.update_func(α.val,u,p,t); α)
setval!(α::DiffEqScalar, val) = (α.val = val; α)
is_constant(α::DiffEqScalar) = α.update_func == DEFAULT_UPDATE_FUNC

for op in (:*, :/, :\)
  @eval $op(α::DiffEqScalar{T,F}, x::AbstractVecOrMat{T}) where {T,F} = $op(α.val, x)
  @eval $op(x::AbstractVecOrMat{T}, α::DiffEqScalar{T,F}) where {T,F} = $op(x, α.val)
end
lmul!(α::DiffEqScalar{T,F}, B::AbstractVecOrMat{T}) where {T,F} = lmul!(α.val, B)
rmul!(B::AbstractVecOrMat{T}, α::DiffEqScalar{T,F}) where {T,F} = rmul!(B, α.val)
mul!(Y::AbstractVecOrMat{T}, α::DiffEqScalar{T,F},
  B::AbstractVecOrMat{T}) where {T,F} = mul!(Y, α.val, B)
axpy!(α::DiffEqScalar{T,F}, X::AbstractVecOrMat{T},
  Y::AbstractVecOrMat{T}) where {T,F} = axpy!(α.val, X, Y)
Base.abs(α::DiffEqScalar) = abs(α.val)

(α::DiffEqScalar)(u,p,t) = (update_coefficients!(α,u,p,t); α.val * u)
(α::DiffEqScalar)(du,u,p,t) = (update_coefficients!(α,u,p,t); @. du = α.val * u)

"""
    DiffEqArrayOperator(A[; update_func])

Represents a time-dependent linear operator given by an AbstractMatrix. The
update function is called by `update_coefficients!` and is assumed to have
the following signature:

    update_func(A::AbstractMatrix,u,p,t) -> [modifies A]

You can also use `setval!(α,A)` to bypass the `update_coefficients!` interface
and directly mutate the array's value.
"""
mutable struct DiffEqArrayOperator{T,AType<:AbstractMatrix{T},F} <: AbstractDiffEqLinearOperator{T}
  A::AType
  update_func::F
  DiffEqArrayOperator(A::AType; update_func=DEFAULT_UPDATE_FUNC) where {AType} = 
    new{eltype(A),AType,typeof(update_func)}(A, update_func)
end

update_coefficients!(L::DiffEqArrayOperator,u,p,t) = (L.update_func(L.A,u,p,t); L)
setval!(L::DiffEqArrayOperator, A) = (L.A = A; L)
is_constant(L::DiffEqArrayOperator) = L.update_func == DEFAULT_UPDATE_FUNC
(L::DiffEqArrayOperator)(u,p,t) = (update_coefficients!(L,u,p,t); L.A * u)
(L::DiffEqArrayOperator)(du,u,p,t) = (update_coefficients!(L,u,p,t); mul!(du, L.A, u))

# Forward operations that use the underlying array
convert(::Type{AbstractMatrix}, L::DiffEqArrayOperator) = L.A
for pred in (:isreal, :issymmetric, :ishermitian, :isposdef)
  @eval LinearAlgebra.$pred(L::DiffEqArrayOperator) = $pred(L.A)
end
size(L::DiffEqArrayOperator) = size(L.A)
size(L::DiffEqArrayOperator, m) = size(L.A, m)
opnorm(L::DiffEqArrayOperator, p::Real=2) = opnorm(L.A, p)
getindex(L::DiffEqArrayOperator, i::Int) = L.A[i]
getindex(L::DiffEqArrayOperator, I::Vararg{Int, N}) where {N} = L.A[I...]
setindex!(L::DiffEqArrayOperator, v, i::Int) = (L.A[i] = v)
setindex!(L::DiffEqArrayOperator, v, I::Vararg{Int, N}) where {N} = (L.A[I...] = v)
for op in (:*, :/, :\)
  @eval $op(L::DiffEqArrayOperator{T,AType,F}, x::AbstractVecOrMat{T}) where {T,AType,F} = $op(L.A, x)
  @eval $op(x::AbstractVecOrMat{T}, L::DiffEqArrayOperator{T,AType,F}) where {T,AType,F} = $op(x, L.A)
end
mul!(Y, L::DiffEqArrayOperator, B) = mul!(Y, L.A, B)
ldiv!(Y, L::DiffEqArrayOperator, B) = ldiv!(Y, L.A, B)

# Forward operations that use the full matrix
Matrix(L::DiffEqArrayOperator) = Matrix(L.A)
LinearAlgebra.exp(L::DiffEqArrayOperator) = exp(Matrix(L))

"""
    FactorizedDiffEqArrayOperator(F)

Like DiffEqArrayOperator, but stores a Factorization instead.

Supports left division and `ldiv!` when applied to an array.
"""
struct FactorizedDiffEqArrayOperator{T<:Number,FType<:Factorization{T}} <: AbstractDiffEqLinearOperator{T}
  F::FType
end

factorize(L::DiffEqArrayOperator) = FactorizedDiffEqArrayOperator(factorize(L.A))
for fact in (:lu, :lu!, :qr, :qr!, :chol, :chol!, :ldlt, :ldlt!,
  :bkfact, :bkfact!, :lq, :lq!, :svd, :svd!)
  @eval LinearAlgebra.$fact(L::DiffEqArrayOperator, args...) = FactorizedDiffEqArrayOperator($fact(L.A, args...))
end

Matrix(L::FactorizedDiffEqArrayOperator) = Matrix(L.F)
convert(::Type{AbstractMatrix}, L::FactorizedDiffEqArrayOperator) = convert(AbstractMatrix, L.F)
is_constant(::FactorizedDiffEqArrayOperator) = true
update_coefficients(L::FactorizedDiffEqArrayOperator,u,p,t) = L
size(L::FactorizedDiffEqArrayOperator, args...) = size(L.F, args...)
ldiv!(Y::AbstractVecOrMat, L::FactorizedDiffEqArrayOperator, B::AbstractVecOrMat) = ldiv!(Y, L.F, B)
\(L::FactorizedDiffEqArrayOperator, x::AbstractVecOrMat) = L.F \ x
