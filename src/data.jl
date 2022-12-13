"Values are stored as Rational, not Float, to ensure no round-off errors."
const SNumber = Rational{Int64}

const Item = Symbol
const Building = Symbol

"
Recipes are ways to craft ingredients into other ingredients.
They take some time to perform, and require use of a certain building.
"
struct Recipe
    inputs::Dict{Item, SNumber}
    outputs::Dict{Item, SNumber}
    duration_seconds::SNumber # Less ambiguous than "per minute"
                              #    when there are multiple outputs
    building::Building
end

Base.hash(r::Recipe, u::UInt) = hash(hash.((r.inputs, r.outputs, r.duration_seconds, r.building)), u)
Base.:(==)(a::Recipe, b::Recipe) = (a.inputs == b.inputs) &&
                                   (a.outputs == b.outputs) &&
                                   (a.duration_seconds == b.duration_seconds) &&
                                   (a.building == b.building)