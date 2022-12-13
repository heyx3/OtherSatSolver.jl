# Activate the testing environment correctly,
#    as a layer on top of the project environment.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
insert!(LOAD_PATH, 1, @__DIR__)

# Run.
include("runtests.jl")