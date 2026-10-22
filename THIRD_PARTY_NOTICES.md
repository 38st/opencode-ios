# Third-party notices

This is an independent native client, licensed under the GPL-3.0-only (see [LICENSE](LICENSE)). Bundled third-party material keeps its own licence and is credited below.

## OpenCode design tokens and icons — MIT

The default OpenCode (OC-2) theme, component measurements and 149 SVG icons were ported from `packages/ui` in the read-only OpenCode reference, with layout references from `packages/app` and `packages/session-ui`. The original icon geometry is preserved; SVGs are template assets. The complete licence is bundled at `Packages/OpencodeKit/Sources/OCDesign/Resources/Licenses/opencode-MIT.txt`.

MIT License

Copyright (c) 2025 opencode

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## Material Icon Theme file-type artwork and OpenCode mappings — MIT

The 231 `filetype-*` SVG image sets and `file-icons.json` were ported from OpenCode's `packages/ui/src/components/file-icons/sprite.svg` and `file-icon.tsx` at `d0732ea`. The filename, extension and directory mappings remain covered by the OpenCode MIT notice above.

The artwork originates in **Material Icon Theme**, created by **Philipp Kief** and maintained by **Material Extensions**. Its paths and colours were verified against the published VSIX artifacts for [v5.18.0](https://github.com/material-extensions/vscode-material-icon-theme/releases/tag/v5.18.0), [v5.30.0](https://github.com/material-extensions/vscode-material-icon-theme/releases/tag/v5.30.0) and [v5.39.0](https://github.com/material-extensions/vscode-material-icon-theme/releases/tag/v5.39.0): 220 exact XML matches after serialization normalization, ten with OpenCode's `currentColor` substitutions, and one with equivalent SVG path syntax. OpenCode's artwork adaptations are preserved; no icons were changed by this attribution review.

The complete published MIT notice (Copyright (c) 2025 Material Extensions), together with the original project notice (Copyright (c) 2021 Philipp Kief, verified in [v4.34.0](https://github.com/material-extensions/vscode-material-icon-theme/blob/v4.34.0/LICENSE.md)), is bundled at `Packages/OpencodeKit/Sources/OCDesign/Resources/Licenses/material-icon-theme-MIT.txt`, beside `opencode-MIT.txt`. See `docs/m3b-audit.md` for the comparison method and evidence.

## Inter — SIL Open Font License 1.1

Copyright 2016 The Inter Project Authors (https://github.com/rsms/inter).

Bundled unchanged from `packages/ui/src/assets/fonts/Inter.ttf`. The copyright, licence and licence URL were verified in the font's OpenType name table (IDs 0, 13 and 14). The full licence is bundled in `Resources/Licenses/Inter-OFL.txt` within OCDesign.

## JetBrains Mono Nerd Font Mono — SIL Open Font License 1.1

Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono).

Source: `packages/ui/src/assets/fonts/JetBrainsMonoNerdFontMono-Regular.woff2`. Its name table identifies the family as `JetBrainsMono NFM`, PostScript name `JetBrainsMonoNFM-Regular`, and SIL OFL 1.1. The WOFF2 container was decoded to TTF for Core Text using FontTools; glyph outlines and name-table metadata are preserved. The complete licence is bundled in `Resources/Licenses/JetBrainsMono-OFL.txt` within OCDesign. The common OFL text comes from `packages/app/src/settings/about/notices/fonts/OFL-1.1.txt`, prefixed with each font's own copyright line.

## Existing Swift dependencies

- GRDB 7.8.0 — MIT, copyright Gwendal Roué and contributors; https://github.com/groue/GRDB.swift/blob/v7.8.0/LICENSE
- swift-clocks 1.1.1 — MIT, copyright Point-Free, Inc.; https://github.com/pointfreeco/swift-clocks/blob/1.1.1/LICENSE
- swift-snapshot-testing 1.18.7 (tests only) — MIT, copyright Point-Free, Inc.; https://github.com/pointfreeco/swift-snapshot-testing/blob/1.18.7/LICENSE
- swift-concurrency-extras (transitive dependency of swift-clocks / snapshot testing) — MIT, copyright Point-Free, Inc.; https://github.com/pointfreeco/swift-concurrency-extras/blob/main/LICENSE

Full dependency licences remain in their SwiftPM checkouts. The design-asset port adds no app library; M2b's rendering dependencies are listed below. Local capture tooling uses Playwright 1.56.1 (Apache 2.0), its Chromium browser (Chromium third-party notices), FontTools (MIT), Brotli (MIT), and Pillow (HPND); these are not bundled in the application. New development dependencies are installed under `.build`; existing Python tools are reused without global installation or reconfiguration. Reference web screenshots stay in `.build` and are not redistributed in Git.

### GRDB.swift licence

Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


### swift-clocks licence

MIT License

Copyright (c) 2022 Point-Free

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


### swift-concurrency-extras licence

MIT License

Copyright (c) 2023 Point-Free

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## M2b rendering engines and grammars

The Swift package pins swift-markdown 0.7.3, Textual 0.5.0 and SwiftTreeSitter
0.10.0. SwiftTreeSitter's unrelated older 0.25.0 tag is deliberately not selected.
Their package sources retain upstream licenses. Textual brings its required
SwiftUIMath and ConcurrencyExtras dependencies; resolved revisions are locked in
`Packages/OpencodeKit/Package.resolved`.

Generated tree-sitter parsers and scanners for Swift, TypeScript, TSX, JavaScript,
Python, JSON, Bash, Go, Rust, Markdown, YAML, HTML and CSS are vendored under
`Packages/OpencodeKit/Grammars`. Each directory contains its upstream license.
Exact source repositories and revisions are recorded in
`Tools/grammars/manifest.json`; `Tools/grammars/import.py` reproduces the import.
Swift uses the generated-files revision pinned by SwiftTreeSitter 0.10.0.
The importer adjusts TypeScript scanner include paths and adds explicit bounded
serialization casts in the Python/YAML scanners for warning-free Apple builds.

The model-output cleanup and session indicator implementations are original code,
informed by the ideas documented in research/09. No grapeot source was copied.
