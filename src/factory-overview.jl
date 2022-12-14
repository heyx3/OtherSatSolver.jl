"A set of recipes needed to solve a given factory floor."
struct FactoryOverview
    # How much of each recipe is needed.
    # E.x. a value of 2.5 means 250% of that building/recipe.
    recipe_amounts::Dict{Recipe, SNumber}
    # How many raw ingredients are needed per minute.
    raw_amounts::Dict{Item, SNumber}
    #TODO: Total building counts
    # The total power usage across all buildings, not including those which generate power.
    startup_power_usage::SNumber
    # The total power usage across all buildings, including those which generate power.
    continuous_power_usage::SNumber
end

"
For the `FactoryOverview` solver, more than this many iterations
    will be detected as an infinite loop and throw an error.
The constant is stored in a mutable ref; you can change the constant if you desire a different limit.
"
const INFINITE_LOOP_MAX_FACTORY_OVERVIEW = Ref(5000)

"
Returns a solved factory floor, and also a set of items that were needed but had no recipe.
If the list is nonempty, then the solution is considered 'partial'.
"
function solve(floor::FactoryFloor, log_io::IO = devnull)::Tuple{FactoryOverview, Set{Item}}
    session::GameSession = floor.game_session
    cookbook::Cookbook = session.cookbook

    # For now, to keep things simple,
    #    pick the most desired recipe for each output and ignore the rest.
    recipe_for_each_output::Dict{Item, Optional{Recipe}} = Dict(Iterators.map(floor.output_recipe_weights) do (item, weights)
        item => (isempty(weights) ? nothing : session.recipes_by_output[item][findmax(weights)[2]])
    end)
    println(log_io, "Chosen recipes: ")
    for (item, recipe) in recipe_for_each_output
        println(log_io, '\t', item, ": ", recipe)
    end

    # Accumulate the total number of resources needed.
    # This is done iteratively by peeling off each layer of resources using those resources' recipes.
    failed_items = Set{Item}()
    recipes_needed = Dict{Recipe, SNumber}()
    raws_needed = Dict{Item, SNumber}()
    new_resources_needed_per_minute = copy(floor.outputs_per_minute)
    infinite_loop_counter::Int = 0
    while !isempty(new_resources_needed_per_minute)
        # Pop an item off the stack.
        (next_output, output_count_per_minute) = first(new_resources_needed_per_minute)
        output_recipe::Optional{Recipe} = get(recipe_for_each_output, next_output, nothing)
        delete!(new_resources_needed_per_minute, next_output)

        print(log_io, "Need to make ")
        print_nice(log_io, output_count_per_minute)
        print(log_io, " '", next_output, "' per minute")

        # If this is a raw item, it is not crafted from a recipe but mined outside the factory.
        if next_output in cookbook.raw_items
            print(log_io, ". But that's a raw item, so don't try to craft it.\n")
            raws_needed[next_output] = get(raws_needed, next_output, 0//1) + output_count_per_minute
        else
            # If there is no recipe for this item, then the solver fails.
            if isnothing(output_recipe)
                print(log_io, ". \n\tUH-OH: no recipe available! Skipping this item.\n")
                push!(failed_items, next_output)
            else
                print(log_io, ". \n\tUsing this recipe: ", output_recipe, '\n')

                n_per_recipe_minute = (60 // output_recipe.duration_seconds) * output_recipe.outputs[next_output]
                n_recipes_needed = output_count_per_minute // n_per_recipe_minute
                recipes_needed[output_recipe] = n_recipes_needed + get(recipes_needed, output_recipe, 0 // 1)
                print(log_io, "\tWe need (")
                print_nice(log_io, output_count_per_minute)
                print(log_io, ") / (")
                print_nice(log_io, n_per_recipe_minute)
                print(log_io, ") == ")
                print_nice(log_io, n_recipes_needed)
                print(log_io, " new instances of this recipe, for a new total of ")
                print_nice(log_io, recipes_needed[output_recipe])
                print(log_io, ".\n")

                for (input, input_count_per_recipe) in output_recipe.inputs
                    input_count_per_minute = n_recipes_needed * input_count_per_recipe // (output_recipe.duration_seconds // 60)
                    print(log_io, "\tMore ingredients are now needed: ")
                    print_nice(log_io, input_count_per_minute)
                    print(log_io, " '", input, "' per minute.\n")

                    new_resources_needed_per_minute[input] = input_count_per_minute +
                                                             get(new_resources_needed_per_minute, input, 0//1)
                end
            end
        end

        # Watch out for endless recipe cycles.
        infinite_loop_counter += 1
        if (infinite_loop_counter > INFINITE_LOOP_MAX_FACTORY_OVERVIEW[])
            print(log_io, "ERROR: hit ", infinite_loop_counter,
                          " iterations! Assuming this is an infinite loop.\n")
            error("Infinite loop detected! After ", infinite_loop_counter, " iterations")
        end
    end

    # Calculate the total power usage of these recipes.
    startup_power = 0 // 1
    continuous_power = 0 // 1
    for (recipe, recipe_scale) in recipes_needed
        recipe_power = cookbook.buildings[recipe.building] * recipe_scale
        print(log_io, "Need ")
        print_nice(log_io, recipe_power)
        print(log_io, " MW of power for recipe: ", recipe, '\n')
        continuous_power += recipe_power
        if (recipe_power > 0)
            startup_power += recipe_power
        end
    end

    print(log_io, "Finished!")
    return (FactoryOverview(recipes_needed, raws_needed, startup_power, continuous_power),
            failed_items)
end