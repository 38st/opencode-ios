import Testing
@testable import OCModels

// The cases of the reference's markdown-inline-code-kind.test.ts.
@Test(arguments: ["app.tsx", "app.tsx:42", "app.tsx#L42-L55", "src/file.ts", "C:\\tmp\\out.html", "/etc/hosts",
                  "app/(auth)/[id]/page.tsx", "console.log", "Dockerfile", "Makefile:12"])
func inlineCodeThatMayNameAFile(_ text: String) { #expect(InlineCodeLinks.isPath(text)) }

@Test(arguments: ["value", "readme", "1.2.3", "127.0.0.1:8080", "foo(bar)", "a = b", "<App />", "src/**/*.ts", "{ a: 1 }",
                  "...", "ftp://x/y", "\\\\host\\share\\x.ts", "//host/share/x.ts", "https://opencode.ai/docs"])
func inlineCodeThatStaysCode(_ text: String) { #expect(!InlineCodeLinks.isPath(text)) }

@Test func candidatesSkipFencesLinkTextAndDuplicates() {
    let markdown = """
    Open `Sources/App.swift:2` and `README.md`, then `Sources/App.swift:2` again.
    Already linked: [`Example.swift`](Sources/Example.swift:2-3).
    ```swift
    let path = `Fenced.swift`
    ```
    Inline `value` and `src/**/*.ts` stay code.
    ~~~
    `Tilde.swift`
    ~~~
    After the fence: `after.ts`
    """
    #expect(InlineCodeLinks.candidates(in: markdown) == ["Sources/App.swift:2", "README.md", "after.ts"])
    #expect(InlineCodeLinks.candidates(in: markdown, limit: 2) == ["Sources/App.swift:2", "README.md"])
}

@Test func confirmedSpansBecomeLinksToThemselves() {
    let markdown = "See `Sources/App.swift:2`, `missing.ts` and `app/(auth)/page.tsx`.\n```\n`Sources/App.swift:2`\n```"
    let linked = InlineCodeLinks.link(markdown, existing: ["Sources/App.swift:2", "app/(auth)/page.tsx"])
    #expect(linked == "See [`Sources/App.swift:2`](Sources/App.swift:2), `missing.ts` and [`app/(auth)/page.tsx`](app/%28auth%29/page.tsx).\n```\n`Sources/App.swift:2`\n```")
    #expect(InlineCodeLinks.link(markdown, existing: []) == markdown)
}
