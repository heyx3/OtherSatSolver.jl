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


#=
    Describe the factory floor as a series of linear equations/inequalities.

    ax + by + cz + ... = f
    a'x + b'y + c'z + ... = f'
    ...

    Each kind of item corresponds to one equation of the form:
    -neededByRecipe1 * recipe1Scale + -neededByRecipe2 * recipe2Scale ... = desiredTotal - rawInputOfIt
    If a recipe produces the item, then it will have a negative 'neededByRecipe' value).

    Each raw item implies an extra "recipe" for mining 1 per minute.

    Try to minimize the amount of raw materials needed, and the amount of power used.
=#


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
const FLOAT_PRECISION = Ref(0.000075)

"
The default weights given to different raw materials.
Higher weights make the solver avoid them more.
"
const DEFAULT_RAW_WEIGHTS = Dict{Item, WeightedValue}(
    :iron_ore       => WeightedValue(scale = 0.65,  curve = 1.0),
    :copper_ore     => WeightedValue(scale = 0.8,   curve = 1.0),
    :water          => WeightedValue(scale = 0.8,   curve = 1.0),
    :oil            => WeightedValue(scale = 0.95,  curve = 1.0),
    :limestone      => WeightedValue(scale = 1.0,   curve = 1.0),
    :raw_quartz     => WeightedValue(scale = 1.0,   curve = 1.0),
    :caterium_ore   => WeightedValue(scale = 1.3,   curve = 1.0),
    :coal           => WeightedValue(scale = 2.1,   curve = 1.0),
    :bauxite        => WeightedValue(scale = 1.5,   curve = 1.0),
    :nitrogen       => WeightedValue(scale = 1.5,   curve = 1.0),
    :sulfur         => WeightedValue(scale = 1.5,   curve = 1.0),

    :wood           => WeightedValue(scale = 1.0,   curve = 1.0),
    :mycelia        => WeightedValue(scale = 1.0,   curve = 1.0),
    :leaves         => WeightedValue(scale = 1.0,   curve = 1.0),
    :alien_protein  => WeightedValue(scale = 1.0,   curve = 1.0)
)


"Information about a single kind of item. This will be converted into an equation for a solver."
struct SolverItemFact
    # The item this fact is about.
    item::Item
    # Each relevant recipe (by its index) maps to the amount of items produced per minute
    #    (negative if it consumes).
    recipe_terms::Dict{Int, SNumber}
    # If this item is a raw, this is the index of its "mine" pseudo-recipe.
    mining_term::Optional{Int}
    # The total amount of the item to be made, minus the amount that's coming into the factory.
    output::SNumber
    # Whether there was any external input of this item.
    any_external_input::Bool
end
SolverItemFact() = SolverItemFact(:NULL, Dict{Int, SNumber}(), nothing,
                                  0//1, false)

struct SolverProblem
    facts::Vector{SolverItemFact}

    # The number of recipes, plus the number of raws.
    # Each raw implies a pseudo-recipe for mining it (producing 1 per minute).
    n_pseudo_recipes::Int
    # The first index after all real recipes, representing the first pseudo-recipe.
    first_mining_index::Int

    # Each raw is assigned a unique index.
    # The index for the pseudo-recipe "mine raw item #i" is "n_recipes + i".
    raws_ordering::Dict{Item, Int}
    raws_by_idx::Dict{Int, Item}

    # Some facts can be definitively solved.
    # Note that if they're solved with the value 0, they're not included in this dictionary.
    recipe_scales::Dict{Int, SNumber}
    # Raws are indexed here by 'raws_ordering'.
    raws_mined_per_minute::Dict{Int, SNumber}

    # All recipes (and pseudo-recipes for mining raws)
    #    which have been solved and their solutions baked into the facts already.
    # This is equivalent to union(keys(recipe_scales),
    #                             keys(raws_mined_per_minute),
    #                             recipes_and_raws_to_ignore).
    solved_pseudo_recipes::Set{Int}
    # Each unsolved recipe/mining action is a variable to be solved.
    # This list maps each variable to the pseudo-recipe it represents.
    pseudo_recipes_by_variable::Vector{Int}
    # Maps each unsolved pseudo-recipe to its variable.
    variables_by_pseudo_recipe::Dict{Int, Int}
end

"
Builds a set of facts about the given problem to solve.
Also generates some metadata for the facts.

Note that returned fields about 'solved' values or 'variables' are not filled in yet;
    you should call `simplify_facts!()` after this.
"
function build_facts(floor::FactoryFloor, log_io::IO = devnull)::SolverProblem
    game_session = floor.game_session
    cookbook = game_session.cookbook

    n_raws = length(cookbook.raw_items)
    n_recipes = length(game_session.available_recipes)
    all_items::Set{Item} = union(cookbook.raw_items,
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

    # Build a simple data representation of the equations.
    # Generate all the information to provide to the solver.
    facts = collect(Iterators.map(all_items) do item::Item
        fact = SolverItemFact()

        @set! fact.item = item

        for (recipe_idx, recipe) in enumerate(game_session.available_recipes)
            if haskey(recipe.inputs, item)
                fact.recipe_terms[recipe_idx] = -input_per_minute(recipe, item)
            end
            if haskey(recipe.outputs, item)
                fact.recipe_terms[recipe_idx] = get(fact.recipe_terms, recipe_idx, 0//1) +
                                                  output_per_minute(recipe, item)
            end
        end

        if item in cookbook.raw_items
            @set! fact.mining_term = n_recipes + raws_ordering[item]
        end

        @set! fact.output = get(floor.outputs_per_minute, item, 0//1)

        factory_input = get(floor.inputs_per_minute, item, 0//1)
        if !iszero(factory_input)
            @set! fact.output -= factory_input
            @set! fact.any_external_input = true
        end

        return fact
    end)

    return SolverProblem(facts, n_pseudo_recipes, first_mining_index,
                         raws_ordering, raws_by_idx,
                         Dict{Int, SNumber}(), Dict{Int, SNumber}(),
                         Set{Int}(), Vector{Int}(), Dict{Int, Int}())
end

"
Looks for trivial solutions to as many facts as possible.
Returns 'false' if the problem is determined to be unsolvable.
"
function simplify_facts!(floor::FactoryFloor, problem::SolverProblem, log_io::IO = devnull)::Bool

    # Any facts with only a single term are instantly solvable.
    # There are no facts with zero terms, as raws always have a "mine it" pseudo-recipe,
    #    and non-raws are detected by their existence in recipes.
    empty!(problem.solved_pseudo_recipes)
    empty!(problem.recipe_scales)
    raws_mined_per_minute::Dict{Item, SNumber} = Dict{Item, SNumber}()
    # Iterate on the set of facts until they are as simplified as possible.
    needs_simplification::Bool = true
    while needs_simplification
        needs_simplification = false
        for fact_idx::Int in 1:length(problem.facts)
            fact::SolverItemFact = problem.facts[fact_idx]
            # If it can only be mined, it's trivially-solvable.
            if isempty(fact.recipe_terms) && !isnothing(fact.mining_term)
                @assert(!isnothing(fact.mining_term),
                        "$(fact.item) isn't minable and isn't used in a recipe; what is it!? $fact")
                println(log_io, "Minable item ", fact.item,
                        " isn't used in any recipes, so it's being dropped from the solver")
                if haskey(floor.outputs_per_minute, fact.item)
                    println(log_io, "\tThe user has requested to 'solve' it for some reason,",
                              " so just tell them we need to mine the ",
                              floor.outputs_per_minute[fact.item],
                              " per minute that they asked for")
                end
                if fact.output > 0
                    raws_mined_per_minute[fact.item] = fact.output
                end
                @set! fact.output = 0//1
                problem.facts[fact_idx] = fact
                push!(problem.solved_pseudo_recipes, fact.mining_term)
            # If it's only involved in one recipe, then that recipe's usage scale is fixed.
            elseif (length(fact.recipe_terms) == 1) && isnothing(fact.mining_term)
                (recipe_idx, output_per_minute) = first(fact.recipe_terms)
                println(log_io, "Recipe is trivial to solve due to the requirements for ",
                        fact.item, ": ", floor.game_session.available_recipes[recipe_idx])
                # recipe_scale * recipe_output_per_minute == item_output_per_minute
                # => recipe_scale == item_output_per_minute / recipe_output_per_minute
                recipe_scale = max(0//1, fact.output) / output_per_minute
                problem.recipe_scales[recipe_idx] = recipe_scale

                println(log_io, "\tThe item has a required output of ", max(0//1, fact.output),
                                ", and the recipe outputs ", output_per_minute,
                                ", so the recipe scale will be ", recipe_scale)
                push!(problem.solved_pseudo_recipes, recipe_idx)

                # Now go through other facts and take into account this newly-solved recipe,
                #    moving its terms to the right-hand side of the equations.
                needs_simplification = true
                map!(problem.facts, problem.facts) do other_fact::SolverItemFact
                    if haskey(other_fact.recipe_terms, recipe_idx)
                        println(log_io, "\tThis simplifies the equation for ", other_fact.item,
                                "\n\t\tCurrent item output: ", other_fact.output,
                                "; change: ", -recipe_scale * other_fact.recipe_terms[recipe_idx])
                        @set! other_fact.output -= recipe_scale * other_fact.recipe_terms[recipe_idx]
                        delete!(other_fact.recipe_terms, recipe_idx)
                    end
                    return other_fact
                end
            end
        end

        # Prune any facts which have no terms left.
        # Look for false facts (e.x. 0 == 1), which indicate an unsolvable situation.
        let is_unsolvable = Ref(false)
            filter!(problem.facts) do fact::SolverItemFact
                should_prune::Bool = isempty(fact.recipe_terms) &&
                                    (isnothing(fact.mining_term) ||
                                     (fact.mining_term in problem.solved_pseudo_recipes))
                if should_prune
                    println(log_io, "Item ", fact.item,
                            " is full of trivially-solvable recipes and is being removed from the solver.")
                    # There are no terms on the left-hand side, meaning production is fixed.
                    # If some amount still needs to be produced, there is no way to produce it.
                    if fact.output > 0
                        print(log_io, "\tUnfortunately, it needs to produce another ")
                        print_nice(log_io, fact.output)
                        println(log_io, " per minute. Solver failed!")
                        is_unsolvable[] = true
                    end
                end
                return !should_prune
            end
            if is_unsolvable[]
                return nothing
            end
        end
    end

    # Now that numerous recipes have been solved, there are fewer variables for the solver to handle.
    # Create an explicit mapping from variable to unsolved recipe.
    empty!(problem.pseudo_recipes_by_variable)
    for pseudo_recipe_idx::Int in 1:problem.n_pseudo_recipes
        if !in(pseudo_recipe_idx, problem.solved_pseudo_recipes)
            push!(problem.pseudo_recipes_by_variable, pseudo_recipe_idx)
        end
    end
    for (v, r) in enumerate(problem.pseudo_recipes_by_variable)
        problem.variables_by_pseudo_recipe[r] = v
    end

    for (r, m) in raws_mined_per_minute
        problem.raws_mined_per_minute[problem.raws_ordering[r]] = m
    end

    return true
end

"
Searches for a good solution to the problem, assumed to have been pre-processed by `simplify_facts!()`.
Returns the solved scale for every pseudo-recipe that hasn't been pre-solved.
"
function search_facts(floor::FactoryFloor, problem::SolverProblem, log_io::IO)::Dict{Int, SNumber}
    # Use Float64 internally, then rationalize and iron out the kinks at the end.
    pseudo_recipe_scales = fill(0.0, problem.n_pseudo_recipes)
    used_pseudo_recipes = Set{Int}()


    # Come up with an initial guess for the solution.
    # For each fact equation (ax + by + cz = d),
    #    set each new recipe's scale based on its multiplier (x/y = a/b, x/z = a/c, etc).
    # ax + by + cz = d
    # x/y = a/b
    # x/z = a/c
    # y/z = b/c
    #   => x = y*a/b
    #   => z = x*c/a
    #   => z = ya/b * c/a = y(ac / ab)
    #    Substitute x and z in terms of y:
    #   => d = a(ya/b) + by + c(yac/(ab))
    #   => d = y([a² / b] + b + [c² / b])
    #   => y = d / (b + c² / b + a² / b) = d / (b + (c² + a²) / b)
    #    Solve x and z in the same way as y:
    #   => x = z(a/c)
    #   => y = x(b/a)
    #        = z(b/c)
    #   => d = ax + b(xb/a) + c(xc/a)
    #        = x(a + b²/a + c²/a)
    #   => x = d / (a + (b² + c²)/a)
    #   => d = a(za/c) + b(zb/c) + cz
    #        = z([a² / c] + b²/c + c)
    #   => z = d / (c + [a² + b²] / c)
    #  This implies the weighting for each recipe is `output / (multipler + (sum(x->x*x, other_multipliers) / multiplier))`.
    #    Prove by substituting the solutions for x, y, and z in the equation for d.
    #   => d = a(d/(a + (b² + c²)/a)) + b(d/(b + [c² + a²] / b)) + c(d/(c + [a² + b²] / c))
    #        = d(a / (a + (b² + c²)/a) + b / (b + [c² + a²] / b) + c / (c + [a² + b²] / c)
    #   => 1 = a / (a + [b² + c²] / a) + b / (b + [c² + a²] / b) + c / (c + [a² + b²] / c)
    #        = (a[b + (c² + a²)/b][c + (a² + b²)/c] +
    #           b[a + (b² + c²)/a][c + (a² + b²)/c] +
    #           c[a + (b² + c²)/a][b + (c² + a²)/b]) /
    #          ([a + (b² + c²)/a][b + (a² + c²)/b][c + (a² + b²)/c])
    #        = ([ab + a(c² + a²)/b][c + (a² + b²)/c] +
    #           [ba + b(b² + c²)/a][c + (a² + b²)/c] +
    #           [ca + c(b² + c²)/a][b + (c² + a²)/b]) /
    #          ([ab + a(a² + c²)/b + b(b² + c²)/a + (b² + c²)(a² + c²)/(ab)] *
    #           [c + (a² + b²)/c])
    #        = ([abc + ab(a² + b²)/c + ac(c² + a²)/b + a(c² + a²)(a² + b²)/(bc)] +
    #           [bac + cb(b² + c²)/a + ba(a² + b²)/c + b(b² + c²)(a² + b²)/(ac)] +
    #           [cab + ca(c² + a²)/b + bc(b² + c²)/a + c(b² + c²)(c² + a²)/(ab)]) /
    #          (abc + ab(a² + b²)/c + ac(a² + c²)/b + a(a² + c²)(a² + b²)/(bc) +
    #           bc(b² + c²)/a + b(b² + c²)(a² + b²)/(ac) +
    #           c(b² + c²)(a² + c²)/(ab) +
    #           (a² + b²)(b² + c²)(a² + c²)/(abc))
    #       => 3abc + 2ab(a² + b²)/c + 2ac(c² + a²)/b + 2cb(b² + c²)/a +
    #           a(c² + a²)(a² + b²)/(bc) + b(b² + c²)(a² + b²)/(ac) + c(b² + c²)(a² + c²)/(ab)
    #          =
    #          abc +
    #           ab(a² + b²)/c + ac(a² + c²)/b + bc(b² + c²)/a +
    #           a(a² + c²)(a² + b²)/(bc) + b(b² + c²)(b² + a²)/(ac) + c(b² + c²)(a² + c²)/(ab) +
    #           (a² + b²)(b² + c²)(a² + c²)/(abc)
    #       => 2abc + ab(a² + b²)/c + ac(c² + a²)/b + bc(b² + c²)/a
    #          =
    #          (a² + b²)(b² + c²)(a² + c²)/(abc)
    #       => 2a²b²c² + a²b²(a² + b²) + a²c²(a² + c²) + b²c²(b² + c²)
    #          = (a²b² + a²c² + b⁴ + b²c²)(a² + c²)
    #          = (a⁴b² + a²b²c² + a⁴c² + a²c⁴ + a²b⁴ + c²b⁴ + a²b²c² + b²c⁴)
    #          = 2a²b²c² + a⁴(b² + c²) + b⁴(a² + c²) + c⁴(a² + b²)
    #       => a⁴b² + a²b⁴ + a⁴c² + a²c⁴ + b⁴c² + b²c⁴
    #          = a⁴b² + a²b⁴ + a⁴c² + a²c⁴ + b⁴c² + b²c⁴
    #       yay
    # ---------------------------------------------------------
    # Intuitively, this should be the same regardless of how many variables there are.
    # Double-check that the pattern applies in a 5-variable version.
    # ax + by + cz + dw + eu = f
    # x/y = a/b
    #  => x = y(a/b)
    # z/y = c/b
    #  => z = y(c/b)
    # w/y = d/b
    #  => w = y(d/b)
    # u/y = e/b
    #  => u = y(e/b)
    #      => f = ya²/b + by + yc²/b + yd²/b + ye²/b
    #           = y(b + a²/b + c²/b + d²/b + e²/b)
    #           = y(b + (a² + c² + d² + e²)/b)
    #      => y = f / (b + (a² + c² + d² + e²)/b)
    #      yay

    # So the weighting for each recipe is
    #     `output / (multipler + (sum(x->x*x, other_multipliers) / multiplier))`.

    estimated_recipes = Set{Int}()
    # Start with the most complex recipes, which I list at the end of the cookbook.
    for fact::SolverItemFact in reverse(problem.facts)
        left_hand_terms = fact.recipe_terms
        if exists(fact.mining_term)
            # Append the mining term.
            left_hand_terms = Iterators.flatten((left_hand_terms, tuple(fact.mining_term => 1)))
        end

        # Move already-estimated variables to the right-hand side of this equation,
        #    and get the sum total multiplier of the left-hand side.
        output::Float64 = fact.output
        total_multiplier::Float64 = 0.0
        for (recipe_idx, multiplier) in left_hand_terms
            if recipe_idx in estimated_recipes
                output -= multiplier * pseudo_recipe_scales[recipe_idx]
            else
                total_multiplier += abs(multiplier)
            end
        end
        # Now make an estimate for each un-estimated variable,
        #    using the math derived above.
        for (recipe_idx, multiplier) in left_hand_terms
            if !in(recipe_idx, estimated_recipes)
                push!(estimated_recipes, recipe_idx)
                other_multipliers_squared = sum(m*m for (i, m) in left_hand_terms if (i != recipe_idx))
                pseudo_recipe_scales[recipe_idx] = output / (multiplier + (other_multipliers_squared / multiplier))
            end
        end
    end

    println(log_io, "Initial estimation for the solver: {")
    for (pseudo_recipe_idx, scale) in enumerate(Iterators.filter(s -> !iszero(s), pseudo_recipe_scales))
        if pseudo_recipe_idx >= problem.first_mining_index
            print(log_io, "\tMine 1 ",
                          problem.raws_by_idx[pseudo_recipe_idx - problem.first_mining_index + 1],
                          " per minute: ")
        else
            print(log_io, "\t", floor.game_session.available_recipes[pseudo_recipe_idx], ": ")
        end
        print_nice(log_io, rationalize(scale * 100, atol=0.01))
        println(log_io, " %")
    end
    println(log_io, "}")

    # Iteratively push the solver towards more efficient solutions.
    push_amount = Dict{Int, Float64}()
    fact_terms = Vector{Pair{Int, SNumber}}() # Temp list
    for iter_idx in 1:100
        # Compute the push.
        empty!(push_amount)
        for fact::SolverItemFact in problem.facts
            # Gather all the terms on the left-hand side of the equation.
            clear!(fact_terms)
            append!(fact_terms, fact.recipe_terms)
            if exists(fact.mining_term)
                append!(fact_terms, fact.mining_term => 1//1)
            end

            # Find the difference between the left-hand side and the right-hand side.
            expected::Float64 = fact.output
            actual::Float64 = sum(multiplier * pseudo_recipe_scales[recipe_idx]
                                    for (recipe_idx, multiplier) in fact_terms)
            needed_delta = expected - actual

            # Push the relevant variables around to shrink the delta.
            # Each variable's weight is relative to:
            #    1) its current magnitude squared (to keep all recipe weights as small as possible)
            #    2) its multiplier (to put more emphasis on more impactful recipes)
            #TODO: Implement.
        end
        # Apply the push.
        for (pseudo_recipe_idx, amount) in push_amount
            pseudo_recipe_scales[pseudo_recipe_idx] += amount
        end
    end

    # Rationalize the solver, and reduce it to a sparse array.
    rational_recipe_scales = Dict(i => rationalize(scale, tol=FLOAT_PRECISION[])
                                    for (i, scale) in enumerate(pseudo_recipe_scales))
    filter!(kvp -> !iszero(kvp[2]), rational_recipe_scales)

    #TODO: Iron out small imprecisions due to the rationalization. Might not be necessary, as Satisfactory solutions are expected to be fairly simple rationals already.

    return rational_recipe_scales
end


"Converts a fact into a JuMP constraint."
function fact_to_constraint(problem::SolverProblem, fact_idx::Int, model::JuMP.Model, x, log_io::IO)
    fact = problem.facts[fact_idx]
    @assert((length(fact.recipe_terms) + (isnothing(fact.mining_term) ? 0 : 1)) > 1,
            "Fact should have been solved/pruned: $fact")
    # Annoyingly, it is very hard to find any way to dynamically assemble a constraint function,
    #   so we have to push it back to compile-time.
    # @generated functions make this less painful, compared to
    #    manually assembling an AST for the entire model definition.
    return fact_to_constraint(problem, fact_idx, model, x, log_io::IO, Val(length(fact.recipe_terms)))
end

@generated function fact_to_constraint(problem::SolverProblem, fact_idx::Int, model::JuMP.Model, x,
                                       log_io::IO,
                                       ::Val{NTerms}) where {NTerms}
    # The left-hand-side of the equation is a sum
    #    of the total amount of this recipe produced per minute.

    vars_expr = quote end
    lhs_expr = :( +() )

    for i in 1:NTerms
        var_idx = Symbol(:i, i)
        push!(vars_expr.args, :(
            $var_idx::Int = problem.variables_by_pseudo_recipe[terms[$i][1]]
        ))

        push!(lhs_expr.args, :( x[$var_idx] * terms[$i][2] ))
    end

    return quote
        fact::SolverItemFact = problem.facts[fact_idx]
        terms::Vector{Pair{Int, SNumber}} = collect(fact.recipe_terms)
        $vars_expr

        print(log_io, fact.item, ": ")
        if fact.any_external_input
            println(log_io, "@constraint(model, ", :( $($lhs_expr) >= $(fact.output)))
            @constraint(model, $lhs_expr >= fact.output)
        else
            println(log_io, "@constraint(model, ", :( $($lhs_expr) == $(fact.output)))
            @constraint(model, $lhs_expr == fact.output)
        end
    end
end


"Solves a factory floor."
function solve(floor::FactoryFloor,
               ;
               # You can use this to provide higher or lower preference
               #    to specific raw materials that might be used.
               # The solver will try to avoid using materials with higher values.
               raws_priorities::Dict{Item, WeightedValue} = DEFAULT_RAW_WEIGHTS,
               # Weights the impact of power efficiency on a factory design's judged quality.
               power_efficiency_priority::WeightedValue = WeightedValue(
                   # Extremely vague guess: a factory with 350 raw input should use 1000 MW.
                   # Power is not particularly rare, so I'd like it to scale less than linearly by default.
                   # However, exponents less than 1 seem to break the solver,
                   #    so settle for lowering the scale.
                   scale = (350 / 1000) * 0.85,
                   curve = 1.0
               ),
               log_io::IO = devnull)::Optional{FactoryOverview}

    game_session = floor.game_session
    cookbook = game_session.cookbook

    # Pre-process the problem.
    problem::SolverProblem = build_facts(floor, log_io)
    is_solvable::Bool = simplify_facts!(floor, problem, log_io)
    if !is_solvable
        return nothing
    end
    recipe_scales::Vector{SNumber} = fill(0//1, length(game_session.available_recipes))
    raws_mined_per_minute::Dict{Item, SNumber} = Dict{Item, SNumber}()
    for (recipe_idx, recipe_scale) in problem.recipe_scales
        recipe_scales[recipe_idx] = recipe_scale
        println(log_io, "Pre-crafting ", recipe_scale, " times '",
                game_session.available_recipes[recipe_idx])
    end
    for (raw_idx, raw_per_minute) in problem.raws_mined_per_minute
        raws_mined_per_minute[problem.raws_by_idx[raw_idx]] = raw_per_minute
        println(log_io, "Pre-mining ", raw_per_minute, " ",
                problem.raws_by_idx[raw_idx], " per minute");
    end

    # Solve the problem.
    if true # Use my solver
        solver_result = search_facts(floor, problem, log_io)
        for (pseudo_recipe_idx, scale) in solver_result
            if pseudo_recipe_idx >= problem.first_mining_index
                raw = problem.raws_by_idx[pseudo_recipe_idx - problem.first_mining_index + 1]
                raws_mined_per_minute[raw] = scale
            else
                recipe_scales[pseudo_recipe_idx] = scale
            end
        end
    else # Create and execute an external solver
        n_variables::Int = length(problem.pseudo_recipes_by_variable)
        if n_variables > 0
            println(log_io, "Variables: ")
            for i in 1:n_variables
                pseudo_recipe_idx = problem.pseudo_recipes_by_variable[i]
                print_data = (pseudo_recipe_idx >= problem.first_mining_index) ?
                                tuple(problem.raws_by_idx[i - problem.first_mining_index + 1]) :
                                tuple(game_session.available_recipes[pseudo_recipe_idx])
                println(log_io, "\tx[", i, "] = ", print_data...)
            end

            # model = JuMP.Model(ECOS.Optimizer)
            # set_optimizer_attribute(model, "maxit", 200000)

            model = JuMP.Model(() -> AmplNLWriter.Optimizer(Couenne_jll.amplexe))
            # set_silent(model)

            @variable(model, x[i=1:n_variables] >= 0)
            for i in 1:length(problem.facts)
                fact_to_constraint(problem, i, model, x, log_io)
            end
            @objective(model, Min, sum(r*r for r in x))
            println(log_io, "\nModel:\n", model, "\n\n")

            optimize!(model)
            #TODO: Bring back the old smart objective functions (need some kind of wacky @generated for that).

            # Communicate the results.
            if !has_values(model)
                println(log_io, "No solution. Solver status:")
                println(log_io, solution_summary(model))
                return nothing
            end
            println(log_io, "Found a solution!")

            # Translate variables into actual results.
            for var_idx::Int in 1:n_variables
                pseudo_recipe_idx::Int = problem.pseudo_recipes_by_variable[var_idx]
                scale::SNumber = rationalize(value(x[var_idx]), tol=FLOAT_PRECISION[])

                if !iszero(scale)
                    if pseudo_recipe_idx >= problem.first_mining_index
                        raw_idx = pseudo_recipe_idx - problem.first_mining_index + 1
                        raws_mined_per_minute[problem.raws_by_idx[raw_idx]] = scale
                    else
                        @assert(iszero(recipe_scales[pseudo_recipe_idx]), "Already set this recipe scale??")
                        recipe_scales[pseudo_recipe_idx] = scale
                    end
                end
            end
        end
    end

    # Calculate other information needed in the factory overview.
    startup_power_usage::Float64 = 0
    continuous_power_usage::Float64 = 0
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

    # Return the solution.
    recipe_scale_lookup = Dict(game_session.available_recipes[i] => s
                                   for (i, s) in enumerate(recipe_scales)
                                   if !iszero(s))
    return FactoryOverview(recipe_scale_lookup, raws_mined_per_minute, unused_inputs_per_minute,
                           rationalize(startup_power_usage, tol=FLOAT_PRECISION[]),
                           rationalize(continuous_power_usage, tol=FLOAT_PRECISION[]))
end


#TODO: Optionally minimize power usage, material usage, or other things.
#TODO: Prioritize certain recipes (e.x. alternates)
#TODO: Output some info on how much "startup" resources are needed, i.e. count all the used recipe byproducts.