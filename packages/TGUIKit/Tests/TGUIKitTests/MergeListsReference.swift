import TGUIKit
import protocol TGUIKit.Identifiable

func referenceMergeListsStableWithUpdates<T>(leftList: [T], rightList: [T], allUpdated: Bool = false) -> ([Int], [(Int, T, Int?)], [(Int, T, Int)]) where T: Comparable, T: Identifiable {
    var removeIndices: [Int] = []
    var insertItems: [(Int, T, Int?)] = []
    var updatedIndices: [(Int, T, Int)] = []

    let nl = leftList.count
    let nr = rightList.count

    var previousIndices: [T.T: Int] = [:]
    previousIndices.reserveCapacity(nl)
    for idx in 0..<nl {
        previousIndices[leftList[idx].stableId] = idx
    }

    var keptRight = [Bool](repeating: false, count: nr)

    var i = 0, j = 0
    while true {
        let left: T? = i < nl ? leftList[i] : nil
        let right: T? = j < nr ? rightList[j] : nil

        if let left = left, let right = right {
            let sameStableId = left.stableId == right.stableId
            let isEqual = sameStableId ? !(left != right) : false
            if sameStableId && (!isEqual || allUpdated) {
                updatedIndices.append((j, right, previousIndices[left.stableId]!))
                keptRight[j] = true
                i += 1; j += 1
            } else if (sameStableId ? isEqual : left == right) && !allUpdated {
                keptRight[j] = true
                i += 1; j += 1
            } else if left < right {
                removeIndices.append(i)
                i += 1
            } else if !(left > right) {
                removeIndices.append(i)
                i += 1
            } else {
                j += 1
            }
        } else if left != nil {
            removeIndices.append(i)
            i += 1
        } else if right != nil {
            j += 1
        } else {
            break
        }
    }

    for index in 0 ..< nr where !keptRight[index] {
        let right = rightList[index]
        insertItems.append((index, right, previousIndices[right.stableId]))
    }

    return (removeIndices, insertItems, updatedIndices)
}
