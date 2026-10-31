import Foundation

/// A TeX math formula, for the transcript's LaTeX (the desktop app uses KaTeX). The parser covers the common subset:
/// scripts, fractions, roots, large operators, delimiters, accents, styles, matrices and cases, and the usual
/// symbols. Anything else is an error, and the caller shows the source instead.
public indirect enum MathNode: Equatable, Sendable {
    /// An identifier, number or symbol. Single Latin letters are set in italic.
    case symbol(String)
    /// Upright text: `\text{…}`, function names and `\mathrm`.
    case text(String)
    case row([MathNode])
    case fraction(MathNode, MathNode)
    case root(MathNode, index: MathNode?)
    case scripts(base: MathNode, sup: MathNode?, sub: MathNode?)
    /// ∑, ∏, ∫…; `limits` sets the scripts above and below in display style.
    case largeOperator(String, limits: Bool)
    case delimited(left: String, MathNode, right: String)
    case accent(String, MathNode)
    case bold(MathNode)
    case matrix([[MathNode]], left: String, right: String)
    /// Horizontal space in em.
    case space(Double)
}

public struct MathError: Error, Equatable, Sendable {
    public let message: String
}

public enum MathParser {
    public static func parse(_ source: String) throws -> MathNode {
        var parser = Parser(Array(source))
        let node = try parser.parseRow(until: nil)
        guard parser.atEnd else { throw MathError(message: localized("Unexpected “\(parser.peek.map(String.init) ?? "")”", comment: "%@ is a character in the formula")) }
        return node
    }

    static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
        "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
        "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "ϕ",
        "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ",
        "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
    ]
    static let symbols: [String: String] = [
        "times": "×", "cdot": "⋅", "pm": "±", "mp": "∓", "div": "÷", "ast": "∗", "star": "⋆", "circ": "∘", "bullet": "∙",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡", "sim": "∼",
        "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫", "infty": "∞", "partial": "∂", "nabla": "∇",
        "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←", "leftrightarrow": "↔", "Rightarrow": "⇒",
        "Leftarrow": "⇐", "Leftrightarrow": "⇔", "implies": "⟹", "iff": "⟺", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "cup": "∪",
        "cap": "∩", "setminus": "∖", "emptyset": "∅", "varnothing": "∅", "forall": "∀", "exists": "∃", "neg": "¬",
        "lnot": "¬", "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨", "oplus": "⊕", "otimes": "⊗", "perp": "⊥",
        "parallel": "∥", "mid": "∣", "angle": "∠", "triangle": "△", "ldots": "…", "dots": "…", "cdots": "⋯", "vdots": "⋮",
        "ddots": "⋱", "prime": "′", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ", "degree": "°",
        "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "vert": "|", "Vert": "‖",
        "lbrace": "{", "rbrace": "}", "{": "{", "}": "}", "%": "%", "$": "$", "&": "&", "#": "#", "_": "_", "|": "‖",
        "colon": ":", "dagger": "†", "checkmark": "✓",
    ]
    static let functions: Set<String> = ["sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh",
        "cosh", "tanh", "log", "ln", "lg", "exp", "det", "dim", "ker", "deg", "gcd", "arg", "Pr", "hom"]
    static let limitFunctions: Set<String> = ["lim", "max", "min", "sup", "inf", "limsup", "liminf", "argmax", "argmin"]
    static let largeOperators: [String: String] = ["sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬",
        "iiint": "∭", "oint": "∮", "bigcup": "⋃", "bigcap": "⋂", "bigoplus": "⨁", "bigotimes": "⨂", "bigvee": "⋁", "bigwedge": "⋀"]
    static let accents: [String: String] = ["hat": "\u{302}", "widehat": "\u{302}", "bar": "\u{304}", "overline": "\u{305}",
        "vec": "\u{20D7}", "tilde": "\u{303}", "widetilde": "\u{303}", "dot": "\u{307}", "ddot": "\u{308}", "underline": "\u{332}"]
    static let blackboard: [Character: String] = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "H": "ℍ", "E": "𝔼"]
    static let spaces: [String: Double] = [",": 0.17, ":": 0.22, ";": 0.28, "!": -0.17, " ": 0.25, "quad": 1, "qquad": 2, "enspace": 0.5]
    static let delimiters: [String: String] = ["(": "(", ")": ")", "[": "[", "]": "]", "|": "|", ".": "", "/": "/",
        "\\{": "{", "\\}": "}", "\\langle": "⟨", "\\rangle": "⟩", "\\lvert": "|", "\\rvert": "|", "\\|": "‖", "\\lVert": "‖",
        "\\rVert": "‖", "\\lfloor": "⌊", "\\rfloor": "⌋", "\\lceil": "⌈", "\\rceil": "⌉", "\\vert": "|", "\\Vert": "‖"]
    static let environments: [String: (String, String)] = ["matrix": ("", ""), "pmatrix": ("(", ")"), "bmatrix": ("[", "]"),
        "Bmatrix": ("{", "}"), "vmatrix": ("|", "|"), "Vmatrix": ("‖", "‖"), "cases": ("{", ""), "aligned": ("", ""),
        "align": ("", ""), "align*": ("", ""), "array": ("", ""), "smallmatrix": ("", ""), "gathered": ("", "")]

    struct Parser {
        let chars: [Character]
        var index = 0
        var depth = 0
        init(_ chars: [Character]) { self.chars = chars }
        var atEnd: Bool { index >= chars.count }
        var peek: Character? { atEnd ? nil : chars[index] }

        mutating func skipSpaces() { while let c = peek, c.isWhitespace { index += 1 } }

        /// Parses until `terminator` (a closing character or `\right`, `\end`, `&`, `\\`), which is left in place.
        mutating func parseRow(until terminator: Character?, stopAtCells: Bool = false) throws -> MathNode {
            depth += 1; defer { depth -= 1 }
            guard depth < 64 else { throw MathError(message: localized("Too deeply nested")) }
            var items: [MathNode] = []
            while true {
                skipSpaces()
                guard let c = peek else {
                    if terminator != nil { throw MathError(message: localized("Missing “\(terminator.map(String.init) ?? "")”", comment: "%@ is a closing character")) }
                    break
                }
                if c == terminator { break }
                if stopAtCells && (c == "&" || lookingAt("\\\\") || lookingAt("\\end")) { break }
                if lookingAt("\\right") {
                    if terminator == nil { break }
                    throw MathError(message: localized("Unexpected \\right"))
                }
                if lookingAt("\\end") { throw MathError(message: localized("Unexpected \\end")) }
                if c == "^" || c == "_" {
                    index += 1
                    let script = try parseArgument()
                    let base = items.popLast() ?? .symbol("")
                    items.append(attach(script, to: base, superscript: c == "^"))
                    continue
                }
                if c == "'" {
                    index += 1
                    let base = items.popLast() ?? .symbol("")
                    items.append(attach(.symbol("′"), to: base, superscript: true))
                    continue
                }
                items.append(try parseAtom())
            }
            return items.count == 1 ? items[0] : .row(items)
        }

        func attach(_ script: MathNode, to base: MathNode, superscript: Bool) -> MathNode {
            if case .scripts(let inner, let sup, let sub) = base {
                if superscript && sup == nil { return .scripts(base: inner, sup: script, sub: sub) }
                if !superscript && sub == nil { return .scripts(base: inner, sup: sup, sub: script) }
            }
            return superscript ? .scripts(base: base, sup: script, sub: nil) : .scripts(base: base, sup: nil, sub: script)
        }

        func lookingAt(_ text: String) -> Bool {
            let target = Array(text)
            guard index + target.count <= chars.count else { return false }
            return Array(chars[index..<index + target.count]) == target
        }

        mutating func parseArgument() throws -> MathNode {
            skipSpaces()
            guard let c = peek else { throw MathError(message: localized("Missing argument")) }
            if c == "{" {
                index += 1
                let node = try parseRow(until: "}")
                index += 1
                return node
            }
            if c == "\\" { return try parseCommand() }
            index += 1
            return .symbol(String(c))
        }

        mutating func parseAtom() throws -> MathNode {
            guard let c = peek else { throw MathError(message: localized("Unexpected end")) }
            if c == "{" {
                index += 1
                let node = try parseRow(until: "}")
                index += 1
                return node
            }
            if c == "}" { throw MathError(message: localized("Unmatched “}”")) }
            if c == "&" { throw MathError(message: localized("Unexpected “&”")) }
            if c == "\\" { return try parseCommand() }
            index += 1
            if c.isNumber || c == "." && (peek?.isNumber ?? false) {
                var number = String(c)
                while let next = peek, next.isNumber || next == "." && index + 1 < chars.count && chars[index + 1].isNumber {
                    number.append(next); index += 1
                }
                return .symbol(number)
            }
            switch c {
            case "-": return .symbol("−")
            case "*": return .symbol("∗")
            case "~": return .space(0.25)
            default: return .symbol(String(c))
            }
        }

        mutating func readName() -> String {
            guard let first = peek else { return "" }
            if !first.isLetter { index += 1; return String(first) }
            var name = ""
            while let c = peek, c.isLetter { name.append(c); index += 1 }
            if peek == "*" && name == "align" { name.append("*"); index += 1 }
            return name
        }

        mutating func readBraced() throws -> String {
            skipSpaces()
            guard peek == "{" else { throw MathError(message: localized("Expected “{”")) }
            index += 1
            var level = 1, text = ""
            while let c = peek {
                index += 1
                if c == "{" { level += 1 } else if c == "}" { level -= 1; if level == 0 { return text } }
                text.append(c)
            }
            throw MathError(message: localized("Missing “}”"))
        }

        mutating func readDelimiter() throws -> String {
            skipSpaces()
            guard let c = peek else { throw MathError(message: localized("Missing delimiter")) }
            if c == "\\" {
                index += 1
                let name = "\\" + readName()
                guard let value = MathParser.delimiters[name] else { throw MathError(message: localized("Unknown delimiter \(name)", comment: "%@ is a TeX delimiter")) }
                return value
            }
            index += 1
            guard let value = MathParser.delimiters[String(c)] else { throw MathError(message: localized("Unknown delimiter \(String(c))", comment: "%@ is a TeX delimiter")) }
            return value
        }

        mutating func parseCommand() throws -> MathNode {
            index += 1
            let name = readName()
            if let value = MathParser.greek[name] { return .symbol(value) }
            if let value = MathParser.spaces[name] { return .space(value) }
            if let value = MathParser.largeOperators[name] { return .largeOperator(value, limits: !value.hasPrefix("∫") && !"∬∭∮".contains(value)) }
            if MathParser.functions.contains(name) { return .text(name) }
            if MathParser.limitFunctions.contains(name) { return .largeOperator(name, limits: true) }
            if let value = MathParser.symbols[name] { return .symbol(value) }
            if let mark = MathParser.accents[name] { return .accent(mark, try parseArgument()) }
            switch name {
            case "frac", "dfrac", "tfrac", "cfrac": return .fraction(try parseArgument(), try parseArgument())
            case "binom", "dbinom", "tbinom": return .delimited(left: "(", .matrix([[try parseArgument()], [try parseArgument()]], left: "", right: ""), right: ")")
            case "sqrt":
                skipSpaces()
                var degree: MathNode?
                if peek == "[" { index += 1; degree = try parseRow(until: "]"); index += 1 }
                return .root(try parseArgument(), index: degree)
            case "text", "textrm", "textnormal", "mbox", "operatorname", "mathrm", "textit", "mathit", "textsf", "mathsf", "texttt", "mathtt":
                let text = try readBraced()
                return name.hasPrefix("math") && name != "mathrm" ? .symbol(text) : .text(text)
            case "mathbf", "textbf", "boldsymbol", "bm": return .bold(try parseArgument())
            case "mathbb":
                let text = try readBraced()
                return .symbol(String(text.flatMap { MathParser.blackboard[$0] ?? String($0) }))
            case "mathcal", "mathscr", "mathfrak": return .symbol(try readBraced())
            case "left":
                let left = try readDelimiter()
                let body = try parseRow(until: nil)
                guard lookingAt("\\right") else { throw MathError(message: localized("Missing \\right")) }
                index += "\\right".count
                return .delimited(left: left, body, right: try readDelimiter())
            case "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr": return .symbol(try readDelimiter())
            case "begin": return try parseEnvironment(try readBraced())
            case "displaystyle", "textstyle", "scriptstyle", "limits", "nolimits": return .row([])
            case "not": return .row([.symbol("̸"), try parseArgument()])
            case "overset", "stackrel":
                let over = try parseArgument()
                return .scripts(base: try parseArgument(), sup: over, sub: nil)
            case "\\": return .space(0)
            default: throw MathError(message: localized("Unsupported command \\\(name)", comment: "%@ is a TeX command name"))
            }
        }

        mutating func parseEnvironment(_ name: String) throws -> MathNode {
            guard let (left, right) = MathParser.environments[name] else { throw MathError(message: localized("Unsupported environment \(name)", comment: "%@ is a TeX environment name")) }
            if name == "array" { _ = try? readBraced() }
            var rows: [[MathNode]] = [], cells: [MathNode] = []
            while true {
                let cell = try parseRow(until: nil, stopAtCells: true)
                cells.append(cell)
                if lookingAt("&") { index += 1; continue }
                if lookingAt("\\\\") { index += 2; rows.append(cells); cells = []; continue }
                if lookingAt("\\end") {
                    index += 4
                    let end = try readBraced()
                    guard end == name else { throw MathError(message: localized("\\end{\(end)} closes \(name)", comment: "%1$@ and %2$@ are TeX environment names")) }
                    if !(cells.count == 1 && cells[0] == .row([])) || rows.isEmpty { rows.append(cells) }
                    break
                }
                throw MathError(message: localized("Missing \\end{\(name)}", comment: "%@ is a TeX environment name"))
            }
            return .matrix(rows, left: left, right: right)
        }
    }
}

extension MathNode {
    /// Plain Unicode for inline math in running text: scripts as super- and subscript characters where they exist,
    /// otherwise `^(…)`; fractions as `a/b`.
    public var unicode: String {
        switch self {
        case .symbol(let value), .text(let value): return value
        case .row(let items):
            // Binary operators and relations get the spaces TeX would give them, except as a leading sign.
            return items.enumerated().map { index, item in
                if index > 0, case .symbol(let value) = item, Self.spaced.contains(value) { return " " + value + " " }
                return item.unicode
            }.joined()
        case .fraction(let a, let b): return Self.wrap(a) + "/" + Self.wrap(b)
        case .root(let body, let index): return (index.map { Self.raised($0.unicode) ?? "" } ?? "") + "√" + Self.wrap(body)
        case .scripts(let base, let sup, let sub):
            var out = base.unicode
            if let sub { out += Self.lowered(sub.unicode) ?? "_(" + sub.unicode + ")" }
            if let sup { out += Self.raised(sup.unicode) ?? "^(" + sup.unicode + ")" }
            return out
        case .largeOperator(let value, _): return value
        case .delimited(let left, let body, let right): return left + body.unicode + right
        case .accent(let mark, let body):
            let text = body.unicode
            return text.count == 1 ? text + mark : text
        case .bold(let body): return body.unicode
        case .matrix(let rows, let left, let right):
            return left + rows.map { $0.map(\.unicode).joined(separator: ", ") }.joined(separator: "; ") + right
        case .space(let em): return em > 0.5 ? "  " : em > 0 ? " " : ""
        }
    }
    static let spaced: Set<String> = ["+", "−", "=", "<", ">", "×", "⋅", "±", "∓", "÷", "≤", "≥", "≠", "≈", "≡", "∼", "≃", "≅", "∝",
        "≪", "≫", "→", "←", "↔", "⇒", "⇐", "⇔", "⟹", "⟺", "↦", "∈", "∉", "∋", "⊂", "⊃", "⊆", "⊇", "∪", "∩", "∧", "∨", "⊕", "⊗"]
    static func wrap(_ node: MathNode) -> String {
        let text = node.unicode
        return text.count <= 1 || text.allSatisfy({ $0.isNumber || $0.isLetter }) ? text : "(" + text + ")"
    }
    static let superscripts: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶",
        "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "−": "⁻", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ",
        "′": "′", "T": "ᵀ", "k": "ᵏ", "x": "ˣ", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "m": "ᵐ", "t": "ᵗ", "*": "*", "∗": "*"]
    static let subscripts: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆",
        "7": "₇", "8": "₈", "9": "₉", "+": "₊", "−": "₋", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "i": "ᵢ", "j": "ⱼ",
        "n": "ₙ", "k": "ₖ", "m": "ₘ", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "t": "ₜ", "r": "ᵣ", "s": "ₛ", "p": "ₚ"]
    static func raised(_ text: String) -> String? { map(text, superscripts) }
    static func lowered(_ text: String) -> String? { map(text, subscripts) }
    private static func map(_ text: String, _ table: [Character: Character]) -> String? {
        var out = ""
        for c in text { guard let mapped = table[c] else { return nil }; out.append(mapped) }
        return out.isEmpty ? nil : out
    }
}
