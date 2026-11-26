import Foundation

public protocol Identifiable {
    associatedtype T: Hashable
    var stableId: T { get }
}

public func mergeListsStableWithUpdates<T>(leftList: [T], rightList: [T], allUpdated: Bool = false) -> ([Int], [(Int, T, Int?)], [(Int, T, Int)]) where T: Comparable, T: Identifiable {
    var removeIndices: [Int] = []
    var insertItems: [(Int, T, Int?)] = []
    var updatedIndices: [(Int, T, Int)] = []

    let nl = leftList.count
    let nr = rightList.count

    var previousIndices: [T.T: Int] = [:]
    var hasPreviousIndices = false

    func previousIndex(for stableId: T.T) -> Int? {
        if !hasPreviousIndices {
            previousIndices.reserveCapacity(nl)
            for index in 0..<nl {
                previousIndices[leftList[index].stableId] = index
            }
            hasPreviousIndices = true
        }
        return previousIndices[stableId]
    }

    var i = 0, j = 0
    while true {
        let left: T? = i < nl ? leftList[i] : nil
        let right: T? = j < nr ? rightList[j] : nil

        if let left = left, let right = right {
            let sameStableId = left.stableId == right.stableId
            let isEqual = sameStableId ? !(left != right) : false
            if sameStableId && (!isEqual || allUpdated) {
                updatedIndices.append((j, right, previousIndex(for: left.stableId)!))
                i += 1; j += 1
            } else if (sameStableId ? isEqual : left == right) && !allUpdated {
                i += 1; j += 1
            } else if left < right {
                removeIndices.append(i)
                i += 1
            } else if !(left > right) {
                removeIndices.append(i)
                i += 1
            } else {
                insertItems.append((j, right, previousIndex(for: right.stableId)))
                j += 1
            }
        } else if left != nil {
            removeIndices.append(i)
            i += 1
        } else if let right = right {
            insertItems.append((j, right, previousIndex(for: right.stableId)))
            j += 1
        } else {
            break
        }
    }

    return (removeIndices, insertItems, updatedIndices)
}




public func mergeListsStableWithUpdatesReversed<T>(leftList: [T], rightList: [T], allUpdated: Bool = false) -> ([Int], [(Int, T, Int?)], [(Int, T, Int)]) where T: Comparable, T: Identifiable {
    var removeIndices: [Int] = []
    var insertItems: [(Int, T, Int?)] = []
    var updatedIndices: [(Int, T, Int)] = []
    
    #if targetEnvironment(simulator)
    var existingStableIds: [T.T: T] = [:]
    for item in leftList {
        if let _ = existingStableIds[item.stableId] {
            assertionFailure()
        } else {
            existingStableIds[item.stableId] = item
        }
    }
    existingStableIds.removeAll()
    for item in rightList {
        if let other = existingStableIds[item.stableId] {
            print("\(other) has the same stableId as \(item): \(item.stableId)")
            assertionFailure()
        } else {
            existingStableIds[item.stableId] = item
        }
    }
    #endif
    
    var currentList = leftList
    
    var i = 0
    var previousIndices: [T.T: Int] = [:]
    for left in leftList {
        previousIndices[left.stableId] = i
        i += 1
    }
    
    i = 0
    var j = 0
    while true {
        let left: T? = i < currentList.count ? currentList[i] : nil
        let right: T? = j < rightList.count ? rightList[j] : nil
        
        if let left = left, let right = right {
            if left.stableId == right.stableId && (left != right || allUpdated) {
                updatedIndices.append((i, right, previousIndices[left.stableId]!))
                i += 1
                j += 1
            } else {
                if left == right && !allUpdated {
                    i += 1
                    j += 1
                } else if left > right {
                    removeIndices.append(i)
                    i += 1
                } else if !(left < right) {
                    removeIndices.append(i)
                    i += 1
                } else {
                    j += 1
                }
            }
        } else if let _ = left {
            removeIndices.append(i)
            i += 1
        } else if let _ = right {
            j += 1
        } else {
            break
        }
    }
    
    //print("remove:\n\(removeIndices)")
    
    for index in removeIndices.reversed() {
        currentList.remove(at: index)
        for i in 0 ..< updatedIndices.count {
            if updatedIndices[i].0 >= index {
                updatedIndices[i].0 -= 1
            }
        }
    }
    
    i = 0
    j = 0
    var k = 0
    while true {
        let left: T?
        
        if k < updatedIndices.count && updatedIndices[k].0 < i {
            k += 1
        }
        
        if k < updatedIndices.count {
            if updatedIndices[k].0 == i {
                left = updatedIndices[k].1
            } else {
                left = i < currentList.count ? currentList[i] : nil
            }
        } else {
            left = i < currentList.count ? currentList[i] : nil
        }
        
        let right: T? = j < rightList.count ? rightList[j] : nil
        
        if let left = left, let right = right {
            if left == right {
                i += 1
                j += 1
            } else if left < right {
                let previousIndex = previousIndices[right.stableId]
                insertItems.append((i, right, previousIndex))
                currentList.insert(right, at: i)
                if k < updatedIndices.count {
                    for l in k ..< updatedIndices.count {
                        updatedIndices[l] = (updatedIndices[l].0 + 1, updatedIndices[l].1, updatedIndices[l].2)
                    }
                }
                
                i += 1
                j += 1
            } else {
                i += 1
            }
        } else if let _ = left {
            i += 1
        } else if let right = right {
            let previousIndex = previousIndices[right.stableId]
            insertItems.append((i, right, previousIndex))
            currentList.insert(right, at: i)
            
            if k < updatedIndices.count {
                for l in k ..< updatedIndices.count {
                    updatedIndices[l] = (updatedIndices[l].0 + 1, updatedIndices[l].1, updatedIndices[l].2)
                }
            }
            
            i += 1
            j += 1
        } else {
            break
        }
    }
    
    for (index, item, _) in updatedIndices {
        currentList[index] = item
    }
    
    assert(currentList == rightList, "currentList == rightList")
    
    return (removeIndices, insertItems, updatedIndices)
}

