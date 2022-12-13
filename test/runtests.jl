using Test

using OtherSatSolver

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
            "outputs": { "rotor": 3 },
            "per_minute": "11.25"
        }
    ]
}"""


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
              Set{Recipe}(),
              Vector{Recipe}(),
              Dict(:a => 1//10),
              Set([ :rr ]),
              [ 5//4, 3//1 ]
          )
        @test parse_cookbook_json(COMPLEX_COOKBOOK_JSON) == Cookbook(
              Set{Recipe}([
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
              ]),
              Recipe[
                  Recipe(
                      Dict(:copper_sheet => 6, :screw => 52),
                      Dict(:rotor => 3),
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
        @test read_game_session(write_game_session([1, 2, 5, 7, 3])) == [
            1, 2, 5, 7, 3
        ]

        # Unit-testing the exact value of a GameSession is a pain in the ass,
        #    so I didn't do it.
    end
end