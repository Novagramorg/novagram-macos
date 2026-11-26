#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    /// Every code box in the document, recursing containers — a code block can sit inside a quote or a
    /// table cell. Mirrors `stackContainingCodeBox(id:)`'s traversal.
    func forEachCodeBox(_ body: (CodeBlockBox) -> Void) {
        func walk(_ stack: BlockStack) {
            for b in stack.boxes {
                if let c = b as? CodeBlockBox { body(c) }
                if let bq = b as? BlockQuoteBox { walk(bq.children) }
                if let t = b as? TableBlockBox {
                    for cell in t.cells.flatMap({ $0 }) { walk(cell) }
                }
            }
        }
        walk(root)
    }

    /// Schedule a debounced highlight pass. Called from every content edit and from `setModelBlocks`,
    /// never from a selection change: the caret moving through code changes no spec, and scheduling there
    /// would re-run the walk on every arrow key.
    func scheduleSyntaxHighlightPass() {
        guard syntaxHighlighter != nil else { return }
        pendingSyntaxHighlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSyntaxHighlightWork = nil
            self?.runSyntaxHighlightPass()
        }
        pendingSyntaxHighlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + syntaxHighlightDebounceInterval, execute: work)
    }

    /// Collect the document's specs, request the ones not already answered UNDER THE CURRENT PALETTE, and
    /// drop answers for specs the document no longer contains (so a long editing session does not
    /// accumulate every intermediate string the user typed).
    ///
    /// "Already answered" is (language, text, palette): the macOS host bakes the live theme into the
    /// colours it returns, so after an appearance change the cached answer is a placeholder, not an
    /// answer, and the spec must be re-asked. An unchanged palette re-asks nothing, so an ordinary edit
    /// or layout pass costs exactly what it did before — including an unknown language's empty answer,
    /// which is cached like any other and attempted once.
    func runSyntaxHighlightPass() {
        guard let provider = syntaxHighlighter else { return }
        let paletteToken = syntaxHighlightPaletteToken

        var live: Set<CodeHighlightSpec> = []
        forEachCodeBox { box in
            guard let language = richTextNormalizedCodeLanguage(box.languageLayout.attributedString.string) else { return }
            let text = box.layout.attributedString.string
            guard !text.isEmpty else { return }
            live.insert(CodeHighlightSpec(language: language, text: text))
        }

        syntaxHighlightCache = syntaxHighlightCache.filter { live.contains($0.key) }
        inFlightSyntaxHighlightSpecs = inFlightSyntaxHighlightSpecs.filter { live.contains($0.key) }

        applySyntaxHighlightsToBoxes()

        for spec in live where syntaxHighlightCache[spec]?.paletteToken != paletteToken
                            && inFlightSyntaxHighlightSpecs[spec] != paletteToken {
            inFlightSyntaxHighlightSpecs[spec] = paletteToken
            provider(spec.language, spec.text) { [weak self] tokens in
                guard let self else { return }
                if self.inFlightSyntaxHighlightSpecs[spec] == paletteToken {
                    self.inFlightSyntaxHighlightSpecs[spec] = nil
                }
                // An answer produced under a palette the canvas has already left is DROPPED, never cached:
                // the appearance change that retired that palette also scheduled a pass which re-asks for
                // this spec, and storing the old colours here would out-live the fresh answer.
                guard paletteToken == self.syntaxHighlightPaletteToken else { return }
                self.syntaxHighlightCache[spec] = CachedSyntaxHighlight(paletteToken: paletteToken, tokens: tokens)
                self.applySyntaxHighlightsToBoxes()
            }
        }
    }

    /// Hands each code box the tokens for its current (language, text), or none, and repaints on change.
    /// (Unlike the UIKit editor, a macOS code block draws directly into the canvas — there is no pooled
    /// per-block backing view to poke — so `needsDisplay` on the canvas IS the repaint.) Colours only —
    /// never metrics (same text, same font) — so this deliberately does NOT call
    /// `invalidateIntrinsicContentSize()`, which would ask the host to re-lay-out on every arrival.
    func applySyntaxHighlightsToBoxes() {
        forEachCodeBox { box in
            let language = richTextNormalizedCodeLanguage(box.languageLayout.attributedString.string)
            let text = box.layout.attributedString.string
            // Whatever is cached is painted, current palette or not: a stale answer is a placeholder that
            // keeps the rebuild frame coloured until the re-request under the new palette lands.
            let tokens = language.flatMap { syntaxHighlightCache[CodeHighlightSpec(language: $0, text: text)]?.tokens } ?? []
            guard box.applySyntaxHighlight(tokens) else { return }
            needsDisplay = true
            codeHighlightRepaintCount += 1
        }
    }

    /// Re-apply cached highlights to boxes that were just rebuilt from the model, synchronously.
    ///
    /// A rebuild — a theme change, an undo restore, a programmatic re-seed — reconstructs every box from
    /// the model, which carries no colours by design. Leaving them for the debounced pass shows a PLAIN
    /// frame first (the "text loses highlight when the theme changes" report): the answer was in the
    /// cache the whole time. Called from `setModelBlocks`, before the first layout of the new boxes.
    func reapplyCachedSyntaxHighlights() {
        guard !syntaxHighlightCache.isEmpty else { return }
        applySyntaxHighlightsToBoxes()
    }

    /// Test seam: true when nothing is cached.
    var syntaxHighlightCacheIsEmptyForTesting: Bool { syntaxHighlightCache.isEmpty }
    /// Test seam: how many repaints a colour change has caused.
    var codeHighlightRepaintCountForTesting: Int { codeHighlightRepaintCount }
}
#endif
