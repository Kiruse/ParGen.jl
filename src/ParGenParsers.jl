# ParGen Parser - the parser parsing parsers
# Copyright (c) Skye Cobile 2020 Germany
# SEE LICENSE IN LICENSE
# ------------------------------------------
# Instantiation of this parser is based on the ldef.ldef file

function pargenparser()
    parser = Parser()
    rule!(parser, Rule(:pargen_blank, :root))
    rule!(parser, Rule(:root, :pargen_blankline, :root))
    rule!(parser, Rule(:root, :commentline, :root))
    rule!(parser, Rule(:root, capture()))
    
    rule!(parser, Rule(:rule, union(unicodeL(), charset("_-"))))
    rule!(parser, Rule(:rulename, :rulename, wscharset(), ':', :rulebody))
    rule!(parser, Rule())
end
