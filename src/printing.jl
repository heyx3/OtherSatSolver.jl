function print_nice(io::IO, r::Rational{Int})
    if isinteger(r)
        print(io, numerator(r))
    else
        i_part = numerator(r) ÷ denominator(r)
        small_numerator = abs(numerator(r)) - (abs(i_part) * denominator(r))
        if i_part != 0
            print(io, i_part, ' ')
        elseif r < 0
            print(io, '-')
        end
        print(io, small_numerator, '/', denominator(r))

    end
end

function print_building(io::IO, b::Building, pluralize::Bool = false)
    s = string(b)
    print(io, uppercase(s[1]))
    print(io, SubString(s, 2:length(s)))
    if pluralize
        if s[end] == 's'
            print(io, "es")
        else
            print(io, 's')
        end
    end
end

function print_ingredient_group(io::IO, items_and_counts; tab="")
    n_items = length(items_and_counts)
    if n_items == 0
        print(io, "[no items!?]")
    elseif n_items == 1
        (item, count) = first(items_and_counts)
        print_nice(io, count)
        print(io, ' ', item)
    else
        print(io, '<')
        for (i, (item, count)) in enumerate(items_and_counts)
            # Print a divider.
            if i > 1
                print(io, " | ")
            end
            print_nice(io, count)
            print(io, ' ', item)
        end
        print(io, '>')
    end
end

function Base.print(io::IO, r::Recipe)
    print(io, "After ")
    print_nice(io, r.duration_seconds)
    print(io, " seconds in a ", r.building, " yield ")
    print_ingredient_group(io, r.outputs)
    print(io, " from ")
    print_ingredient_group(io, r.inputs)
    print(io, '.')
end

#TODO: Cookbook

function Base.print(io::IO, s::GameSession
                    ;
                    tab="",
                    tab_in="    ",
                    line_ending='\n',
                    outer_bookends="{}",
                    inner_bookends="<>")

    TAB1 = tuple(tab, tab_in)
    TAB2 = tuple(TAB1..., tab_in)

    print(io, outer_bookends[1], line_ending)

    # Recipes:
    print(io, TAB1..., "Recipes: ", inner_bookends[1], line_ending)
    for recipe in s.available_recipes
        print(io, TAB2..., recipe, line_ending)
    end
    print(io, TAB1..., inner_bookends[2], line_ending)

    # Raw items:
    print(io, TAB1..., "Raw materials: ", inner_bookends[1], line_ending, TAB2...)
    for (i, material) in enumerate(s.cookbook.raw_items)
        if mod1(i, 4) > 1
            print(io, ' ')
        elseif i > 1
            print(io, line_ending, TAB2...)
        end
        print(io, material)
    end
    print(io, line_ending, TAB1..., inner_bookends[2], line_ending)

    # Processed items:
    print(io, TAB1..., "Processed items: ", inner_bookends[1], line_ending, TAB2...)
    for (i, item) in enumerate(s.processed_items)
        if mod1(i, 4) > 1
            print(io, ' ')
        elseif i > 1
            print(io, line_ending, TAB2...)
        end
        print(io, item)
    end
    print(io, line_ending, TAB1..., inner_bookends[2], line_ending)

    # Conveyor belts:
    print(io, TAB1..., "Conveyor speeds (in items / second): ", inner_bookends[1])
    for speed in s.cookbook.conveyor_speeds
        print(io, ' ')
        print_nice(io, speed)
    end
    print(io, ' ', inner_bookends[2], line_ending)
    # Cached lookups:
    #TODO: More detailed printouts (maybe based on a flag parameter?)
    print(io, TAB1..., "# recipes for each ingredient: ", inner_bookends[1], line_ending)
    for (item, set) in s.recipes_by_input
        print(io, TAB2..., item, ": ", length(set), line_ending)
    end
    print(io, TAB1..., inner_bookends[2], line_ending)
    print(io, TAB1..., "# recipes for each output: ", inner_bookends[1], line_ending)
    for (item, set) in s.recipes_by_output
        print(io, TAB2..., item, ": ", length(set), line_ending)
    end
    print(io, TAB1..., inner_bookends[2], line_ending)

    # Don't bother printing the entire referenced cookbook.

    print(io, tab, outer_bookends[2])
end

function Base.print(io::IO, solution::FactoryOverview
                    ;
                    tab="",
                    tab_in="    ",
                    line_ending='\n',
                    outer_bookends="{}",
                    inner_bookends="<>")
    TAB1 = tuple(tab, tab_in)
    TAB2 = tuple(TAB1..., tab_in)

    print(io, outer_bookends[1], line_ending)

    # Metadata:
    print(io, TAB1..., "Initial power usage: ")
    print_nice(io, solution.startup_power_usage)
    print(io, " MW  |  Continuous power usage: ")
    print_nice(io, solution.continuous_power_usage)
    print(io, " MW", line_ending)

    # Raw materials:
    print(io, TAB1..., "Raw material inputs: ", inner_bookends[1], line_ending)
    for (item, amount_per_minute) in solution.raw_amounts
        if amount_per_minute > 0
            print(io, TAB2..., item, ": ")
            print_nice(io, amount_per_minute)
            print(io, " per minute", line_ending)
        end
    end
    print(io, TAB1..., inner_bookends[2], line_ending)

    # Recipes:
    print(io, TAB1..., "Buildings per recipe: ", inner_bookends[1], line_ending)
    for (recipe, scale) in solution.recipe_amounts
        if scale > 0
            print(io, TAB2...)
            print_nice(io, scale)
            print(io, " ")
            print_building(io, recipe.building, scale > 1)
            print(io, ", doing: ")
            print(io, recipe, line_ending)
        end
    end
    print(io, TAB1..., inner_bookends[2], line_ending)

    print(io, tab, outer_bookends[2])
end