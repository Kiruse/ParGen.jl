# ParGen.jl
A parser generator for the Julia programming language - although currently it does not generate source code, it is a planned feature. A PR for this would be deeply appreciated.

# Table of Contents
*TODO*

# Usage
ParGen can be used as both a library and an application. It produces a parser by the definition of its acceptable language. This language can be defined in memory through ParGen's API, or through the use of another, specifically crafted language called *Language Definition Language*, or LDL for short.

However, ParGen internally generates a *deterministic finite state machine* (DFSM). LDL allows defining ambiguous rules which ultimately must be unified in this internal DFSM in order to achieve determinism. This is achieved via *optimization*, which can also remove unnecessary states (such as subsequent static patterns or dummy states). Optimization is a rather computation-heavy operation that would have to be performed every time the parser is generated. ParGen is intended produce source code that generates the optimized graph from the start to avoid unnecessary optimizations once they have been already computed.

**NOTE: At this time ParGen does not yet produce the aforementioned source code. I would appreciate a PR for this. If no such PR arrives, I will probably implement it myself sooner or later.**

The generated parser attempts to parse complete sources. If it falls short, this is considered an error. If the file falls short, this is also considered an error. Upon success, the parser will return all encountered [captures](#captures). In particular, [Rule Captures](#rule-capture) can be used to semantically process the parsed source while the [String Captures](#string-capture) provide the relevant source snippets.

## Rule Definition
Rules are the heart of ParGen. They employ a [RegEx](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_Expressions)-inspired syntax to define a sequence of arbitrary UTF-8 formatted characters.

Rules adhere to the following logic:

* Rules may be ambiguous. ParGen will attempt to parse the rules in the order they occur from top to bottom.
* Rules may be nested and recursed.

ParGen attempts to parse the entire rule. If the current source position does not fully satisfy a rule, it will abort the current definition and move on to the next alternative definition of the same rule. If none of these apply, ParGen cancels the parsing and throws a [CompositeSyntaxError](#composite-syntax-error) which describes the errors that occurred when attempting to match *all* rule definitions.

Rules are defined through a simple syntax:

```
rule-name: rule-pattern
rule-name: another-pattern
```

`rule-name` may be any UTF-8 character that is *not* used to [modulate](#rule-modulation) rule components. Some safe characters are the ASCII letters & numbers as well as hyphen and underscore. Naturally as the colon indicates the end of the rule name it cannot be used as part of the name.

*Note:* ParGen can (and should) handle ambiguous use of the same characters if the respective context of these characters is unambiguous. For example, the multiplicity pattern `pattern{min, max}` uses the comma which gains a second use outside of curly braces to mean *pattern or pattern* like `pattern, pattern` such that combining both to `pattern{3, 4}, pattern{5, 6}` is still easily possible. However, for simplicity, ParGen avoids ambiguous characters within its own language definition language as far as possible. This does not mean your defined language must adhere to the same rule.

The various `rule-pattern`s one may use to define what the rule matches are defined below ([here](#patterns)).

Note that the above example is syntactically equivalent to the below and merely serves for code clarity:

```
rule-name: rule-pattern | another-pattern
```

## Arrow Syntax
The arrow syntax is one of two flavored syntaxes to describe a mandatory sequence of consecutive patterns. It has two uses: #1) to visually highlight two logically distinct patterns (e.g. separating them through `pattern1 -> newline -> pattern2`), and #2) to define initial terminal state transitions.

What sets ParGen's LDef language apart from other syntax definition languages like the one used by Oracle to document the correct syntax for its MySQL language - for example [CREATE TABLE](https://dev.mysql.com/doc/refman/5.7/en/create-table.html) - is that LDef must also define where the parser starts and where it stops. If one were to try and parse a complete source with these rules, normally they are all entirely interchangeable or part of another rule. From the context in Oracle's MySQL documentation, it is clear which syntax is the "top level" syntax and which nested definitions exist merely for clarity or for reusing. ParGen *could* look similar, and simply treat unnamed rules as top-level syntax definitions. But this assumes that all of these rules are valid in a global "root" context. This is most commonly found in programming languages, but through its arrow syntax ParGen is capable of parsing texts in linear format as well, such as real world addresses.

All of the above, however, implies that ParGen requires explicit definition of which rules are considered "root" rules. This is done through the arrow syntax `->`. This syntax explicitly states that one pattern must follow on another Notably, this will likely result in the "root pattern" like so:

```
-> root
root -> variable -> root
root -> function -> root
root ->
```

The first definition states that the very first rule ParGen must match is `root`. This rule in turn is ambiguous and nests either a `variable` or a `function` rule before returning to `root`. Finally, the last definition declares that `root` may also terminate the parsing. In chief, this sample would parse variables and functions until the end of the file.

While the middle two definitions may also be rewritten as follows:

```
root: variable root
root: function root
```

The first and last definitions must not. Without the former, ParGen will parse nothing of the source and fail immediately. Without the latter, ParGen will parse the entire file but never actually reach a clearly acceptable terminal state and also fail. All other uses of the arrow `->` are optional and may be replaced with one or more whitespaces.

## Patterns
*TODO*

## Rule Modulation
*TODO*

## Captures
Captures resemble a sort of generalized AST. They store various information on the parsed source and are categorized in three different types:

### Capture Sequence
These captures directly represent the capture syntax in a language definition. They contain an arbitrary number of other captures, including nested capture sequences.

### String Capture
The most basic of captures, string captures directly store literal strings of the source. These usually contain the relevant data, such as literal integers or symbol names, in raw/unprocessed string form. Smart capture placement can sanitize and strip irrelevant data such as static prefixes or whitespaces.

### Rule Capture
When captured, rules behave as a recursive [Capture Sequence](#capture-sequence) labeled with the rule name. However, captured rules do not capture the entire rule - only recursively contained captures. An example:

```
foo: <bar>
bar: "test test " <[0-9]{3}>
```

Here, given the source string `"test test 123"` successfully parsing the `foo` rule, the capture `[RuleCapture(:bar, [StringCapture("123")])]` is procured.

On the opposite hand, this ldef:

```
foo: <bar>
bar: "test test " [0-9]{3}
```

Only yields this capture: `[RuleCapture(:bar, [])]`.

This logic allows accepting arbitrary patterns without storing irrelevant data such as comments.


# Errors
ParGen uses few errors to describe what went wrong when parsing the source:

## Parsing Error
A generic error without any specific error instance. It is associated with the parser instance. Cases for this error include failure to parse the complete file (either by reaching terminal state early or by exhausting source *before* entering terminal state), and an undefined yet referenced rule.

## Syntax Error
An error describing what went wrong and where (`line` + `column` properties) in the source.

## Composite Syntax Error
A composition of all [syntax errors](#syntax-error) that occurred while attempting to apply a specific named rule to the source.

The list of errors can be accessed through the error's own `errors` property. This error is designed to allow the caller to attempt to enhance the errors by manually looking at the erroneous source positions - or to simply display them in a prettier fashion.
