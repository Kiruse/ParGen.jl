push!(LOAD_PATH, @__DIR__)
using ParGen

function printerror(err::CompositeSyntaxError, depth::Integer = 1)
    for error ∈ err.errors
        printerror(error, depth+1)
    end
end
printerror(err::ParGenError, _::Integer) = println(err)

symvarname = Symbol("var-name")
symvardef  = Symbol("var-def")

parser = Parser()

symrootval  = Symbol("root-value")
symrootnest = Symbol("root-nested")
symrootor   = Symbol("root-or")
symrootand  = Symbol("root-and")

rule!(parser, Rule(:pargen_blank, :root, :terminal))
rule!(parser, Rule(:root, capture(orvein(symrootval, symrootnest, symrootor, symrootand))))
rule!(parser, Rule(symrootnest, '(', :root, ')'))
rule!(parser, Rule(symrootor,   :root, '|', :root))
rule!(parser, Rule(symrootand,  :root, '&', :root))
rule!(parser, Rule(symrootval, capture(atleast(charset("01"), 1))))

rule!(parser, Rule(:terminal))

ParGen.statemachine(parser)
