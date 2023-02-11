using Test
using JuMP

using OtherSatSolver

# Note this one is used to test parsing, not solving.
# It's very simple and unsolvable.
const COMPLEX_COOKBOOK_JSON = """{
    "buildings" : {
        "smelter": 3,
        "foundry": 16,
        "constructor": 5,
        "assembler": 15
    },
    "building_per_inputs": {
        "1": "constructor",
        "2": "assembler"
    },
    "raw_items": [
        "iron_ore", "copper_ore", "caterium",
        "coal", "sulfur", "bauxite",
        "limestone", "raw_quartz",
        "water", "oil", "nitrogen",
        "wood", "leaves", "alien_protein"
    ],
    "conveyor_speeds": [ 60, 120, 270, 480 ],
    "main_recipes": [
        {
            "inputs": { "iron_ore": 1 },
            "outputs": { "iron_ingot": 1 },
            "per_minute": 30,
            "building": "smelter"
        },
        {
            "inputs": { "steel_ingot": 3 },
            "outputs": { "steel_pipe": 2 },
            "per_minute": 20
        }
    ],
    "alternative_recipes": [
        {
            "inputs": { "copper_sheet": 6, "screw": 52 },
            "outputs": { "steel_pipe": 3 },
            "per_minute": "11.25"
        }
    ]
}"""
const IRON_COOKBOOK_JSON = """{
    "buildings" : {
        "smelter": 3,
        "foundry": 16,
        "constructor": 5,
        "assembler": 15
    },
    "building_per_inputs": {
        "1": "constructor",
        "2": "assembler"
    },
    "raw_items": [
        "iron_ore"
    ],
    "conveyor_speeds": [ 60, 120, 270, 480 ],
    "main_recipes": [
        {
            "inputs": { "iron_ore": 1 },
            "outputs": { "iron_ingot": 1 },
            "per_minute": 30,
            "building": "smelter"
        },
        {
            "inputs": { "iron_ingot": 3 },
            "outputs": { "iron_plate": 2 },
            "per_minute": 20
        },
        {
            "inputs": { "iron_ingot": 1 },
            "outputs": { "iron_rod": 1 },
            "per_minute": 15
        },
        {
            "inputs": { "iron_rod": 1 },
            "outputs": { "screw": 4 },
            "per_minute": 40
        }
    ],
    "alternative_recipes": [
        {
            "inputs": { "iron_plate": 6, "screw": 12 },
            "outputs": { "reinforced_iron_plate": 1 },
            "per_minute": 5
        }
    ]
}"""
const RECIPE_IRON_INGOT = Recipe(Dict(:iron_ore => 1), Dict(:iron_ingot => 1), 60//30, :smelter)
const RECIPE_IRON_PLATE = Recipe(Dict(:iron_ingot => 3), Dict(:iron_plate => 2), 60 // (20//2), :constructor)
const RECIPE_IRON_ROD = Recipe(Dict(:iron_ingot => 1), Dict(:iron_rod => 1), 60//15, :constructor)
const RECIPE_SCREW = Recipe(Dict(:iron_rod => 1), Dict(:screw => 4), 60 // (40//4), :constructor)
const RECIPE_REINFORCED_PLATE = Recipe(Dict(:iron_plate => 6, :screw => 12),
                                       Dict(:reinforced_iron_plate => 1),
                                       60//5,
                                       :assembler)


"A cookbook that uses multiple raw materials."
const HYBRID_COOKBOOK_JSON = """{
    "buildings" : {
        "foundry": 16,
        "constructor": 5,
        "assembler": 15
    },
    "building_per_inputs": {
        "1": "constructor",
        "2": "assembler"
    },
    "raw_items": [
        "iron_ore", "coal", "limestone",
        "leaves"
    ],
    "conveyor_speeds": [ 60, 120, 270, 480 ],
    "main_recipes": [
        {
            "inputs": { "limestone": 3 },
            "outputs": { "concrete": 1 },
            "per_minute": 15
        },
        {
            "inputs": { "coal": 3, "iron_ore": 3 },
            "outputs": { "steel_ingot": 3 },
            "per_minute": 45,
            "building": "foundry"
        },
        {
            "inputs": { "steel_ingot": 4 },
            "outputs": { "steel_beam": 1 },
            "per_minute": 15
        },
        {
            "inputs": { "steel_ingot": 3 },
            "outputs": { "steel_pipe": 2 },
            "per_minute": 20
        },
        {
            "inputs": { "steel_beam": 4, "concrete": 5 },
            "outputs": { "encased_industrial_beam": 1 },
            "per_minute": 6
        },
        {
            "inputs": { "leaves": 10 },
            "outputs": { "biomass": 5 },
            "per_minute": 60
        }
    ]
}"""
const RECIPE_CONCRETE = Recipe(Dict(:limestone => 3), Dict(:concrete => 1), 60//15, :constructor)
const RECIPE_STEEL_INGOT = Recipe(Dict(:coal => 3, :iron_ore => 3),
                                  Dict(:steel_ingot => 3),
                                  60 // (45//3), :foundry)
const RECIPE_STEEL_BEAM = Recipe(Dict(:steel_ingot => 4), Dict(:steel_beam => 1), 60//15, :constructor)
const RECIPE_STEEL_PIPE = Recipe(Dict(:steel_ingot => 3), Dict(:steel_pipe => 2), 60//20, :constructor)
const RECIPE_ENCASED_INDUSTRIAL_BEAM = Recipe(Dict(:steel_beam => 4, :concrete => 5),
                                              Dict(:encased_industrial_beam => 1),
                                              60//6, :assembler)
const RECIPE_BIOMASS_LEAVES = Recipe(Dict(:leaves => 10), Dict(:biomass => 5), 60//60, :constructor)


@testset "OtherSatSolver" begin
    @testset "Parsing" begin
        @test parse_rational("abcd") === nothing

        @test parse_rational("1") === 1 // 1
        @test parse_rational("-1") === -1 // 1
        @test parse_rational("-     1") === -1 // 1
        @test parse_rational("1-") === nothing
        @test parse_rational("-1-") === nothing

        @test parse_rational("12345678") === 12345678 // 1
        @test parse_rational("-12345678") === -12345678 // 1
        @test parse_rational("-       12345678") === -12345678 // 1
        @test parse_rational("123-45678") === nothing
        @test parse_rational("-1234-5678") === nothing

        @test parse_rational("34.567") === ((34 * 1000) + 567) // 1000
        @test parse_rational("34 . 567") === ((34 * 1000) + 567) // 1000
        @test parse_rational("-34.567") === -((34 * 1000) + 567) // 1000
        @test parse_rational("- 34.567") === -((34 * 1000) + 567) // 1000
        @test parse_rational("- 34 .567") === -((34 * 1000) + 567) // 1000
        @test parse_rational("34.-567") === nothing
        @test parse_rational("34.-567-") === nothing
        @test parse_rational("-34.-567") === nothing
        @test parse_rational("-34.-567-") === nothing
        @test parse_rational("-34.567-") === nothing

        @test parse_rational("13/32") === 13 // 32
        @test parse_rational("13 /32") === 13 // 32
        @test parse_rational("13 / 32") === 13 // 32
        @test parse_rational("13/ 32") === 13 // 32
        @test parse_rational("-13/32") === -13 // 32
        @test parse_rational("-13 /32") === -13 // 32
        @test parse_rational("-13/ 32") === -13 // 32
        @test parse_rational("-13 / 32") === -13 // 32
        @test parse_rational("- 13/32") === -13 // 32
        @test parse_rational("- 13 /32") === -13 // 32
        @test parse_rational("- 13/ 32") === -13 // 32
        @test parse_rational("- 13 / 32") === -13 // 32

        @test parse_rational(4) === 4 // 1
        @test parse_rational(-4.0) === -4 // 1

        @test parse_cookbook_json("""
            {
                "buildings": { "a": "0.1" },
                "raw_items": [ "rr" ],
                "conveyor_speeds": [ "1.25", 3 ]
            }
          """) == Cookbook(
              Vector{Recipe}(),
              Vector{Recipe}(),
              Dict(:a => 1//10),
              Set([ :rr ]),
              [ 5//4, 3//1 ]
          )
        @test parse_cookbook_json(COMPLEX_COOKBOOK_JSON) == Cookbook(
              [
                  Recipe(
                      Dict(:iron_ore => 1),
                      Dict(:iron_ingot => 1),
                      2,
                      :smelter
                  ),
                  Recipe(
                      Dict(:steel_ingot => 3),
                      Dict(:steel_pipe => 2),
                      6,
                      :constructor
                  )
              ],
              [
                  Recipe(
                      Dict(:copper_sheet => 6, :screw => 52),
                      Dict(:steel_pipe => 3),
                      1 // (((11 + (1//4)) // 3) // 60),
                      :assembler
                  )
              ],
              Dict(
                  :smelter => 3,
                  :foundry => 16,
                  :constructor => 5,
                  :assembler => 15
              ),
              Set([
                  :iron_ore, :copper_ore, :caterium,
                  :coal, :sulfur, :bauxite,
                  :limestone, :raw_quartz,
                  :water, :oil, :nitrogen,
                  :wood, :leaves, :alien_protein
              ]),
              [ 60//1, 120//1, 270//1, 480//1]
          )
    end

    @testset "GameSessions" begin
        @test read_game_session(write_game_session(Int[ ])) == Int[ ]
        @test read_game_session(write_game_session([1, 2, 5, 7, 3])) == [
            1, 2, 5, 7, 3
        ]

        # Unit-testing the exact value of a GameSession is a pain in the ass,
        #    so test individual fields instead.
        session1 = GameSession(parse_cookbook_json(COMPLEX_COOKBOOK_JSON), Int[ ])
        session2 = GameSession(parse_cookbook_json(COMPLEX_COOKBOOK_JSON), Int[ 1 ])
        @test session1.processed_items == Set([
            :iron_ingot, :steel_ingot, :steel_pipe
        ])
        @test session2.processed_items == Set([
            :iron_ingot, :steel_ingot, :steel_pipe, :copper_sheet, :screw
        ])
    end

    @testset "FactoryFloor" begin
        trivial_floor = parse_factory_floor_json("""{
            "outputs_per_minute": { }
        }""", GameSession(
            parse_cookbook_json("""{
                "buildings": { "a": "0.1" },
                "raw_items": [ "rr" ],
                "conveyor_speeds": [ "1.25", 3 ]
            }"""),
            Int[ ]
        ))
        @test trivial_floor.outputs_per_minute == Dict{Item, SNumber}()
        @test trivial_floor.inputs_per_minute == Dict{Item, SNumber}()

        interesting_floor = parse_factory_floor_json("""{
            "outputs_per_minute": {
                "iron_rod": 20,
                "modular_frame": 6,
                "cable": "20.1"
            },
            "inputs_per_minute": {
                "iron_ingot": 2000
            }
        }""", GameSession(parse_cookbook_json(COMPLEX_COOKBOOK_JSON),
                          Int[ 1 ]))
        @test interesting_floor.outputs_per_minute == Dict(
            :iron_rod => 20//1,
            :modular_frame => 6//1,
            :cable => 20 + (1//10)
        )
        @test interesting_floor.inputs_per_minute == Dict(
            :iron_ingot => 2000
        )
    end

    @testset "Printing" begin
        spn(r) = sprint(io -> print_nice(io, r))
        @test spn(4 // 1) == "4"
        @test spn(-4 // 1) == "-4"
        @test spn(8 // 4) == "2"
        @test spn(-8 // 4) == "-2"
        @test spn(5 // 2) == "2 1/2"
        @test spn(-5 // 2) == "-2 1/2"
        @test spn(1 // 3) == "1/3"
        @test spn(-1 // 3) == "-1/3"
        @test spn(180 // 51) == "3 9/17"
        @test spn(-180 // 51) == "-3 9/17"

        spb(b, pl) = sprint(io -> print_building(io, b, pl))
        @test spb(:assembler, false) == "Assembler"
        @test spb(:assembler, true) == "Assemblers"
        @test spb(:foundry, false) == "Foundry"
        @test spb(:foundry, true) == "Foundries"
        @test spb(:ends_in_s, false) == "Ends_in_s"
        @test spb(:ends_in_s, true) == "Ends_in_ses"
    end

    @testset "Solving iron" begin
        # Work with the basic iron recipes, up to reinforced plates.
        cookbook = parse_cookbook_json(IRON_COOKBOOK_JSON)

        function run_problem(desired_outputs,
                             alternative_recipes = Int[ ],
                             inputs_per_minute = Dict{Item, SNumber}()
                            )::Union{Nothing, FactoryOverview}
            session = GameSession(cookbook, alternative_recipes)
            problem = FactoryFloor(Dict(k=>(v//1) for (k,v) in desired_outputs),
                                   Dict(k=>(v//1) for (k,v) in inputs_per_minute),
                                   session)

            # Solve, and capture the log for debugging.
            solution_box = Ref{Any}(nothing)
            solution_log = sprint() do io
                solution_box[] = solve(problem, log_io = stdout)
            end
            @debug "Solution log:\n============\n$solution_log\n=============="

            return solution_box[]
        end

        # For the first test, don't even craft anything. Just ask for ore.
        solution_trivial = run_problem(Dict(:iron_ore => 10))
        @test !isnothing(solution_trivial)
        @test isempty(solution_trivial.recipe_amounts)
        @test isempty(solution_trivial.unused_inputs)
        @test solution_trivial.raw_amounts == Dict(:iron_ore => 10)
        @test solution_trivial.startup_power_usage == 0
        @test solution_trivial.continuous_power_usage == solution_trivial.startup_power_usage

        # Design a factory that just makes a few ingots.
        solution_basic = run_problem(Dict(:iron_ingot => 5))
        @test !isnothing(solution_basic)
        @test isempty(solution_basic.unused_inputs)
        @test solution_basic.recipe_amounts == Dict(RECIPE_IRON_INGOT => 5//30)
        @test solution_basic.raw_amounts == Dict(:iron_ore => 5)
        @test solution_basic.startup_power_usage == cookbook.buildings[RECIPE_IRON_INGOT.building] *
                                                      solution_basic.recipe_amounts[RECIPE_IRON_INGOT]
        @test solution_basic.continuous_power_usage == solution_basic.startup_power_usage

        # Design a factory that makes two simple products from ingots.
        # Provide access to a superfluous alternative recipe.
        # Also ask for some item that can't be crafted, but provide that item as an input to the floor.
        solution_level1 = run_problem(Dict(:iron_plate=>500, :iron_rod=>1, :widget=>11),
                                      [ 1 ],
                                      Dict(:widget=>20))
        @test !isnothing(solution_level1)
        @test solution_level1.recipe_amounts == Dict(
            RECIPE_IRON_ROD => 1//15,
            RECIPE_IRON_PLATE => 500//20,
            RECIPE_IRON_INGOT => ((1//15 * 15) + (500//20 * 30)) // 30
        )
        @test solution_level1.unused_inputs == Dict(:widget => 9)
        @test solution_level1.raw_amounts == Dict(
            :iron_ore => solution_level1.recipe_amounts[RECIPE_IRON_INGOT] *
                         RECIPE_IRON_INGOT.inputs[:iron_ore] * (60 // RECIPE_IRON_INGOT.duration_seconds)
        )
        @test solution_level1.startup_power_usage == sum((
            solution_level1.recipe_amounts[RECIPE_IRON_ROD] * cookbook.buildings[RECIPE_IRON_ROD.building],
            solution_level1.recipe_amounts[RECIPE_IRON_PLATE] * cookbook.buildings[RECIPE_IRON_PLATE.building],
            solution_level1.recipe_amounts[RECIPE_IRON_INGOT] * cookbook.buildings[RECIPE_IRON_INGOT.building],
        ))
        @test solution_level1.continuous_power_usage == solution_level1.startup_power_usage

        # Design a reinforced iron plate factory, without the alternative recipe that allows it.
        solution_impossible = run_problem(Dict(:reinforced_iron_plate => 20))
        @test isnothing(solution_impossible)

        # Now try to design the reinforced iron plate factory for real.
        solution_big = run_problem(Dict(:reinforced_iron_plate => 20), [ 1 ])
        @test !isnothing(solution_big)
        @test isempty(solution_big.unused_inputs)
        @test solution_big.recipe_amounts == Dict(
            RECIPE_REINFORCED_PLATE => 4//1,
            RECIPE_SCREW => (60 * 4//1)//40,
            RECIPE_IRON_PLATE => (30 * 4//1)//20,
            RECIPE_IRON_ROD => ((60 * 4//1)//4) // 15,
            RECIPE_IRON_INGOT => ((30 * solution_big.recipe_amounts[RECIPE_IRON_PLATE]) +
                                  (15 * solution_big.recipe_amounts[RECIPE_IRON_ROD])
                                 ) // 30
        )
        @test solution_big.raw_amounts == Dict(
            :iron_ore => solution_big.recipe_amounts[RECIPE_IRON_INGOT] *
                         RECIPE_IRON_INGOT.inputs[:iron_ore] * (60 // RECIPE_IRON_INGOT.duration_seconds)
        )
        @test solution_big.startup_power_usage == sum((
            solution_big.recipe_amounts[RECIPE_REINFORCED_PLATE] * cookbook.buildings[:assembler],
            solution_big.recipe_amounts[RECIPE_SCREW] * cookbook.buildings[:constructor],
            solution_big.recipe_amounts[RECIPE_IRON_PLATE] * cookbook.buildings[:constructor],
            solution_big.recipe_amounts[RECIPE_IRON_ROD]* cookbook.buildings[:constructor],
            solution_big.recipe_amounts[RECIPE_IRON_INGOT] * cookbook.buildings[:smelter]
        ))
        @test solution_big.continuous_power_usage == solution_big.startup_power_usage

    end

    @testset "Solving more complex chains" begin
        # Work with a steel+concrete cookbook.
        cookbook = parse_cookbook_json(HYBRID_COOKBOOK_JSON)

        function run_problem(desired_outputs,
                             alternative_recipes = Int[ ],
                             inputs_per_minute = Dict{Item, SNumber}()
                            )::Union{Nothing, FactoryOverview}
            session = GameSession(cookbook, alternative_recipes)
            problem = FactoryFloor(Dict(k=>(v//1) for (k,v) in desired_outputs),
                                   Dict(k=>(v//1) for (k,v) in inputs_per_minute),
                                   session)

            # Solve, and capture the log for debugging.
            solution_box = Ref{Any}(nothing)
            solution_log = sprint() do io
                solution_box[] = solve(problem, log_io = io)
            end
            @debug "Solution log:\n============\n$solution_log\n=============="

            return solution_box[]
        end

        solution = run_problem(Dict(:encased_industrial_beam => (2 + 1//4)),
                               Int[ ],
                               Dict(:concrete => 2))
        @test !isnothing(solution)
        @test isempty(solution.unused_inputs)
        @test length(solution.recipe_amounts) == 4
        @test solution.recipe_amounts[RECIPE_ENCASED_INDUSTRIAL_BEAM] ==
                  (2 + 1//4) // 6
        @test solution.recipe_amounts[RECIPE_STEEL_BEAM] ==
                  (solution.recipe_amounts[RECIPE_ENCASED_INDUSTRIAL_BEAM] *
                     input_per_minute(RECIPE_ENCASED_INDUSTRIAL_BEAM, :steel_beam)
                  ) // output_per_minute(RECIPE_STEEL_BEAM)
        @test solution.recipe_amounts[RECIPE_CONCRETE] ==
                  ((solution.recipe_amounts[RECIPE_ENCASED_INDUSTRIAL_BEAM] *
                      input_per_minute(RECIPE_ENCASED_INDUSTRIAL_BEAM, :concrete)) -
                   2
                  ) // output_per_minute(RECIPE_CONCRETE)
        @test solution.recipe_amounts[RECIPE_STEEL_INGOT] ==
                  (solution.recipe_amounts[RECIPE_STEEL_BEAM] *
                   input_per_minute(RECIPE_STEEL_BEAM, :steel_ingot)
                  ) // output_per_minute(RECIPE_STEEL_INGOT)
        @test solution.raw_amounts == Dict(
            :iron_ore => input_per_minute(RECIPE_STEEL_INGOT, :iron_ore) *
                           solution.recipe_amounts[RECIPE_STEEL_INGOT],
            :coal => input_per_minute(RECIPE_STEEL_INGOT, :coal) *
                       solution.recipe_amounts[RECIPE_STEEL_INGOT],
            :limestone => input_per_minute(RECIPE_CONCRETE, :limestone) *
                            solution.recipe_amounts[RECIPE_CONCRETE]
        )
        @test solution.startup_power_usage == sum((
            solution.recipe_amounts[RECIPE_ENCASED_INDUSTRIAL_BEAM] *
               cookbook.buildings[RECIPE_ENCASED_INDUSTRIAL_BEAM.building],
            solution.recipe_amounts[RECIPE_STEEL_BEAM] *
               cookbook.buildings[RECIPE_STEEL_BEAM.building],
            solution.recipe_amounts[RECIPE_CONCRETE] *
               cookbook.buildings[RECIPE_CONCRETE.building],
            solution.recipe_amounts[RECIPE_STEEL_INGOT] *
               cookbook.buildings[RECIPE_STEEL_INGOT.building]
        ))
        @test solution.continuous_power_usage == solution.startup_power_usage
    end

    #TODO: Test other solver objectives.
end