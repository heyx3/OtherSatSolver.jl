# Activate the testing environment correctly,
#    as a layer on top of the project environment.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
insert!(LOAD_PATH, 1, @__DIR__)

# Enable debug-level logging.
if "-debug" in ARGS
    using Logging
    Base.global_logger(ConsoleLogger(stderr, Logging.Debug))
end

# Run.
include("runtests.jl")