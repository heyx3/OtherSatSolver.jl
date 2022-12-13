"Specific data gleaned from a `Cookbook`, using a specific subset of its alternative recipes."
struct GameSession
    available_recipes::Vector{Recipe}
    recipes_by_input::Dict{Item, Set{Recipe}}
    recipes_by_output::Dict{Item, Set{Recipe}}
    processed_items::Set{Item} # Items that aren't "raw"
    cookbook::Cookbook
end

# Do hashing and equality based on values, not references.
# This makes testing much easier.
Base.hash(g::GameSession, u::UInt) = hash(
    hash.(tuple((getfield(g, f) for f in fieldnames(GameSession))...)),
    u
)
Base.:(==)(a::GameSession, b::GameSession) = all(tuple((
    getfield(a, f) == getfield(b, f)
      for f in fieldnames(GameSession)
)...))


"Sets up a `GameSession` using the given `Cookbook` and set of alternative recipes."
function GameSession(c::Cookbook, alternative_recipe_indices)::DataCache
    # Get all available recipes.
    available_recipes = collect(c.main_recipes)
    append!(available_recipes,
            (c.alternative_recipes[i] for i in alternative_recipe_indices))

    # Pull data from the recipes.
    processed_items = Set{Item}()
    recipes_by_input = Dict{Item, Set{Recipe}}()
    recipes_by_output = Dict{Item, Set{Recipe}}()
    for recipe in available_recipes
        for (data_dict, session_dict) in [(recipe.inputs, recipes_by_input),
                                          (recipe.outputs, recipes_by_output)]
            for (ingredient, count) in data_dict
                push!(processed_items, ingredient)
                # Add an entry to the correct recipe lookup.
                recipe_set = get!(() -> Set{Recipe}(), # (create if not exists)
                                  session_dict, ingredient)
                push!(recipe_set, recipe)
            end
        end
    end

    return DataCache(available_recipes,
                     recipes_by_input, recipes_by_output,
                     processed_items,
                     cookbook)
end


"Serializes the subset of alternative recipes used in some specific `GameSession`."
write_game_session(alternative_recipe_indices)::AbstractString = sprint(io -> write_game_session(io, alternative_recipe_indices))
write_game_session(io::IO, alternative_recipe_indices) = join(io, alternative_recipe_indices, ',')

"Deserializes the subset of alternative recipes used in some specific `GameSession`."
read_game_session(io::IO)::Vector{Int} = read_game_session(read(String, io))
read_game_session(str::AbstractString)::Vector{Int} = parse.(Ref(Int), split(str, ','))