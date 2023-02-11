"A set of recipes needed to solve a given factory floor."
struct FactoryOverview
    # How much of each recipe is needed.
    # E.x. a value of 2.5 means 250% of that building/recipe.
    recipe_amounts::Dict{Recipe, SNumber}

    # How many raw ingredients are needed per minute.
    # Not including any inputs you explicitly provided to the factory floor.
    raw_amounts::Dict{Item, SNumber}
    # Items which were mentioned as inputs in the FactoryFloor, but not used.
    unused_inputs::Dict{Item, SNumber}

    #TODO: Extra outputs that will be crafted
    #TODO: Total building counts

    # The total power usage across all buildings, not including those which generate power.
    startup_power_usage::SNumber
    # The total power usage across all buildings, including those which generate power.
    continuous_power_usage::SNumber
end

"
A value which is raised to an exponent and then scaled.
Useful when scoring the efficiency of factory overviews.
For example, use a low scale for iron ore because it's so plentiful,
    and use a high exponent for items you only have small veins of.
"
Base.@kwdef struct WeightedValue
    scale::Float64 = 1.0
    curve::Float64 = 1.0
end
evaluate(v::Float64, w::WeightedValue) = (v ^ w.curve) * v.scale


"
The solver uses `Float64`, then translates back to `Rational` within this margin of error.
Satisfactory's display for overclocking only goes up to 4 decimal digits.
"
const FLOAT_PRECISION = Ref(0.00001)

"Solves a factory floor."
function solve(floor::FactoryFloor,
               ;
               # You can use this to provide higher or lower preference
               #    to specific raw materials that might be used.
               # The solver will try to avoid using materials with higher values.
               # All raws have a default priority of WeightedValue(1, 1).
               raws_priorities::Dict{Item, WeightedValue} = Dict{Item, WeightedValue}(),
               # Weights the impact of power efficiency on a factory design's judged quality.
               power_efficiency_priority::WeightedValue = WeightedValue(
                   # Extremely vague guess: a factory with 350 raw input should use 1000 MW.
                   scale = 350 / 1000,
                   # Power is not particularly rare, so let it scale linearly by default.
                   curve = 1.0
               ),
               log_io::IO = devnull)::Optional{FactoryOverview}
    #=
        Describe the factory floor as a series of linear equations/inequalities.

        ax + by + cz + ... = f
        a'x + b'y + c'z + ... = f'
        ...

        Each kind of item corresponds to one equation of the form:
        -neededByRecipe1 * recipe1Scale + -neededByRecipe2 * recipe2Scale ... = desiredTotal - rawInputOfIt
        If a recipe produces the item, then it will have a negative 'neededByRecipe' value).

        Each raw item implies an extra "recipe" for mining 1 per minute.

        As most recipes don't use most items, and most items aren't needed by any one factory,
            the series of equations should often be sparse -- most constants are 0.

        A major framework for defining equations/optimization problems is JuMP.
        I have decided to use EAGO.jl as the solver, via JuMP.
        It can handle nonlinear equations too, so if that ever comes up in this project it's an easy transition.
    =#

    model = JuMP.Model(EAGO.Optimizer)

    game_session = floor.game_session
    cookbook = game_session.cookbook
    n_raws = length(cookbook.raw_items)
    n_recipes = length(game_session.available_recipes)
    all_items = union(cookbook.raw_items,
                      game_session.processed_items,
                      # Edge-case: items are mentioned but not involved in recipes.
                      keys(floor.inputs_per_minute),
                      keys(floor.outputs_per_minute))

    # The last few recipes are actually placeholders for "mine 1 raw item per minute".
    # Assign an (arbitrary) ordering to the raw items so they can be indexed.
    n_pseudo_recipes = n_recipes + n_raws
    first_mining_index = n_recipes + 1
    raws_ordering = Dict{Item, Int}(r=>i for (i, r) in enumerate(cookbook.raw_items))
    raws_by_idx = Dict{Int, Item}(v=>k for (k,v) in raws_ordering)

    # Unfortunately, I cannot for the life of me figure out how to programmatically build constraints,
    #    so I have to resort to building macro invocations by hand.
    # And due to the complexity of invoking macros within an Expr,
    #    I have to assemble the entire chain of calls as an expression tree.
    # :(

    solve_expr = quote
        model = JuMP.Model(EAGO.Optimizer)
        set_silent(model)
        @variable(model, x[i=1:$n_pseudo_recipes])
    end
    for i in 1:n_pseudo_recipes
        push!(solve_expr.args, :( @constraint(model, x[$i] >= 0) ))
    end

    # For debugging, throw some string messages into the model expression.
    log_data(msg...) = push!(solve_expr.args, :( print(devnull, $(msg...))))

    for item in all_items
        func_expr = 0 # To start, there is nothing affecting the amount of item produced.
        log_data("Item ", string(item))

        # Each use as a recipe input subtracts from the total of the item's linear equation.
        for recipe_idx in get(game_session.recipes_by_input, item, 1:0)
            recipe::Recipe = game_session.available_recipes[recipe_idx]
            func_expr = :( $func_expr + (x[$recipe_idx] * $(-input_per_minute(recipe, item))) )
        end

        # Each use as a recipe output adds to the total of the item's linear equation.
        for recipe_idx in get(game_session.recipes_by_output, item, 1:0)
            recipe::Recipe = game_session.available_recipes[recipe_idx]
            func_expr = :( $func_expr + (x[$recipe_idx] * $(output_per_minute(recipe, item))) )
        end

        # If this is a raw, add a term for the "mine" pseudo-recipe.
        if item in cookbook.raw_items
            raw_idx = raws_ordering[item]
            pseudo_recipe_idx = first_mining_index + raw_idx-1
            log_data("\t Raw idx ", raw_idx)
            func_expr = :( $func_expr + x[$pseudo_recipe_idx] )
        end

        # The bound of this linear equation is the desired output, minus any existing input.
        total_output = get(floor.outputs_per_minute, item, 0) -
                       get(floor.inputs_per_minute, item, 0)
        final_expr = Expr(:call, :>=, func_expr, total_output)

        push!(solve_expr.args, :( @constraint(model, $final_expr)))
    end

    # Minimize raw material requirements.
    raw_material_expr = :( 0 )
    raw_material_expr_is_nonlinear::Bool = false
    for (raw, raw_idx) in raws_ordering
        mining_recipe_idx = first_mining_index + raw_idx-1
        raw_term_expr = :( x[$mining_recipe_idx] )
        if haskey(raws_priorities, raw)
            priority_weighting = raws_priorities[raw]
            if !isone(priority_weighting.curve)
                raw_material_expr_is_nonlinear = true
                raw_term_expr = :( $raw_term_expr ^ $(priority_weighting.curve) )
            end
            if !isone(priority_weighting.scale)
                raw_term_expr = :( $raw_term_expr * $(priority_weighting.scale) )
            end
        end
        raw_material_expr = :( $raw_material_expr + $raw_term_expr )
    end
    push!(solve_expr.args,
          raw_material_expr_is_nonlinear ?
              :( @NLobjective(model, Min, $raw_material_expr) ) :
              :( @objective(model, Min, $raw_material_expr) ))
    # Minimize power usage (not including pseudo "mining" recipes, as mining power use varies a lot).
    power_usage_expr = :( +() )
    for (recipe_idx, recipe) in enumerate(game_session.available_recipes)
        recipe_base_power_usage = cookbook.buildings[recipe.building]
        push!(power_usage_expr.args, :( (x[$recipe_idx] * $recipe_base_power_usage) ))
    end
    if length(power_usage_expr.args) == 2
        power_usage_expr = power_usage_expr.args[2]
    end
    if length(power_usage_expr.args) > 1
        is_nonlinear::Bool = false
        if !isone(power_efficiency_priority.curve)
            is_nonlinear = true
            power_usage_expr = :( $power_usage_expr ^ $(power_efficiency_priority.curve) )
        end
        if !isone(power_efficiency_priority.scale)
            power_usage_expr = :( $power_usage_expr * $(power_efficiency_priority.scale) )
        end
        push!(solve_expr.args,
              is_nonlinear ?
                  :( @NLobjective(model, Min, $power_usage_expr) ) :
                  :( @objective(model, Min, $power_usage_expr) ))
    end
    #TODO: Take user preferences for alternative recipes and raw materials allowed.

    # Add expressions to run and return the solver.
    push!(solve_expr.args, :( optimize!(model) ))
    push!(solve_expr.args, :model)

    # Try running the solver!
    println(log_io, "The solver code: ")
    println(log_io, solve_expr)
    model = eval(solve_expr)

    # Translate the results.
    if !has_values(model)
        println(log_io, "No solution. Solver status:")
        println(log_io, solution_summary(model))
        return nothing
    end
    println(log_io, "Found a solution!")
    recipe_scales::Vector{Rational} = map(f -> rationalize(f, tol=FLOAT_PRECISION[]),
                                          value.(x[1:n_recipes]))
    raws_mined_per_minute = Dict{Item, SNumber}(map(e -> raws_by_idx[e[1]] =>
                                                               rationalize(e[2], tol=FLOAT_PRECISION[]),
                                                    enumerate(value.(x[first_mining_index:n_pseudo_recipes]))))
    filter!(kvp -> !iszero(kvp[2]), raws_mined_per_minute)
    startup_power_usage::Rational = 0
    continuous_power_usage::Rational = 0
    unused_inputs_per_minute = copy(floor.inputs_per_minute)
    acknowledge_ingredient_usage(item, amount) = if haskey(unused_inputs_per_minute, item)
        unused_inputs_per_minute[item] -= amount
        if unused_inputs_per_minute[item] <= 0
            delete!(unused_inputs_per_minute, item)
        end
    end
    for (recipe, scale) in zip(game_session.available_recipes, recipe_scales)
        # Power usage:
        power_usage = scale * cookbook.buildings[recipe.building]
        continuous_power_usage += power_usage
        if power_usage > 0
            startup_power_usage += power_usage
        elseif power_usage < 0
            println("NEGATIVE ENERGY: ", recipe, "\n\tScale: ", scale)
        end

        # Unused input counting:
        for ingredient in keys(recipe.inputs)
            amount = scale * input_per_minute(recipe, ingredient)
            acknowledge_ingredient_usage(ingredient, amount)
        end
    end
    # Edge-case: inputs being directly used as outputs.
    for item in keys(floor.outputs_per_minute)
        if haskey(unused_inputs_per_minute, item)
            acknowledge_ingredient_usage(item, floor.outputs_per_minute[item])
        end
    end
    recipe_scale_lookup = Dict(game_session.available_recipes[i] => s
                                   for (i, s) in enumerate(recipe_scales)
                                   if !iszero(s))
    return FactoryOverview(recipe_scale_lookup, raws_mined_per_minute, unused_inputs_per_minute,
                           startup_power_usage, continuous_power_usage)
end


#TODO: Optionally minimize power usage, material usage, or other things.
#TODO: Prioritize certain recipes (e.x. alternates)
#TODO: Output some info on how much "startup" resources are needed, i.e. count all the used recipe byproducts.