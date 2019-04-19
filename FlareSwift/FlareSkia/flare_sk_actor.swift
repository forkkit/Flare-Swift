//
//  flare_sk_actor.swift
//  FlareSkia
//
//  Created by Umberto Sonnino on 2/22/19.
//  Copyright © 2019 2Dimensions. All rights reserved.
//

import Foundation
import Skia

public class FlareSkActor: Actor {
    public var maxTextureIndex: Int = 0
    public var _version: Int = -1
    public var _artboardCount: Int = 0
    /// List of
    public var images: [OpaquePointer]?
    public var _artboards: [ActorArtboard?] = []
    
    public var artboard: FlareSkArtboard? {
        return _artboards.count > 0 ? (_artboards.first as! FlareSkArtboard) : nil
    }
    public init() {}
    
    public func makeArtboard() -> ActorArtboard {
        return FlareSkArtboard(actor: self)
    }
    
    public func makeShapeNode() -> ActorShape {
        return FlareSkShape()
    }
    
    public func makePathNode() -> ActorPath {
        return FlareSkActorPath()
    }
    
    public func makeRectangle() -> ActorRectangle {
        return FlareSkRectangle()
    }
    
    public func makeTriangle() -> ActorTriangle {
        return FlareSkTriangle()
    }
    
    public func makeStar() -> ActorStar {
        return FlareSkStar()
    }
    
    public func makePolygon() -> ActorPolygon {
        return FlareSkPolygon()
    }
    
    public func makeEllipse() -> ActorEllipse {
        return FlareSkEllipse()
    }

    public func makeColorFill() -> ColorFill {
        return FlareSkColorFill()
    }

    public func makeColorStroke() -> ColorStroke {
        return FlareSkColorStroke()
    }

    public func makeGradientFill() -> GradientFill {
        return FlareSkGradientFill()
    }

    public func makeGradientStroke() -> GradientStroke {
        return FlareSkGradientStroke()
    }

    public func makeRadialFill() -> RadialGradientFill {
        return FlareSkRadialFill()
    }

    public func makeRadialStroke() -> RadialGradientStroke {
        return FlareSkRadialStroke()
    }
    
    public func makeImageNode() -> ActorImage {
        return FlareSkImage()
    }
    
    func loadData(_ data: Data) {
        self.load(data: data)
    }
    
    public func onImageData(_ rawData: [Data]) {
        images = []
        for imageData in rawData {
            imageData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                let skData = sk_data_new_with_copy(buffer.baseAddress, imageData.count)
                images!.append(sk_image_new_from_encoded(skData, nil))
                sk_data_unref(skData)
            }
        }
    }
    
    public func dispose(){
        guard let images = images else {
            return
        }
        
        for image in images {
            sk_image_unref(image)
        }
    }
    
    public func loadFromBundle(filename: String) -> Bool {
        let endIndex = filename.index(filename.endIndex, offsetBy: -4)
        let fname = String(filename.prefix(upTo: endIndex))
        if let path = Bundle.main.path(forResource: fname, ofType: "flr") {
            if let data = FileManager.default.contents(atPath: path) {
                self.load(data: data)
                return true
            }
        }
        return false
    }
}