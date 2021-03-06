//
//  actor_path.swift
//  Flare
//
//  Created by Umberto Sonnino on 2/18/19.
//  Copyright © 2019 2Dimensions. All rights reserved.
//

import Foundation

public protocol ActorBasePath: class {
    var shape: ActorShape? { get set }
    var isRootPath: Bool { get set }
    var points: [PathPoint] { get }
    var isClosed: Bool { get }
    var pathTransform: Mat2D? { get }
    var parent: ActorNode? { get }
    var transform: Mat2D { get }
    var worldTransform: Mat2D { get }
    var allClips: [[ActorClip]] { get }
    var deformedPoints: [PathPoint] { get }
    
    func invalidatePath()
    func updateShape()
    func completeResolve()
    func getPathAABB() -> AABB
    func getPathOBB() -> AABB
}

public extension ActorBasePath {
    var isPathInWorldSpace: Bool {
        return false
    }
    
    func getPathAABB() -> AABB {
        var minX = Float32.greatestFiniteMagnitude
        var minY = Float32.greatestFiniteMagnitude
        var maxX = -Float32.greatestFiniteMagnitude
        var maxY = -Float32.greatestFiniteMagnitude
        
        let obb = getPathOBB()
        
        let pts = [
            Vec2D.init(fromValues: obb[0], obb[1]),
            Vec2D.init(fromValues: obb[2], obb[1]),
            Vec2D.init(fromValues: obb[2], obb[3]),
            Vec2D.init(fromValues: obb[0], obb[3])
        ]
        
        var localTransform: Mat2D
        if isPathInWorldSpace {
            // Convert path coordinates to local parent space.
            localTransform = Mat2D()
            _ = Mat2D.invert(localTransform, parent!.worldTransform)
        } else if !isRootPath, let shape = self.shape {
            localTransform = Mat2D()
            // Path isn't root, so get transform in shape space.
            if Mat2D.invert(localTransform, shape.worldTransform) {
                Mat2D.multiply(localTransform, localTransform, worldTransform)
            }
        } else {
            localTransform = transform
        }
        
        for p in pts {
            let wp: Vec2D = Vec2D.transformMat2D(p, p, localTransform)
            if wp[0] < minX {
                minX = wp[0]
            }
            if wp[1] < minY {
                minY = wp[1]
            }
            
            if wp[0] > maxX {
                maxX = wp[0]
            }
            if wp[1] > maxY {
                maxY = wp[1]
            }
        }
        
        return AABB.init(fromValues: minX, minY, maxX, maxY)
    }
    
    func getPathOBB() -> AABB {
        var minX = Float32.greatestFiniteMagnitude
        var minY = Float32.greatestFiniteMagnitude
        var maxX = -Float32.greatestFiniteMagnitude
        var maxY = -Float32.greatestFiniteMagnitude
        
        let renderPoints: [PathPoint] = points
        for point in renderPoints {
            var t = point.translation
            var x = t[0]
            var y = t[1]
            if x < minX {
                minX = x
            }
            if y < minY {
                minY = y
            }
            if x > maxX {
                maxX = x
            }
            if y > maxY {
                maxY = y
            }
            
            if point is CubicPathPoint {
                let cpp = point as! CubicPathPoint
                t = cpp.inPoint
                x = t[0]
                y = t[1]
                if x < minX {
                    minX = x
                }
                if y < minY {
                    minY = y
                }
                if x > maxX {
                    maxX = x
                }
                if y > maxY {
                    maxY = y
                }
                
                t = cpp.outPoint
                x = t[0]
                y = t[1]
                if x < minX {
                    minX = x
                }
                if y < minY {
                    minY = y
                }
                if x > maxX {
                    maxX = x
                }
                if y > maxY {
                    maxY = y
                }
            }
        }
        
        return AABB.init(fromValues: minX, minY, maxX, maxY)
        
    }
    
    func updateShape() {
        if let shape = self.shape {
            _ = shape.removePath(self)
        }

        var possibleShape = parent
        while let possible = possibleShape,
            !(possibleShape is ActorShape) {
                possibleShape = possible.parent
        }
        if let possible = possibleShape {
            self.shape = (possible as! ActorShape)
            _ = self.shape!.addPath(self)
        } else {
            shape = nil
        }
        isRootPath = shape === parent
    }
    
    func invalidateDrawable() {
        self.invalidatePath()
        if let s = shape {
            s.invalidateShape()
        }
    }
    
    /// This function returns the [List] of points that form this path.
    /// They can be either Straight points or Cubic points, depending on
    /// whether the path is made of Segments or of Bezier curves.
    var pathPoints: [PathPoint] {
        let pts = deformedPoints
        guard !pts.isEmpty else {
            return []
        }
        
        var pathPoints = [PathPoint]()
        let pc = pts.count
        
        let arcConstant: Float32 = 0.55
        let iarcConstant = 1.0 - arcConstant
        var previous = isClosed ? pts.last : nil
        
        for i in 0 ..< pc {
            let point = pts[i]
            switch point.type {
            case .Straight:
                let straightPoint = point as! StraightPathPoint
                let radius = straightPoint.radius
                if radius > 0 {
                    if !isClosed && (i == 0 || i == pc - 1) {
                        pathPoints.append(point)
                        previous = point
                    } else {
                        let next = pts[(i+1)%pc]
                        let prevPoint = previous is CubicPathPoint ? (previous as! CubicPathPoint).outPoint : previous!.translation
                        let nextPoint = next is CubicPathPoint ? (next as! CubicPathPoint).inPoint : next.translation
                        let pos = point.translation
                        
                        let toPrev = Vec2D.subtract(Vec2D(), prevPoint, pos)
                        let toPrevLength = Vec2D.length(toPrev)
                        toPrev[0] /= toPrevLength
                        toPrev[1] /= toPrevLength
                        
                        let toNext = Vec2D.subtract(Vec2D(), nextPoint, pos)
                        let toNextLength = Vec2D.length(toNext)
                        toNext[0] /= toNextLength
                        toNext[1] /= toNextLength
                        
                        let renderRadius = min(toPrevLength, min(toNextLength, Float32(radius)))
                        var translation = Vec2D.scaleAndAdd(Vec2D(), pos, toPrev, renderRadius)
                        pathPoints.append(CubicPathPoint.init(fromValues: translation, translation, Vec2D.scaleAndAdd(Vec2D(), pos, toPrev, iarcConstant * renderRadius)))
                        
                        translation = Vec2D.scaleAndAdd(Vec2D(), pos, toNext, renderRadius)
                        previous = CubicPathPoint.init(fromValues: translation, Vec2D.scaleAndAdd(Vec2D(), pos, toNext, iarcConstant * renderRadius), translation)
                        pathPoints.append(previous!)
                    }
                } else {
                    pathPoints.append(point)
                    previous = point
                }
                break
            default:
                pathPoints.append(point)
                previous = point
                break
            }
        }
        
        return pathPoints
    }
    
    func basePathResolve() {
        updateShape()
    }
}

public class ActorProceduralPath: ActorNode, ActorBasePath {
    public var _isClosed: Bool = false

    /// Default empty values
    public var shape: ActorShape? = nil
    public var isRootPath: Bool = false
    public var points: [PathPoint] { return [] }
    ///

    public var isClosed: Bool { return _isClosed }
    public var pathTransform: Mat2D? { return worldTransform }
    public var deformedPoints: [PathPoint] { return points }
    
    var _width: Double = 0.0
    var _height: Double = 0.0
    
    var width: Double {
        get { return _width }
        set {
            if newValue != _width {
                _width = newValue
                invalidateDrawable()
            }
        }
    }
    
    var height: Double {
        get { return _height }
        set {
            if newValue != _height {
                _height = newValue
                invalidateDrawable()
            }
        }
    }
    
    public override init() {}
    
    public func invalidatePath() {
        preconditionFailure("Invalidating an ActorProceduralPath!")
    }
    
    func copyPath(_ node: ActorBasePath, _ resetArtboard: ActorArtboard) {
        guard let nodePath = node as? ActorProceduralPath else {
            fatalError("Copying nodePath that is not an ActorProceduralPath!")
        }
        
        copyNode(nodePath, resetArtboard)
        _width = nodePath.width
        _height = nodePath.height
    }
    
    override func onDirty(_ dirt: UInt8) {
        super.onDirty(dirt)
        // We transformed, make sure parent is invalidated.
        if let shape = self.shape {
            shape.invalidateShape()
        }
    }
    
    override public func completeResolve() {
        basePathResolve()
    }
    
}

public class ActorPath: ActorNode, ActorSkinnable, ActorBasePath {
    
    public var shape: ActorShape? = nil
    public var isRootPath: Bool = false
    
    public var isHidden: Bool = false
    private(set) var _isClosed: Bool = false
    private var _points: [PathPoint] = []
    var vertexDeform: [Float32]?
    var skin: ActorSkin?
    let VertexDeformDirty: UInt8 = 1 << 1
    var _connectedBones: [SkinnedBone]?
    
    public var points: [PathPoint] { return _points }
    public var isClosed: Bool { return _isClosed }
    
    public var pathTransform: Mat2D? {
        return self.isConnectedToBones
            ? nil
            : worldTransform
    }
    
    var isPathInWorldSpace: Bool { return self.isConnectedToBones }
    
    public var deformedPoints: [PathPoint] {
        if !isConnectedToBones || skin == nil {
            return _points
        }
        
        let boneMatrices = skin!.boneMatrices
        var deformed = [PathPoint]()
        for point in _points {
            deformed.append(point.skin(world: worldTransform, bones: boneMatrices)!)
        }
        return deformed
    }
    
    public override init() {}
    
    override func onDirty(_ dirt: UInt8) {
        super.onDirty(dirt)
        if parent is ActorShape {
            parent!.invalidateShape()
        }
    }
    
    func makeVertexDeform() {
        if vertexDeform != nil {
//            print("ActorPath::makeVertexDeform() - VERTEX DEFORM ALREADY SPECIFIED!")
            return
        }
        var length = 0
        for point in points {
            length += 2 + ((point.type == .Straight) ? 1 : 4)
        }
        
        var vertices = Array<Float32>.init(repeating: 0, count: length)
        var readIdx = 0
        for point in points {
            vertices[readIdx] = point.translation[0]
            readIdx += 1
            vertices[readIdx] = point.translation[1]
            readIdx += 1
            if point.type == .Straight {
                // radius
                vertices[readIdx] = Float32((point as! StraightPathPoint).radius)
                readIdx += 1
            } else {
                // in/out
                let cubicPoint = point as! CubicPathPoint
                vertices[readIdx] = cubicPoint.inPoint[0]
                readIdx += 1
                vertices[readIdx] = cubicPoint.inPoint[1]
                readIdx += 1
                vertices[readIdx] = cubicPoint.outPoint[0]
                readIdx += 1
                vertices[readIdx] = cubicPoint.outPoint[1]
                readIdx += 1
            }
        }
        vertexDeform = vertices
    }
    
    public func invalidatePath() {
        // Up to the implementation.
    }
    
    func markVertexDeformDirty() {
        if artboard != nil {
            _ = artboard?.addDirt(self, value: VertexDeformDirty, recurse: false)
        }
    }
    
    override func update(dirt: UInt8) {
        if
            let vertexDeform = vertexDeform,
            (dirt & VertexDeformDirty) == VertexDeformDirty
        {
            var readIdx = 0
            for point in _points {
                point.translation[0] = vertexDeform[readIdx]
                readIdx += 1
                point.translation[1] = vertexDeform[readIdx]
                readIdx += 1
                switch (point.type) {
                case PointType.Straight:
                    (point as! StraightPathPoint).radius = Double(vertexDeform[readIdx])
                    readIdx += 1
                    break;
                    
                default:
                    let cubicPoint = point as! CubicPathPoint;
                    cubicPoint.inPoint[0] = vertexDeform[readIdx]
                    readIdx += 1
                    cubicPoint.inPoint[1] = vertexDeform[readIdx]
                    readIdx += 1
                    cubicPoint.outPoint[0] = vertexDeform[readIdx]
                    readIdx += 1
                    cubicPoint.outPoint[1] = vertexDeform[readIdx]
                    readIdx += 1
                    break
                }
            }
        }
        invalidateDrawable()
        
        super.update(dirt: dirt)
    }
    
    func readPath(_ artboard: ActorArtboard, _ reader: StreamReader) {
        self.readNode(artboard, reader)
        self.readSkinnable(artboard, reader)
        
        self.isHidden = !reader.readBool(label: "isVisible")
        self._isClosed = reader.readBool(label: "isClosed")
        
        reader.openArray(label: "points")
        let pointCount = Int(reader.readUint16Length())
        self._points = Array<PathPoint>()
        
        for i in 0 ..< pointCount {
            reader.openObject(label: "point")
            var point: PathPoint?
            let type: PointType = PointType(rawValue: Int(reader.readUint8(label: "pointType")))!
            switch type {
            case PointType.Straight:
                point = StraightPathPoint()
                break
            default:
                point = CubicPathPoint(ofType: type)
                break
            }
            if point == nil {
                fatalError("Invalid point type: \(type)")
            } else {
                point!.read(reader: reader, isConnectedToBones: self.isConnectedToBones)
            }
            reader.closeObject()
            
            self._points.insert(point!, at: i)
        }
        reader.closeArray()
    }
    
    override func makeInstance(_ resetArtboard: ActorArtboard) -> ActorComponent {
        let instancePath = ActorPath()
        instancePath.copyPath(self, resetArtboard)
        return instancePath
    }
    
    func copyPath(_ node: ActorBasePath, _ resetArtboard: ActorArtboard) {
        let nodePath = node as! ActorPath
        (self as ActorNode).copyNode(nodePath, resetArtboard)
        copySkinnable(nodePath, resetArtboard)
        isHidden = nodePath.isHidden
        _isClosed = nodePath._isClosed
        
        let pointCount = nodePath._points.count
        
        _points = [PathPoint]()
        for i in 0 ..< pointCount {
            _points.insert(nodePath._points[i].makeInstance(), at: i)
        }
        
        if let vd = nodePath.vertexDeform {
            vertexDeform = vd
        }
    }
    
    override func resolveComponentIndices(_ components: [ActorComponent?]) {
        super.resolveComponentIndices(components)
        resolveSkinnable(components)
    }

    override public func completeResolve() {
        basePathResolve()
    }
}
