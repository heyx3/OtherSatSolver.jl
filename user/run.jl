# Move the process to this file's directory.
cd(@__DIR__)

# Activate, compile, and load this project.
using Pkg
Pkg.activate("..")
using OtherSatSolver, JuMP

# Load the cookbook.
const COOKBOOK_NAME = "Satisfactory.cbk"
println("Reading cookbook (", COOKBOOK_NAME, ")...")
if !isfile(COOKBOOK_NAME)
    error("Couldn't find the game rules. Expected to see '", COOKBOOK_NAME, "'")
end
cookbook_str = open(io -> read(io, String), COOKBOOK_NAME)
println("\tParsing cookbook...")
const COOKBOOK = parse_cookbook_json(cookbook_str)
println("\tFinished!")

# Load the game session.
const GAME_SESSION_NAME = "SimpleGameSession.gs"
println("Reading game session (", GAME_SESSION_NAME, ")...")
game_session_str = open(io -> read(io, String), GAME_SESSION_NAME)
println("\tParsing session...")
const GAME_SESSION = GameSession(COOKBOOK, read_game_session(game_session_str))
println("\tFinished!")

# Load the factory floor.
const FACTORY_FLOOR_NAME = "SampleFactoryFloor.ff"
println("Reading factory floor (", FACTORY_FLOOR_NAME, ")...")
factory_floor_str = open(io -> read(io, String), FACTORY_FLOOR_NAME)
println("\tParsing factory floor...")
const FACTORY_FLOOR = parse_factory_floor_json(factory_floor_str, GAME_SESSION)
println("\tFinished!")

# Solve the factory floor.
println("Running the solver...")
const SOLVER_START_TIME = time()
factory_solution_log = sprint() do io::IO
    global factory_solution = solve(FACTORY_FLOOR, log_io=io)
end
const SOLVER_END_TIME = time()
const SOLVER_DURATION_SECONDS = (SOLVER_END_TIME - SOLVER_START_TIME)
if isnothing(factory_solution)
    println(":( Unable to solve it. Solver log is below:")
else
    println("Found a solution!\nFirst, the log:")
end
sleep(2)
println("\n\n>>>>>>>>>>>>>>>>>>>>")
println(factory_solution_log)
println("<<<<<<<<<<<<<<<<<<<<")
if !isnothing(factory_solution)
    println("\n\nNow the solution!")
    sleep(2)
    print(stdout, factory_solution, session=GAME_SESSION)
    println()
end