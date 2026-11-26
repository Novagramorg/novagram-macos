import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import LokiRng
import TelegramContext
import TelegramUtils
import InlineStickerLayer



public struct PositionGenerator {
    public struct Position {
        public let distance: CGFloat
        public let angle: CGFloat
        public let scale: CGFloat
        
        public init(distance: CGFloat, angle: CGFloat, scale: CGFloat) {
            self.distance = distance
            self.angle = angle
            self.scale = scale
        }
        
        public var relativeCartesian: CGPoint {
            return CGPoint(
                x: self.distance * cos(self.angle),
                y: self.distance * sin(self.angle)
            )
        }
    }
    
    let containerSize: CGSize
    let centerFrame: CGRect
    let exclusionZones: [CGRect]
    let minimumDistance: CGFloat
    let edgePadding: CGFloat
    let scaleRange: (min: CGFloat, max: CGFloat)
    
    let innerOrbitRange: (min: CGFloat, max: CGFloat)
    let outerOrbitRange: (min: CGFloat, max: CGFloat)
    let innerOrbitCount: Int
    
    private let lokiRng: LokiRng
    
    public init(
        containerSize: CGSize,
        centerFrame: CGRect,
        exclusionZones: [CGRect],
        minimumDistance: CGFloat,
        edgePadding: CGFloat,
        seed: UInt,
        scaleRange: (min: CGFloat, max: CGFloat) = (0.7, 1.15),
        innerOrbitRange: (min: CGFloat, max: CGFloat) = (1.4, 2.2),
        outerOrbitRange: (min: CGFloat, max: CGFloat) = (2.5, 3.6),
        innerOrbitCount: Int = 4
    ) {
        self.containerSize = containerSize
        self.centerFrame = centerFrame
        self.exclusionZones = exclusionZones
        self.minimumDistance = minimumDistance
        self.edgePadding = edgePadding
        self.scaleRange = scaleRange
        self.innerOrbitRange = innerOrbitRange
        self.outerOrbitRange = outerOrbitRange
        self.innerOrbitCount = innerOrbitCount
        self.lokiRng = LokiRng(seed0: seed, seed1: 0, seed2: 0)
    }
    
    public func generatePositions(count: Int, itemSize: CGSize) -> [Position] {
        var positions: [Position] = []
        
        let centerPoint = CGPoint(x: self.centerFrame.midX, y: self.centerFrame.midY)
        let centerRadius = min(self.centerFrame.width, self.centerFrame.height) / 2.0
        
        let maxAttempts = count * 200
        var attempts = 0
        
        var leftPositions = 0
        var rightPositions = 0
        
        let innerCount = min(self.innerOrbitCount, count)
        
        while positions.count < innerCount && attempts < maxAttempts {
            attempts += 1
            
            let placeOnLeftSide = rightPositions > leftPositions
            
            let orbitRangeSize = self.innerOrbitRange.max - self.innerOrbitRange.min
            let orbitDistanceFactor = self.innerOrbitRange.min + orbitRangeSize * CGFloat(self.lokiRng.next())
            let orbitDistance = orbitDistanceFactor * centerRadius
            
            let angleRange: CGFloat = placeOnLeftSide ? .pi : .pi
            let angleOffset: CGFloat = placeOnLeftSide ? .pi/2 : -(.pi/2)
            let angle = angleOffset + angleRange * CGFloat(self.lokiRng.next())
            
            let absoluteX = centerPoint.x + orbitDistance * cos(angle)
            let absoluteY = centerPoint.y + orbitDistance * sin(angle)
            let absolutePosition = CGPoint(x: absoluteX, y: absoluteY)
            
            if absolutePosition.x - itemSize.width/2 < self.edgePadding ||
                absolutePosition.x + itemSize.width/2 > self.containerSize.width - self.edgePadding ||
                absolutePosition.y - itemSize.height/2 < self.edgePadding ||
                absolutePosition.y + itemSize.height/2 > self.containerSize.height - self.edgePadding {
                continue
            }
            
            let itemRect = CGRect(
                x: absolutePosition.x - itemSize.width/2,
                y: absolutePosition.y - itemSize.height/2,
                width: itemSize.width,
                height: itemSize.height
            )
            
            if self.isValidPosition(itemRect, existingPositions: positions.map { self.posToAbsolute($0.relativeCartesian, centerPoint: centerPoint) }, itemSize: itemSize) {
                let scaleRangeSize = max(self.scaleRange.min + 0.1, 0.75) - self.scaleRange.max
                let scale = self.scaleRange.max + scaleRangeSize * CGFloat(self.lokiRng.next())
                positions.append(Position(distance: orbitDistance, angle: angle, scale: scale))
                
                if absolutePosition.x < centerPoint.x {
                    leftPositions += 1
                } else {
                    rightPositions += 1
                }
            }
        }
        
        let maxPossibleDistance = hypot(self.containerSize.width, self.containerSize.height) / 2
        
        attempts = 0
        
        while positions.count < count && attempts < maxAttempts {
            attempts += 1
            
            let placeOnLeftSide = rightPositions >= leftPositions
            
            let orbitRangeSize = self.outerOrbitRange.max - self.outerOrbitRange.min
            let orbitDistanceFactor = self.outerOrbitRange.min + orbitRangeSize * CGFloat(self.lokiRng.next())
            let orbitDistance = orbitDistanceFactor * centerRadius
            
            let angleRange: CGFloat = placeOnLeftSide ? .pi : .pi
            let angleOffset: CGFloat = placeOnLeftSide ? .pi/2 : -(.pi/2)
            let angle = angleOffset + angleRange * CGFloat(self.lokiRng.next())
            
            let absoluteX = centerPoint.x + orbitDistance * cos(angle)
            let absoluteY = centerPoint.y + orbitDistance * sin(angle)
            let absolutePosition = CGPoint(x: absoluteX, y: absoluteY)
            
            if absolutePosition.x - itemSize.width/2 < self.edgePadding ||
                absolutePosition.x + itemSize.width/2 > self.containerSize.width - self.edgePadding ||
                absolutePosition.y - itemSize.height/2 < self.edgePadding ||
                absolutePosition.y + itemSize.height/2 > self.containerSize.height - self.edgePadding {
                continue
            }
            
            let itemRect = CGRect(
                x: absolutePosition.x - itemSize.width/2,
                y: absolutePosition.y - itemSize.height/2,
                width: itemSize.width,
                height: itemSize.height
            )
            
            if self.isValidPosition(itemRect, existingPositions: positions.map { self.posToAbsolute($0.relativeCartesian, centerPoint: centerPoint) }, itemSize: itemSize) {
                let distance = hypot(absolutePosition.x - centerPoint.x, absolutePosition.y - centerPoint.y)
                
                let normalizedDistance = min(distance / maxPossibleDistance, 1.0)
                let scale = self.scaleRange.max - normalizedDistance * (self.scaleRange.max - self.scaleRange.min)
                positions.append(Position(distance: orbitDistance, angle: angle, scale: scale))
                
                if absolutePosition.x < centerPoint.x {
                    leftPositions += 1
                } else {
                    rightPositions += 1
                }
            }
        }
        
        return positions
    }
    
    private func posToAbsolute(_ relativePos: CGPoint, centerPoint: CGPoint) -> CGPoint {
        return CGPoint(x: relativePos.x + centerPoint.x, y: relativePos.y + centerPoint.y)
    }
    
    private func isValidPosition(_ rect: CGRect, existingPositions: [CGPoint], itemSize: CGSize) -> Bool {
        if rect.minX < self.edgePadding || rect.maxX > self.containerSize.width - self.edgePadding ||
            rect.minY < self.edgePadding || rect.maxY > self.containerSize.height - self.edgePadding {
            return false
        }
        
        for zone in self.exclusionZones {
            if rect.intersects(zone) {
                return false
            }
        }
        
        let effectiveMinDistance = existingPositions.count > 5 ? max(self.minimumDistance * 0.7, 10.0) : self.minimumDistance
        
        for existingPosition in existingPositions {
            let distance = hypot(existingPosition.x - rect.midX, existingPosition.y - rect.midY)
            if distance < effectiveMinDistance {
                return false
            }
        }
        
        return true
    }
}


extension PeerInfoSpawnEmojiView {
    public func set(fileId: Int64, color: NSColor, context: any AccountContextProtocol, animated: Bool) {
        set(fileId: fileId, color: color, context: context, inlinePacksContext: context.inlinePacksContext, animated: animated)
    }
}
