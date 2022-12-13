const RationalFormat_Int = r"^\s*(-?)\s*([0-9]+)\s*$"
const RationalFormat_Decimal = r"^\s*(-?)\s*([0-9]*)\s*\.\s*([0-9]*)\s*$"
const RationalFormat_Fraction = r"^\s*(-?)\s*([0-9]+)\s*/\s*(-?)\s*([0-9]+)\s*$"

"
Parses a base-10 string into a Rational.
Acceptable formats:
 * `-12345` : a normal integer
 * `1.532` : a decimal
 * `25/3` : a fraction

 Returns `nothing` if parsing failed.

Allows whitespace before/after special characters, so that you can pad your text files.
"
function parse_rational( s::AbstractString,
                         ::Type{I} = Int
                       )::Optional{Rational{I}} where {I<:Integer}

    #TODO: Check for out-of-bounds each time a number string is parsed.

    let match = match(RationalFormat_Int, s)
        if exists(match)
            (matched_sign::AbstractString, matched_magnitude::AbstractString) = match.captures

            is_negative::Bool = !isempty(matched_sign)
            if is_negative && (I <: Unsigned)
                return nothing
            end

            value::Rational{I} = parse(I, matched_magnitude) // one(I)
            return is_negative ? -value : value
        end
    end

    let match = match(RationalFormat_Decimal, s)
        if exists(match)
            (matched_sign::AbstractString, matched_ipart::AbstractString, matched_fpart) = match.captures

            is_negative::Bool = !isempty(matched_sign)
            if is_negative && (I <: Unsigned)
                return nothing
            end

            ipart::I = parse(I, matched_ipart)
            fpart::I = parse(I, matched_fpart)
            denominator::I = 10 ^ length(matched_fpart)
            value::Rational{I} = ((ipart * denominator) + fpart) // denominator
            return is_negative ? -value : value
        end
    end

    let match = match(RationalFormat_Fraction, s)
        if exists(match)
            (matched_numer_sign::AbstractString, matched_numerator::AbstractString,
             matched_denom_sign::AbstractString, matched_denominator::AbstractString
            ) = match.captures

            is_negative::Bool = !isempty(matched_numer_sign) != !isempty(matched_denom_sign)
            if is_negative && (I <: Unsigned)
                return nothing
            end

            value::Rational{I} = parse(I, matched_numerator) //
                                   parse(I, matched_denominator)
            return is_negative ? -value : value
        end
    end

    return nothing
end
# For syntactic convenience, add an overload which converts it from a number or symbol.
parse_rational(n::Number, ::Type{I} = Int) where {I<:Integer} = convert(Rational{I}, n)
parse_rational(s::Symbol, ::Type{I} = Int) where {I<:Integer} = parse_rational(string(s), I)