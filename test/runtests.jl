using Test, CycleSolver

include("equations.test.jl")

@testset "DocTests for CycleSolver" begin
    doctest(CycleSolver; manual = false)
end
