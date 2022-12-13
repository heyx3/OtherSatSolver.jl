# Move the process to this file's directory.
cd(@__DIR__)

# Activate, compile, and load this project.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using OtherSatSolver

# Load the cookbook.
const COOKBOOK_NAME = "Satisfactory.json"
println("Reading cookbook (", COOKBOOK_NAME, ")...")
if !isfile(COOKBOOK_NAME)
    error("Couldn't find the game rules. Expected to see '", COOKBOOK_NAME, "'")
end
cookbook_str = open(io -> read(io, String), COOKBOOK_NAME)
println("\tParsing cookbook...")
const COOKBOOK = parse_cookbook_json(cookbook_str)
println("\tFinished!")

