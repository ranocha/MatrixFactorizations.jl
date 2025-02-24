using MatrixFactorizations, LinearAlgebra, Random, ArrayLayouts, Test
using LinearAlgebra: BlasComplex, BlasFloat, BlasReal, rmul!, lmul!, require_one_based_indexing, checksquare
using MatrixFactorizations: QRCompactWYQLayout, AbstractQtype

struct MyMatrix <: LayoutMatrix{Float64}
    A::Matrix{Float64}
end

Base.getindex(A::MyMatrix, k::Int, j::Int) = A.A[k,j]
Base.setindex!(A::MyMatrix, v, k::Int, j::Int) = setindex!(A.A, v, k, j)
Base.size(A::MyMatrix) = size(A.A)
Base.strides(A::MyMatrix) = strides(A.A)
Base.unsafe_convert(::Type{Ptr{T}}, A::MyMatrix) where T = Base.unsafe_convert(Ptr{T}, A.A)
MemoryLayout(::Type{MyMatrix}) = DenseColumnMajor()

struct MyVector <: LayoutVector{Float64}
    A::Vector{Float64}
end

Base.getindex(A::MyVector, k::Int) = A.A[k]
Base.setindex!(A::MyVector, v, k::Int) = setindex!(A.A, v, k)
Base.size(A::MyVector) = size(A.A)
Base.strides(A::MyVector) = strides(A.A)
Base.unsafe_convert(::Type{Ptr{T}}, A::MyVector) where T = Base.unsafe_convert(Ptr{T}, A.A)
MemoryLayout(::Type{MyVector}) = DenseColumnMajor()

include("test_ul.jl")

n = 10

# Split n into 2 parts for tests needing two matrices
n1 = div(n, 2)
n2 = 2*n1

Random.seed!(1234321)

areal = randn(n,n)/2
aimg  = randn(n,n)/2
a2real = randn(n,n)/2
a2img  = randn(n,n)/2
breal = randn(n,2)/2
bimg  = randn(n,2)/2

# helper functions to unambiguously recover explicit forms of an implicit QL Q
squareQ(Q::LinearAlgebra.AbstractQ) = (sq = size(Q.factors, 1); lmul!(Q, Matrix{eltype(Q)}(I, sq, sq)))
rectangularQ(Q::LinearAlgebra.AbstractQ) = Matrix(Q) # convert(Array, Q)

@testset "QR" begin
    @testset for eltya in (Float32, Float64, ComplexF32, ComplexF64, BigFloat, Int)
        raw_a = eltya == Int ? rand(1:7, n, n) : convert(Matrix{eltya}, eltya <: Complex ? complex.(areal, aimg) : areal)
        raw_a2 = eltya == Int ? rand(1:7, n, n) : convert(Matrix{eltya}, eltya <: Complex ? complex.(a2real, a2img) : a2real)
        asym = raw_a' + raw_a                  # symmetric indefinite
        apd  = raw_a' * raw_a                 # symmetric positive-definite
        ε = εa = eps(abs(float(one(eltya))))

        @testset for eltyb in (Float32, Float64, ComplexF32, ComplexF64, Int)
            raw_b = eltyb == Int ? rand(1:5, n, 2) : convert(Matrix{eltyb}, eltyb <: Complex ? complex.(breal, bimg) : breal)
            εb = eps(abs(float(one(eltyb))))
            ε = max(εa, εb)
            tab = promote_type(eltya, eltyb)

            @testset "QR decomposition of a Number" begin
                α = rand(eltyb)
                aα = fill(α, 1, 1)
                @test qrunblocked(α).Q * qrunblocked(α).R ≈ qrunblocked(aα).Q * qrunblocked(aα).R
                @test abs(qrunblocked(α).Q[1,1]) ≈ one(eltyb)
            end

            for (a, b) in ((raw_a, raw_b),
                (view(raw_a, 1:n-1, 1:n-1), view(raw_b, 1:n-1, 1)))
                a_1 = size(a, 1)
                @testset "QR decomposition (without pivoting)" begin
                    qra   = @inferred qrunblocked(a)
                    @inferred qrunblocked(a)
                    q, r = qra.Q, qra.R
                    @test_throws ErrorException qra.Z
                    @test q[1,1] ≈ Matrix(q)[1,1]
                    @test q[1:2,1:2] ≈ Matrix(q)[1:2,1:2]
                    @test q'*squareQ(q) ≈ Matrix(I, a_1, a_1)
                    @test q*squareQ(q)' ≈ Matrix(I, a_1, a_1)
                    @test q'*Matrix(1.0I, a_1, a_1)' ≈ squareQ(q)'
                    @test squareQ(q)'q ≈ Matrix(I, a_1, a_1)
                    @test Matrix(1.0I, a_1, a_1)'q' ≈ squareQ(q)'
                    @test q*r ≈ a
                    @test a*(qra\b) ≈ b atol=5000ε
                    @test Array(qra) ≈ a
                    sq = size(q.factors, 2)
                    @test *(Matrix{eltyb}(I, sq, sq), adjoint(q)) * squareQ(q) ≈ Matrix(I, sq, sq) atol=5000ε
                    if eltya != Int
                        if VERSION < v"1.10-"
                            @test Matrix{eltyb}(I, a_1, a_1)*q ≈ convert(AbstractMatrix{tab}, q)
                        else
                            @test Matrix{eltyb}(I, a_1, a_1)*q ≈ squareQ(convert(LinearAlgebra.AbstractQ{tab}, q))
                        end
                        ac = copy(a)
                        @test qrunblocked!(a[:, 1:5])\b == qrunblocked!(view(ac, :, 1:5))\b
                    end
                    qrstring = sprint((t, s) -> show(t, "text/plain", s), qra)
                    rstring  = sprint((t, s) -> show(t, "text/plain", s), r)
                    qstring  = sprint((t, s) -> show(t, "text/plain", s), q)
                    @test qrstring == "$(summary(qra))\nQ factor:\n$qstring\nR factor:\n$rstring"
                end
                @testset "Thin QR decomposition (without pivoting)" begin
                    qra   = @inferred qrunblocked(a[:, 1:n1], Val(false))
                    @inferred qrunblocked(a[:, 1:n1], Val(false))
                    q,r   = qra.Q, qra.R
                    @test_throws ErrorException qra.Z
                    @test q[1,1] ≈ Matrix(q)[1,1]
                    @test q[1:2,1:2] ≈ Matrix(q)[1:2,1:2]
                    @test q'*squareQ(q) ≈ Matrix(I, a_1, a_1)
                    @test q'*rectangularQ(q) ≈ Matrix(I, a_1, n1)
                    @test q*r ≈ a[:, 1:n1]
                    @test q*b[1:n1] ≈ rectangularQ(q)*b[1:n1] atol=100ε
                    @test q*b ≈ squareQ(q)*b atol=100ε
                    @test_throws DimensionMismatch q*b[1:n1 + 1]
                    @test_throws DimensionMismatch b[1:n1 + 1]*q'
                    sq = size(q.factors, 1)
                    @test *(LowerTriangular(Matrix{eltyb}(I, sq, sq)), adjoint(q))*squareQ(q) ≈ Matrix(I, a_1, a_1) atol=5000ε
                    if eltya != Int
                        if VERSION < v"1.10-"
                            @test Matrix{eltyb}(I, a_1, a_1)*q ≈ convert(AbstractMatrix{tab}, q)
                        else
                            @test Matrix{eltyb}(I, a_1, a_1)*q ≈ squareQ(convert(LinearAlgebra.AbstractQ{tab}, q))
                        end
                    end
                end
            end
            if eltya != Int
                @testset "Matmul with QR factorizations" begin
                    a = raw_a

                    qra = qrunblocked(a[:,1:n1], Val(false))
                    q, r = qra.Q, qra.R
                    @test q[1,1] ≈ Matrix(q)[1,1]
                    @test q[1:2,1:2] ≈ Matrix(q)[1:2,1:2]
                    @test rmul!(copy(squareQ(q)'), q) ≈ Matrix(I, n, n)
                    @test_throws DimensionMismatch rmul!(Matrix{eltya}(I, n+1, n+1),q)
                    @test rmul!(squareQ(q), adjoint(q)) ≈ Matrix(I, n, n)
                    @test_throws DimensionMismatch rmul!(Matrix{eltya}(I, n+1, n+1),adjoint(q))
                    @test_throws ErrorException size(q,-1)
                    @test_throws DimensionMismatch q * Matrix{Int8}(I, n+4, n+4)
                end
            end
        end
    end 

    @testset "transpose errors" begin
        @test_throws MethodError transpose(qrunblocked(randn(3,3)))
        @test_throws MethodError adjoint(qrunblocked(randn(3,3)))
        @test_throws MethodError transpose(qrunblocked(randn(3,3), Val(false)))
        @test_throws MethodError adjoint(qrunblocked(randn(3,3), Val(false)))
        @test_throws MethodError transpose(qrunblocked(big.(randn(3,3))))
        @test_throws MethodError adjoint(qrunblocked(big.(randn(3,3))))
    end

    @testset "Issue 7304" begin
        A = [-√.5 -√.5; -√.5 √.5]
        Q = rectangularQ(qrunblocked(A).Q)
        @test norm(A-Q) < eps()
    end

    @testset "qrunblocked on AbstractVector" begin
        vl = [3.0, 4.0]
        for Tl in (Float32, Float64)
            for T in (Tl, Complex{Tl})
                v = convert(Vector{T}, vl)
                nv, nm = qrunblocked(v)
                @test nv*nm ≈ v
            end
        end
    end

    @testset "Issue 24589. Promotion of rational matrices" begin
        A = rand(1//1:5//5, 4,3)
        @test Matrix(first(qrunblocked(A))) == Matrix(first(qrunblocked(float(A))))
    end

    @testset "Issue Test Factorization fallbacks for rectangular problems" begin
        A  = randn(3,2)
        Ac = copy(A')
        b  = randn(3)
        b0 = copy(b)
        c  = randn(2)
        @test A \b ≈ ldiv!(c, qrunblocked(A ), b)
    end

    @testset "Wide QR" begin
        A = randn(3,5)
        Q,R = qrunblocked(A)
        @test Q*R ≈ A
    end

    @testset "lmul!/rmul!" begin
        A = randn(100,100)
        Q,R = qrunblocked(A)
        x = randn(100)
        b = randn(100,2)
        @test lmul!(Q, copy(x)) ≈ Matrix(Q)*x
        @test lmul!(Q, copy(b)) ≈ Matrix(Q)*b
        @test lmul!(Q', copy(x)) ≈ Matrix(Q)'*x
        @test lmul!(Q', copy(b)) ≈ Matrix(Q)'*b
        c = randn(2,100)
        @test rmul!(copy(c), Q) ≈ c*Matrix(Q)
        @test rmul!(copy(c), Q') ≈ c*Matrix(Q')

        A = randn(100,103)
        Q,R = qrunblocked(A)
        x = randn(100)
        b = randn(100,2)
        @test lmul!(Q, copy(x)) ≈ Matrix(Q)*x
        @test lmul!(Q, copy(b)) ≈ Matrix(Q)*b
        @test lmul!(Q', copy(x)) ≈ Matrix(Q)'*x
        @test lmul!(Q', copy(b)) ≈ Matrix(Q)'*b
        c = randn(2,100)
        @test rmul!(copy(c), Q) ≈ c*Matrix(Q)
        @test rmul!(copy(c), Q') ≈ c*Matrix(Q')
    end

    @testset "LinearAlgebra.QR -> MatrixFactorizations.QR" begin
        A = randn(10,10)
        F̃ = LinearAlgebra.qrfactUnblocked!(copy(A))
        F = MatrixFactorizations.QR(F̃)
        Q,R = F
        @test Q*R ≈ A
        Q̃,_ = F̃
        @test MatrixFactorizations.QRPackedQ(Q̃)*R ≈ A
    end

    @testset "Ambiguity" begin
        A = randn(10,10)
        b = rand(10)
        B = randn(10,3)
        F = qrunblocked(A)
        @test ldiv!(F, MyVector(copy(b))) ≈ A \ b
        @test ldiv!(F, MyMatrix(copy(B))) ≈ A \ B
    end
end

@testset "QL" begin
    @testset "Compare with QR" begin
        n = 10
        A = randn(n,n)
        Q̃, R = @inferred qr(A[end:-1:1,end:-1:1])
        Q, L = @inferred ql(A)
        Q̄, L̄ = MatrixFactorizations.generic_qlfactUnblocked!(copy(A))
        @test Q.factors ≈ Q̄.factors
        @test Q.τ ≈ Q̄.τ
        @test R[end:-1:1,end:-1:1] ≈ L ≈ L̄
        @test Q̃[end:-1:1,end:-1:1] ≈ Matrix(Q) ≈ Matrix(Q̄)
        @test copy(Q) ≡ Q

        A = randn(n,n+2)
        Q̃, R = qr(A[end:-1:1,end:-1:1])
        Q, L = ql(A)
        Q̄, L̄ = MatrixFactorizations.generic_qlfactUnblocked!(copy(A))
        @test Q.factors ≈ Q̄.factors
        @test Q.τ ≈ Q̄.τ
        @test R[end:-1:1,end:-1:1] ≈ L ≈ L̄
        @test Q̃[end:-1:1,end:-1:1] ≈ Matrix(Q) ≈ Matrix(Q̄)

        A = randn(n+2,n)
        Q̃, R = qr(A[end:-1:1,end:-1:1])
        Q, L = ql(A)
        Q̄, L̄ = MatrixFactorizations.generic_qlfactUnblocked!(copy(A))
        @test Q.factors ≈ Q̄.factors
        @test Q.τ ≈ Q̄.τ
        @test R[end:-1:1,end:-1:1] ≈ L ≈ L̄
        @test Q̃[end:-1:1,end:-1:1] ≈ squareQ(Q) ≈ squareQ(Q̄)
    end

    @testset for eltya in (Float32, Float64, ComplexF32, ComplexF64, BigFloat, Int)
        raw_a = eltya == Int ? rand(1:7, n, n) : convert(Matrix{eltya}, eltya <: Complex ? complex.(areal, aimg) : areal)
        raw_a2 = eltya == Int ? rand(1:7, n, n) : convert(Matrix{eltya}, eltya <: Complex ? complex.(a2real, a2img) : a2real)
        asym = raw_a' + raw_a                  # symmetric indefinite
        apd  = raw_a' * raw_a                 # symmetric positive-definite
        ε = εa = eps(abs(float(one(eltya))))

        @testset for eltyb in (Float32, Float64, ComplexF32, ComplexF64, Int)
            raw_b = eltyb == Int ? rand(1:5, n, 2) : convert(Matrix{eltyb}, eltyb <: Complex ? complex.(breal, bimg) : breal)
            εb = eps(abs(float(one(eltyb))))
            ε = max(εa, εb)
            tab = promote_type(eltya, eltyb)

            @testset "QL decomposition of a Number" begin
                α = rand(eltyb)
                aα = fill(α, 1, 1)
                @test ql(α).Q * ql(α).L ≈ ql(aα).Q * ql(aα).L
                @test abs(ql(α).Q[1,1]) ≈ one(eltyb)
            end

            for (a, b) in ((raw_a, raw_b),
                (view(raw_a, 1:n-1, 1:n-1), view(raw_b, 1:n-1, 1)))
                a_1 = size(a, 1)
                @testset "QL decomposition (without pivoting)" begin
                    qla   = @inferred ql(a)
                    @inferred ql(a)
                    q, l  = qla.Q, qla.L
                    @test_throws ErrorException qla.Z
                    @test q'*squareQ(q) ≈ Matrix(I, a_1, a_1)
                    @test q*squareQ(q)' ≈ Matrix(I, a_1, a_1)
                    @test q'*Matrix(1.0I, a_1, a_1)' ≈ squareQ(q)'
                    @test squareQ(q)'q ≈ Matrix(I, a_1, a_1)
                    @test Matrix(1.0I, a_1, a_1)'q' ≈ squareQ(q)'
                    @test q*l ≈ a
                    @test a*(qla\b) ≈ b atol=5000ε
                    @test Array(qla) ≈ a
                    sq = size(q.factors, 2)
                    @test *(Matrix{eltyb}(I, sq, sq), adjoint(q)) * squareQ(q) ≈ Matrix(I, sq, sq) atol=5000ε
                    if eltya != Int
                        @test Matrix{eltyb}(I, a_1, a_1)*q ≈ squareQ(convert(AbstractQtype{tab}, q))
                        ac = copy(a)
                        @test ql!(a[:, 1:5])\b == ql!(view(ac, :, 1:5))\b
                    end
                    qlstring = sprint((t, s) -> show(t, "text/plain", s), qla)
                    rstring  = sprint((t, s) -> show(t, "text/plain", s), l)
                    qstring  = sprint((t, s) -> show(t, "text/plain", s), q)
                    @test qlstring == "$(summary(qla))\nQ factor:\n$qstring\nL factor:\n$rstring"
                end
                @testset "Thin QL decomposition (without pivoting)" begin
                    qla   = @inferred ql(a[:, 1:n1], Val(false))
                    @inferred ql(a[:, 1:n1], Val(false))
                    q,l   = qla.Q, qla.L
                    @test_throws ErrorException qla.Z
                    @test q'*squareQ(q) ≈ Matrix(I, a_1, a_1)
                    @test q'*rectangularQ(q) ≈ Matrix(I, a_1, n1)
                    @test q*l ≈ a[:, 1:n1]
                    @test q*b[1:n1] ≈ rectangularQ(q)*b[1:n1] atol=100ε
                    @test q*b ≈ squareQ(q)*b atol=100ε
                    @test_throws DimensionMismatch q*b[1:n1 + 1]
                    @test_throws DimensionMismatch b[1:n1 + 1]*q'
                    sq = size(q.factors, 1)
                    @test *(LowerTriangular(Matrix{eltyb}(I, sq, sq)), adjoint(q))*squareQ(q) ≈ Matrix(I, a_1, a_1) atol=5000ε
                    if eltya != Int
                        if VERSION < v"1.10-"
                            @test Matrix{eltyb}(I, a_1, a_1)*q ≈ convert(AbstractMatrix{tab}, q)
                        else
                            @test Matrix{eltyb}(I, a_1, a_1)*q ≈ squareQ(convert(LinearAlgebra.AbstractQ{tab}, q))
                        end
                    end
                end
            end
            if eltya != Int
                @testset "Matmul with QL factorizations" begin
                    a = raw_a

                    qla = ql(a[:,1:n1], Val(false))
                    q, l = qla.Q, qla.L
                    @test rmul!(copy(squareQ(q)'), q) ≈ Matrix(I, n, n)
                    @test_throws DimensionMismatch rmul!(Matrix{eltya}(I, n+1, n+1),q)
                    @test rmul!(squareQ(q), adjoint(q)) ≈ Matrix(I, n, n)
                    @test_throws DimensionMismatch rmul!(Matrix{eltya}(I, n+1, n+1),adjoint(q))
                    @test_throws ErrorException size(q,-1)
                    @test_throws DimensionMismatch q * Matrix{Int8}(I, n+4, n+4)
                end
            end
        end
    end

    @testset "transpose errors" begin
        @test_throws MethodError transpose(ql(randn(3,3)))
        @test_throws MethodError adjoint(ql(randn(3,3)))
        @test_throws MethodError transpose(ql(randn(3,3), Val(false)))
        @test_throws MethodError adjoint(ql(randn(3,3), Val(false)))
        @test_throws MethodError transpose(ql(big.(randn(3,3))))
        @test_throws MethodError adjoint(ql(big.(randn(3,3))))
    end

    @testset "Issue 7304" begin
        A = [-√.5 -√.5; -√.5 √.5]
        Q = rectangularQ(ql(A).Q)
        @test norm(A+Q) < eps()
    end

    @testset "ql on AbstractVector" begin
        vl = [3.0, 4.0]
        for Tl in (Float32, Float64)
            for T in (Tl, Complex{Tl})
                v = convert(Vector{T}, vl)
                nv, nm = ql(v)
                @test nv*nm ≈ v
            end
        end
    end

    @testset "Issue 24589. Promotion of rational matrices" begin
        A = rand(1//1:5//5, 4,3)
        @test Matrix(first(ql(A))) == Matrix(first(ql(float(A))))
    end

    @testset "Issue Test Factorization fallbacks for rectangular problems" begin
        A  = randn(3,2)
        Ac = copy(A')
        b  = randn(3)
        b0 = copy(b)
        c  = randn(2)
        @test_broken A \b ≈ ldiv!(c, ql(A ), b)
    end

    @testset "Wide QL" begin
        A = randn(3,5)
        Q,L = ql(A)
        @test Q*L ≈ A
    end

    @testset "lmul!/rmul!" begin
        A = randn(100,100)
        Q,L = ql(A)
        x = randn(100)
        b = randn(100,2)
        @test lmul!(Q, copy(x)) ≈ Matrix(Q)*x
        @test lmul!(Q, copy(b)) ≈ Matrix(Q)*b
        @test lmul!(Q', copy(x)) ≈ Matrix(Q)'*x
        @test lmul!(Q', copy(b)) ≈ Matrix(Q)'*b
        c = randn(2,100)
        @test rmul!(copy(c), Q) ≈ c*Matrix(Q)
        @test rmul!(copy(c), Q') ≈ c*Matrix(Q')

        A = randn(100,103)
        Q,L = ql(A)
        x = randn(100)
        b = randn(100,2)
        @test lmul!(Q, copy(x)) ≈ Matrix(Q)*x
        @test lmul!(Q, copy(b)) ≈ Matrix(Q)*b
        @test lmul!(Q', copy(x)) ≈ Matrix(Q)'*x
        @test lmul!(Q', copy(b)) ≈ Matrix(Q)'*b
        c = randn(2,100)
        @test rmul!(copy(c), Q) ≈ c*Matrix(Q)
        @test rmul!(copy(c), Q') ≈ c*Matrix(Q')
    end

    @testset "Q * Tri" begin
        A = randn(5,5)
        Q,L = ql(A)
        @test Q * LowerTriangular(L) ≈ A
        @test LowerTriangular(L) * Q ≈ L * Q
        @test Q' * LowerTriangular(L) ≈ Q' * L
        @test LowerTriangular(L)' * Q' ≈ A'
    end
end

include("test_rq.jl")

# choleskyinv.jl
@testset "choleskyinv" begin
    etol = 1e-9
    n = 20
	# real matrices
    A = randn(n, n)
    P = A*A'
    Pi = inv(P)
    C = choleskyinv!(copy(Matrix(P)))
	@test(norm(C.c.L*C.c.U-P)/√n < etol)
	@test(norm(C.ci.U*C.ci.L-Pi)/√n < etol)
    C = choleskyinv(P)
	@test(norm(C.c.L*C.c.U-P)/√n < etol)
	@test(norm(C.ci.U*C.ci.L-Pi)/√n < etol)
    
	# repeat the test for complex matrices
    A=randn(ComplexF64, n, n)
    P=A*A'
    Pi=inv(P)
	C=choleskyinv!(copy(Matrix(P)))
	@test(norm(C.c.L*C.c.U-P)/√n < etol)
	@test(norm(C.ci.U*C.ci.L-Pi)/√n < 4etol)
    C = choleskyinv(P)
	@test(norm(C.c.L*C.c.U-P)/√n < etol)
	@test(norm(C.ci.U*C.ci.L-Pi)/√n < 4etol)
end


include("test_polar.jl")
