# Move the process to this file's directory.
cd(@__DIR__)

# Activate, compile, and load this project.
using Pkg
Pkg.activate("..")
using OtherSatSolver

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
factory_solution_log = sprint() do io::IO
    global factory_solution = solve(FACTORY_FLOOR, io)
end
if isempty(factory_solution[2])
    println("Perfect solution!")
else
    print(":( An imperfect solution. The following items couldn't be solved: ")
    join(stdout, factory_solution[2], ", ")
    println()
    println("Partial solution is below:")
    # Give the user time to read before printing the partial solution:
    for _ in 1:3
        sleep(1)
        println('.')
    end
end
println("First, the log:")
sleep(2)
println("\n\n>>>>>>>>>>>>>>>>>>>>")
println(factory_solution_log)
println("<<<<<<<<<<<<<<<<<<<<")
println("\n\nNow the solution!")
sleep(2)
println(factory_solution[1])