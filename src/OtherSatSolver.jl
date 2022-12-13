module OtherSatSolver

using Random, JSON3, Printf

const Optional{T} = Union{T, Nothing}
@inline exists(x) = !isnothing(x)

include("parsing.jl")
include("data.jl")
include("cookbook.jl")
include("game-session.jl")

export parse_rational, SNumber,
       Item, Building, Recipe, Cookbook,
       parse_cookbook_json,
       GameSession, write_game_session, read_game_session

end # module
