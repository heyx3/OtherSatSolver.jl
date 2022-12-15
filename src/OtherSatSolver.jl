module OtherSatSolver

using Random, JSON3, Printf

const Optional{T} = Union{T, Nothing}
@inline exists(x) = !isnothing(x) && !ismissing(x)

include("parsing.jl")
include("data.jl")
include("cookbook.jl")
include("game-session.jl")
include("factory-floor.jl")

include("factory-overview.jl")

include("printing.jl")

export parse_rational, load_json_number, SNumber,
       Item, Building, Recipe,
       recipes_per_minute, input_per_minute, output_per_minute,
       Cookbook, parse_cookbook_json,
       GameSession, write_game_session, read_game_session,
       FactoryFloor, parse_factory_floor_json,
       FactoryOverview, solve,
       print_nice, print_building

end # module
