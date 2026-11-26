import Cocoa

public struct InstantPageV2RevealCostMap {
    public let total: Int
    fileprivate let topLevelEntries: [Entry]
}

extension InstantPageV2RevealCostMap {
    fileprivate enum Entry {
        case text(start: Int, end: Int)
        case nonText(start: Int, end: Int)
        case details(start: Int, end: Int, body: InstantPageV2RevealCostMap?)
        case codeBlock(start: Int, end: Int)
        case table(start: Int, end: Int, rows: [TableRow], title: InstantPageV2RevealCostMap?)
    }

    fileprivate struct TableRow {
        let startCount: Int
        let cells: [TableCell]
    }

    fileprivate struct TableCell {
        let frame: CGRect
        let subMap: InstantPageV2RevealCostMap?
    }
}


private func textInkWidth(_ textItem: InstantPageTextItem) -> Int {
    var total: CGFloat = 0.0
    for line in textItem.lines {
        if let chars = line.characterRects {
            for r in chars where !r.isEmpty {
                total += r.width
            }
        } else {
            total += line.frame.width
        }
    }
    return max(0, Int(total.rounded()))
}

private func itemWidthCost(_ item: InstantPageV2LaidOutItem) -> Int {
    return max(0, Int(item.frame.width.rounded()))
}

private func charCountForWidthBudget(textItem: InstantPageTextItem, widthBudget: Int) -> Int {
    var remaining = CGFloat(widthBudget)
    var count = 0
    for line in textItem.lines {
        if remaining <= 0 { break }
        guard let chars = line.characterRects else {
            let lineWidth = line.frame.width
            if remaining >= lineWidth {
                count += line.range.length
                remaining -= lineWidth
            } else {
                let frac = remaining / max(lineWidth, 0.001)
                count += Int((CGFloat(line.range.length) * frac).rounded(.down))
                remaining = 0
            }
            continue
        }
        var lineDone = false
        for r in chars {
            let w = max(0, r.width)
            if remaining >= w {
                remaining -= w
                count += 1
            } else {
                lineDone = true
                break
            }
        }
        if lineDone {
            break
        }
    }
    return count
}

extension InstantPageV2Layout {
    public func computeRevealCostMap() -> InstantPageV2RevealCostMap {
        var cursor = 0
        let entries = computeEntries(items: self.items, cursor: &cursor)
        return InstantPageV2RevealCostMap(total: cursor, topLevelEntries: entries)
    }
}

extension InstantPageV2RevealCostMap {
    public func revealedContentSize(revealedCount: Int, layout: InstantPageV2Layout) -> CGSize {
        let bounds = computeRevealedBounds(items: layout.items, entries: self.topLevelEntries, revealedCount: revealedCount)
        if bounds.maxY <= 0.0 {
            return CGSize(width: 0.0, height: 0.0)
        }
        let lastItemMaxY = layout.items.map { $0.frame.maxY }.max() ?? 0.0
        let closingPad = max(0.0, layout.contentSize.height - lastItemMaxY)
        let width = min(layout.contentSize.width, max(0.0, bounds.maxX))
        return CGSize(width: width, height: bounds.maxY + closingPad)
    }

    public func revealedItemsMaxY(revealedCount: Int, layout: InstantPageV2Layout) -> CGFloat {
        let bounds = computeRevealedBounds(items: layout.items, entries: self.topLevelEntries, revealedCount: revealedCount)
        return max(0.0, bounds.maxY)
    }
}

private func computeRevealedBounds(items: [InstantPageV2LaidOutItem], entries: [InstantPageV2RevealCostMap.Entry], revealedCount: Int) -> CGRect {
    var bounds: CGRect = .zero
    var initialized = false
    let n = min(items.count, entries.count)
    for i in 0 ..< n {
        guard let extent = revealedExtent(entry: entries[i], item: items[i], revealedCount: revealedCount) else {
            continue
        }
        if initialized {
            bounds = bounds.union(extent)
        } else {
            bounds = extent
            initialized = true
        }
    }
    return bounds
}

private func revealedExtent(entry: InstantPageV2RevealCostMap.Entry, item: InstantPageV2LaidOutItem, revealedCount: Int) -> CGRect? {
    if case let .text(textItem) = item, textItem.isThinking {
        if case let .text(start, _) = entry {
            return revealedCount >= start ? item.frame : nil
        }
        return item.frame
    }
    switch entry {
    case let .text(start, end):
        if revealedCount <= start { return nil }
        if revealedCount >= end { return item.frame }
        if case let .text(textItem) = item {
            return revealedTextExtent(textItem: textItem.textItem, itemFrame: item.frame, localRevealedCount: revealedCount - start)
        }
        return item.frame
    case let .nonText(_, end):
        if revealedCount < end { return nil }
        return item.frame
    case let .codeBlock(start, _):
        if revealedCount < start { return nil }
        return item.frame
    case let .details(start, _, body):
        if revealedCount <= start { return nil }
        if case let .details(detailsItem) = item {
            var bounds = CGRect(
                x: detailsItem.frame.minX,
                y: detailsItem.frame.minY,
                width: detailsItem.frame.width,
                height: detailsItem.titleFrame.maxY
            )
            if let body, let innerLayout = detailsItem.innerLayout, detailsItem.isExpanded {
                let bodyBounds = computeRevealedBounds(
                    items: innerLayout.items,
                    entries: body.topLevelEntries,
                    revealedCount: revealedCount
                )
                if !bodyBounds.isEmpty {
                    bounds = bounds.union(bodyBounds.offsetBy(
                        dx: detailsItem.frame.minX,
                        dy: detailsItem.frame.minY + detailsItem.titleFrame.maxY
                    ))
                }
            }
            return bounds
        }
        return item.frame
    case let .table(start, end, rows, _):
        if revealedCount <= start { return nil }
        if revealedCount >= end { return item.frame }
        if case let .table(table) = item {
            let gridOffsetY = table.titleFrame?.height ?? 0.0
            var height = gridOffsetY
            for row in rows {
                guard revealedCount >= row.startCount else { break }
                let rowMaxY = row.cells.map { $0.frame.maxY }.max() ?? 0.0
                height = max(height, gridOffsetY + rowMaxY)
            }
            return CGRect(x: table.frame.minX, y: table.frame.minY, width: table.frame.width, height: height)
        }
        return item.frame
    }
}

private func revealedTextExtent(textItem: InstantPageTextItem, itemFrame: CGRect, localRevealedCount: Int) -> CGRect {
    var remaining = CGFloat(localRevealedCount)
    var lastRevealedLineMaxY: CGFloat = 0.0
    var maxLocalRight: CGFloat = 0.0
    for line in textItem.lines {
        if remaining <= 0 { break }
        lastRevealedLineMaxY = max(lastRevealedLineMaxY, line.frame.maxY)
        if let chars = line.characterRects {
            var sum: CGFloat = 0.0
            var revealedChars = 0
            var partial = false
            for r in chars {
                let w = max(0, r.width)
                if sum + w <= remaining {
                    sum += w
                    revealedChars += 1
                } else {
                    partial = true
                    break
                }
            }
            if partial {
                let x = CTLineGetOffsetForStringIndex(line.line, line.range.location + revealedChars, nil)
                maxLocalRight = max(maxLocalRight, line.frame.minX + x)
                remaining = 0
            } else {
                maxLocalRight = max(maxLocalRight, textItem.visualLineFrame(line).maxX)
                remaining -= sum
            }
        } else {
            let lineWidth = line.frame.width
            if remaining >= lineWidth {
                maxLocalRight = max(maxLocalRight, textItem.visualLineFrame(line).maxX)
                remaining -= lineWidth
            } else {
                let frac = remaining / max(lineWidth, 0.001)
                maxLocalRight = max(maxLocalRight, line.frame.minX + line.frame.width * frac)
                remaining = 0
            }
        }
    }
    return CGRect(x: itemFrame.minX, y: itemFrame.minY, width: maxLocalRight, height: lastRevealedLineMaxY)
}

private func computeEntries(items: [InstantPageV2LaidOutItem], cursor: inout Int) -> [InstantPageV2RevealCostMap.Entry] {
    var entries: [InstantPageV2RevealCostMap.Entry] = []
    for item in items {
        switch item {
        case let .text(text):
            let start = cursor
            if text.isThinking {
                entries.append(.text(start: start, end: start))
            } else {
                cursor += textInkWidth(text.textItem)
                entries.append(.text(start: start, end: cursor))
            }
        case let .codeBlock(block):
            let start = cursor
            cursor += textInkWidth(block.textItem)
            entries.append(.codeBlock(start: start, end: cursor))
        case let .details(details):
            let start = cursor
            cursor += textInkWidth(details.titleTextItem)
            var body: InstantPageV2RevealCostMap? = nil
            if details.isExpanded, let inner = details.innerLayout {
                var innerCursor = cursor
                let innerEntries = computeEntries(items: inner.items, cursor: &innerCursor)
                let innerTotal = innerCursor - cursor
                cursor = innerCursor
                body = InstantPageV2RevealCostMap(total: innerTotal, topLevelEntries: innerEntries)
            }
            entries.append(.details(start: start, end: cursor, body: body))
        case let .table(table):
            let start = cursor

            var titleMap: InstantPageV2RevealCostMap? = nil
            if let titleLayout = table.titleSubLayout {
                var titleCursor = cursor
                let titleEntries = computeEntries(items: titleLayout.items, cursor: &titleCursor)
                let titleTotal = titleCursor - cursor
                cursor = titleCursor
                titleMap = InstantPageV2RevealCostMap(total: titleTotal, topLevelEntries: titleEntries)
            }

            let groupedByY = Dictionary(grouping: table.cells, by: { $0.frame.minY })
            let sortedRowYs = groupedByY.keys.sorted()

            var rows: [InstantPageV2RevealCostMap.TableRow] = []
            for rowY in sortedRowYs {
                let cellsInRow = (groupedByY[rowY] ?? []).sorted(by: { $0.frame.minX < $1.frame.minX })
                let rowStart = cursor
                var cells: [InstantPageV2RevealCostMap.TableCell] = []
                for cell in cellsInRow {
                    let cellWidthFloor = max(0, Int(cell.frame.width.rounded()))
                    var subMap: InstantPageV2RevealCostMap? = nil
                    if let subLayout = cell.subLayout {
                        var cellCursor = cursor
                        let cellEntries = computeEntries(items: subLayout.items, cursor: &cellCursor)
                        let cellInnerCost = cellCursor - cursor
                        cursor += max(cellInnerCost, cellWidthFloor)
                        subMap = InstantPageV2RevealCostMap(total: cellInnerCost, topLevelEntries: cellEntries)
                    } else {
                        cursor += cellWidthFloor
                    }
                    cells.append(InstantPageV2RevealCostMap.TableCell(frame: cell.frame, subMap: subMap))
                }
                rows.append(InstantPageV2RevealCostMap.TableRow(startCount: rowStart, cells: cells))
            }
            entries.append(.table(start: start, end: cursor, rows: rows, title: titleMap))
        case .formula, .mediaImage, .mediaVideo, .mediaMap, .mediaCoverImage, .mediaPlaceholder,
             .divider, .listMarker, .blockQuoteBar, .blockQuoteDecoration, .shape, .pullQuoteMark, .anchor,
             .buttonRow, .unsupported:
            let start = cursor
            cursor += itemWidthCost(item)
            entries.append(.nonText(start: start, end: cursor))
        }
    }
    return entries
}


public enum InstantPageV2ItemReveal {
    case full
    case hidden
    case clipText(charCount: Int)
    case details(titleCharacterCount: Int, body: InstantPageV2RevealCostMap?, isVisible: Bool)
    case table(InstantPageV2TableReveal)
}

public struct InstantPageV2TableReveal {
    public let title: [InstantPageV2ItemReveal]?
    public let cells: [InstantPageV2CellFrameKey: [InstantPageV2ItemReveal]]
    public let visibleHeight: CGFloat
}

public struct InstantPageV2CellFrameKey: Hashable {
    public let minX: CGFloat, minY: CGFloat, width: CGFloat, height: CGFloat
    public init(_ r: CGRect) { minX = r.minX; minY = r.minY; width = r.width; height = r.height }
}

extension InstantPageV2RevealCostMap {
    public func resolvedReveal(revealedCount: Int, layout: InstantPageV2Layout) -> [InstantPageV2ItemReveal] {
        let entries = self.topLevelEntries
        let n = min(entries.count, layout.items.count)
        var result: [InstantPageV2ItemReveal] = []
        result.reserveCapacity(layout.items.count)
        for i in 0 ..< n {
            result.append(resolveEntry(entries[i], item: layout.items[i], revealedCount: revealedCount))
        }
        if layout.items.count > n {
            for _ in n ..< layout.items.count {
                result.append(.full)
            }
        }
        return result
    }
}

private func resolveEntry(_ entry: InstantPageV2RevealCostMap.Entry, item: InstantPageV2LaidOutItem, revealedCount: Int) -> InstantPageV2ItemReveal {
    if case let .text(textItem) = item, textItem.isThinking {
        if case let .text(start, _) = entry {
            return revealedCount >= start ? .full : .hidden
        }
        return .full
    }
    switch entry {
    case let .text(start, end):
        if revealedCount >= end { return .full }
        if revealedCount <= start { return .hidden }
        if case let .text(textItem) = item {
            let budget = revealedCount - start
            return .clipText(charCount: charCountForWidthBudget(textItem: textItem.textItem, widthBudget: budget))
        }
        return .full
    case let .codeBlock(start, end):
        if revealedCount < start { return .hidden }
        if revealedCount >= end { return .full }
        if case let .codeBlock(block) = item {
            return .clipText(charCount: charCountForWidthBudget(textItem: block.textItem, widthBudget: revealedCount - start))
        }
        return .full
    case let .nonText(_, end):
        return revealedCount >= end ? .full : .hidden
    case let .details(start, _, body):
        guard case let .details(details) = item else { return .full }
        let titleWidth = textInkWidth(details.titleTextItem)
        let titleLocal = max(0, min(revealedCount - start, titleWidth))
        let charCount = titleLocal >= titleWidth
            ? details.titleTextItem.attributedString.length
            : charCountForWidthBudget(textItem: details.titleTextItem, widthBudget: titleLocal)
        return .details(
            titleCharacterCount: charCount,
            body: body,
            isVisible: revealedCount > start
        )
    case let .table(start, end, rows, title):
        if revealedCount <= start { return .hidden }
        if revealedCount >= end { return .full }
        guard case let .table(table) = item else { return .full }
        let titleReveal: [InstantPageV2ItemReveal]?
        if let title, let titleLayout = table.titleSubLayout {
            titleReveal = title.resolvedReveal(revealedCount: revealedCount, layout: titleLayout)
        } else {
            titleReveal = nil
        }
        var subLayouts: [InstantPageV2CellFrameKey: InstantPageV2Layout] = [:]
        for cell in table.cells {
            if let subLayout = cell.subLayout {
                subLayouts[InstantPageV2CellFrameKey(cell.frame)] = subLayout
            }
        }
        var cellReveals: [InstantPageV2CellFrameKey: [InstantPageV2ItemReveal]] = [:]
        let gridOffsetY = table.titleFrame?.height ?? 0.0
        var visibleHeight = gridOffsetY
        for row in rows {
            if revealedCount >= row.startCount {
                visibleHeight = max(visibleHeight, gridOffsetY + (row.cells.map { $0.frame.maxY }.max() ?? 0.0))
            }
            for cell in row.cells {
                let key = InstantPageV2CellFrameKey(cell.frame)
                if let subMap = cell.subMap, let subLayout = subLayouts[key] {
                    cellReveals[key] = subMap.resolvedReveal(revealedCount: revealedCount, layout: subLayout)
                }
            }
        }
        return .table(InstantPageV2TableReveal(title: titleReveal, cells: cellReveals, visibleHeight: visibleHeight))
    }
}


public func instantPageV2RevealClipRects(textItem: InstantPageTextItem, charCount: Int) -> [CGRect] {
    var remaining = charCount
    var rects: [CGRect] = []
    var pendingFullPrefix: CGRect?

    for line in textItem.lines {
        if remaining <= 0 { break }

        let lineFrame = textItem.alignedLineFrame(line)
        let lineUnion: CGRect?
        let isFullLine: Bool
        if let characterRects = line.characterRects {
            let revealCount = min(characterRects.count, remaining)
            isFullLine = revealCount >= characterRects.count
            var union: CGRect?
            for index in 0 ..< revealCount {
                let rect = characterRects[index]
                if rect.isEmpty { continue }
                let glyphRect = CGRect(
                    x: lineFrame.minX + rect.minX,
                    y: lineFrame.minY + lineFrame.height - rect.maxY,
                    width: rect.width,
                    height: rect.height
                )
                union = union?.union(glyphRect) ?? glyphRect
            }
            lineUnion = union
            remaining -= characterRects.count
        } else {
            lineUnion = line.range.length > 0 ? lineFrame : nil
            isFullLine = remaining >= line.range.length
            remaining -= line.range.length
        }

        guard let lineUnion else { continue }
        if isFullLine {
            pendingFullPrefix = pendingFullPrefix?.union(lineUnion) ?? lineUnion
        } else {
            if let pending = pendingFullPrefix {
                rects.append(pending)
            }
            pendingFullPrefix = nil
            rects.append(lineUnion)
        }
    }
    if let pendingFullPrefix {
        rects.append(pendingFullPrefix)
    }
    return rects
}
