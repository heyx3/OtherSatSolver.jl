"A specific set of desired outputs (and related parameters, like how much to use alternative recipes)."
struct FactoryFloor
    outputs_per_minute::Dict{Item, SNumber}

    # Incoming items that the factory can take as a given; it does not need to make/mine them.
    inputs_per_minute::Dict{Item, SNumber}

    # A convenient reference to the game session this factory is being built within.
    game_session::GameSession
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

    return FactoryFloor(outputs_per_minute, inputs_per_minute, session)
end