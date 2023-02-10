"A specific set of desired outputs (and related parameters, like how much to use alternative recipes)."
struct FactoryFloor
    outputs_per_minute::Dict{Item, SNumber}

    # Incoming items that the factory can take as a given; it does not need to make/mine them.
    inputs_per_minute::Dict{Item, SNumber}

    # For each output item, how much weight to give to each of its recipes
    #    in 'game_session.recipes_by_output'.
    #TODO: Make this a parameter of `solve()`, not part of the floor.
    output_recipe_weights::Dict{Item, Vector{SNumber}}

    # A convenient reference to the game session this factory is being built within.
    game_session::GameSession
end

"
Creates a FactoryFloor, filling in some of the information gaps.
Any outputs which you didn't provide recipe-weights for
    will automatically pick one recipe to be weighted 100%.
Output weights are automatically normalized.
"
function FactoryFloor( session::GameSession,
                       outputs_per_minute::Dict{Item, SNumber}
                       ;
                       inputs_per_minute::Dict{Item, SNumber} = Dict{Item, SNumber}(),
                       recipe_weights::Dict{Item, Vector{SNumber}} = Dict{Item, Vector{SNumber}}()
                     )::FactoryFloor
    # Create a copy of the recipe weights for us to modify internally.
    recipe_weights = Dict(k=>copy(v) for (k,v) in recipe_weights)

    # Normalize the user-provided recipe weights.
    for item in collect(keys(recipe_weights))
        list = recipe_weights[item]
        list .//= sum(list)
    end

    # Fill in any missing recipe weights.
    for item in session.processed_items
        if !haskey(recipe_weights, item)
            if length(session.recipes_by_output[item]) > 1
                @warn "Automatically picking one of multiple recipes for output '$item': $(session.available_recipes[session.recipes_by_output[item][1]])"
            end
            recipe_weights[item] = map(i -> (i==1 ? 1//1 : 0//1),
                                       1:length(session.recipes_by_output[item]))
        end
    end

    return FactoryFloor(outputs_per_minute, inputs_per_minute, recipe_weights, session)
end


"
Parses a factory floor from JSON.
Throws an error if the parsing failed or the data was fatally flawed.

#TODO: Document the format
"
function parse_factory_floor_json(json_str::AbstractString, session::GameSession)::FactoryFloor
    json_dict = JSON3.read(json_str)
    if !isa(json_dict, AbstractDict)
        error("Expected a JSON object, got the literal '", json_str, "'")
    end

    load_factory_number(obj, desc) = let result = load_json_number(obj)
        if isnothing(result)
            error("Passed a literal decimal number for ", desc, ": '", obj,
                  "'. This will create floating-point errors!",
                  " Please surround the number in quotes to make it a string.")
        elseif ismissing(result)
            error("Can't convert data for ", desc, " into a number: '", obj, "'")
        else
            result
        end
    end

    # Read the desired outputs.
    outputs_per_minute = Dict{Item, SNumber}()
    if !haskey(json_dict, :outputs_per_minute)
        error("No 'outputs_per_minute' field was given")
    end
    for (item, count) in json_dict[:outputs_per_minute]
        item = Item(item)
        count = load_factory_number(count, "desired output of item '$item'")
        outputs_per_minute[item] = count
    end

    # Read the desired inputs.
    inputs_per_minute = Dict{Item, SNumber}()
    if haskey(json_dict, :inputs_per_minute)
        for (item,  count) in json_dict[:inputs_per_minute]
            item = Item(item)
            count = load_factory_number(count, "extra inputs of item '$item'")
            inputs_per_minute[item] = count
        end
    end

    # Read the explicit recipe weights.
    recipe_weights = Dict{Item, Vector{SNumber}}()
    if haskey(json_dict, :recipe_weights)
        for (item, weights) in json_dict[:recipe_weights]
            recipe_weights[Item(item)] = map(x -> load_factory_number(x, "recipe weights for '$item'"),
                                             weights)
        end
    end

    # The constructor call will fill in gaps, normalize weights, etc.
    return FactoryFloor(session, outputs_per_minute,
                        inputs_per_minute=inputs_per_minute,
                        recipe_weights=recipe_weights)
end