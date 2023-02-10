"Everything theoretically available to a Satisfactory player."
struct Cookbook
    main_recipes::Vector{Recipe} # The recipes all players have
    alternative_recipes::Vector{Recipe} # The recipes that come from hard drives.
                                        # Well-ordered so that you can refer to them by index.
    buildings::Dict{Building, SNumber} # Each building uses some amount of power,
                                       #   in the game's units (MW).
    raw_items::Set{Item}
    conveyor_speeds::Vector{SNumber} # Items transported per minute for each Mk
end

# Do hashing and equality based on values, not references.
# This makes testing much easier.
Base.hash(c::Cookbook, u::UInt) = hash(
    hash.(tuple((getfield(c, f) for f in fieldnames(Cookbook))...)),
    u
)
Base.:(==)(a::Cookbook, b::Cookbook) = all(tuple((
    getfield(a, f) == getfield(b, f)
      for f in fieldnames(Cookbook)
)...))


"
Parses a cookbook from JSON.
Throws an error if the parsing failed or the data was fatally flawed.

#TODO: Document the format
"
function parse_cookbook_json(json_str::AbstractString)::Cookbook
    json_dict = JSON3.read(json_str)
    if !isa(json_dict, AbstractDict)
        error("Expected a JSON object, got the literal '", json_str, "'")
    end

    load_cookbook_number(obj, desc) = let result = load_json_number(obj)
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

    buildings = Dict{Building, SNumber}()
    if !haskey(json_dict, :buildings)
        error("Expected a 'buildings' list in the JSON")
    end
    for (building, power_use) in json_dict[:buildings]
        # Note that no error-checking is done for whether the power use is negative.
        # Some buildings generate power!
        buildings[Building(building)] = load_cookbook_number(
            power_use, "power use of building '$building'"
        )
    end

    # Get the defualt buildings to use for any given input count.
    building_defaults = Dict{Int, Building}()
    if haskey(json_dict, :building_per_inputs)
        for (input_count_str, building) in json_dict[:building_per_inputs]
            input_count = tryparse(Int, string(input_count_str))
            if isnothing(input_count)
                error("Couldn't parse key 'building_per_inputs/", input_count_str,
                      "'! It should have been a number")
            end
            building = Building(building)
            if !haskey(buildings, building)
                error("Unknown building '", building, "' referenced in 'building_per_inputs'")
            end
            building_defaults[input_count] = building
        end
    end

    raw_items = Set{Item}()
    if haskey(json_dict, :raw_items)
        for item in json_dict[:raw_items]
            item = Item(item)
            if in(item, raw_items)
                error("Raw item defined more than once: '", item, "'")
            end
            push!(raw_items, item)
        end
    end

    conveyor_speeds = Vector{SNumber}()
    if !haskey(json_dict, :conveyor_speeds)
        error("No 'conveyor_speeds' array given!")
    end
    for conveyor_speed in json_dict[:conveyor_speeds]
        conveyor_speed = load_cookbook_number(conveyor_speed, "conveyor speed value")
        if conveyor_speed <= 0
            error("Conveyor speed must be >= 0: ", conveyor_speed)
        elseif maximum(conveyor_speeds, init=0) >= conveyor_speed
            error("Conveyor speeds are out-of-order; they must be strictly increasing")
        end
        push!(conveyor_speeds, conveyor_speed)
    end

    main_recipes = Vector{Recipe}()
    alternative_recipes = Vector{Recipe}()
    for (r_list, r_key) in [(main_recipes, :main_recipes),
                            (alternative_recipes, :alternative_recipes)]
        if haskey(json_dict, r_key)
            for recipe in json_dict[r_key]
                # Load inputs/outputs.
                r_inputs = Dict{Item, SNumber}()
                r_outputs = Dict{Item, SNumber}()
                if !haskey(recipe, :inputs) || !haskey(recipe, :outputs)
                    error("Recipe is missing 'inputs' or 'outputs' field: ", string(recipe))
                end
                for (r_ingredients, r_key) in [(r_inputs, :inputs),
                                               (r_outputs, :outputs)]
                    for (ingredient, count) in recipe[r_key]
                        ingredient = Item(ingredient)
                        r_ingredients[ingredient] = load_cookbook_number(count, "count for ingredient '$ingredient'")
                    end
                end

                # Figure out what building it uses.
                local building::Building
                if haskey(recipe, :building)
                    building = Building(recipe[:building])
                    if !haskey(buildings, building)
                        error("Recipe references unknown building '", building, "': ", recipe)
                    end
                else
                    n_inputs::Int = length(r_inputs)
                    if !haskey(building_defaults, n_inputs)
                        error("No default building for recipes with ", n_inputs, " inputs: ", recipe)
                    end
                    building = building_defaults[n_inputs]
                end

                # Get the time to complete 1 instance of the recipe.
                local duration_seconds::SNumber
                if haskey(recipe, :per_minute)
                    if length(r_outputs) != 1
                        error("Can only use the 'per_minute' field on a recipe with 1 output! ",
                                recipe)
                    end
                    per_minute = load_cookbook_number(recipe[:per_minute],
                                                      "'per_minute' field in recipe $recipe")
                    if per_minute <= 0
                        error("The per-minute rate of recipes must be > 0: ", recipe)
                    end
                    # Convert units.
                    recipes_per_minute = per_minute // first(r_outputs)[2]
                    duration_seconds = 1 // (recipes_per_minute // 60)
                elseif haskey(recipe, :duration_seconds)
                    duration_seconds = load_cookbook_number(recipe[:duration_seconds],
                                                            "'duration_seconds' field in recipe $recipe")
                    if duration_seconds < 0
                        error("The duration of recipes must be >= 0: ", recipe)
                    end
                else
                    error("No timing information given for recipe <",
                          sprint(io -> print(io, recipe)),
                          ">. Either provide 'per_minute' or 'duration_seconds'")
                end

                push!(r_list, Recipe(r_inputs, r_outputs, duration_seconds, building))
            end
        end
    end

    return Cookbook(main_recipes, alternative_recipes,
                    buildings, raw_items, conveyor_speeds)
end