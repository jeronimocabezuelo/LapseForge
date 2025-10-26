//
//  UIImage+Extension.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 26/10/25.
//

import UIKit.UIImage

extension UIImage {
    /// Returns JPEG data not exceeding `maxBytes` by adjusting compression quality and, if needed, downscaling.
    /// - Parameters:
    ///   - maxMB: Maximum allowed size in MB.
    /// - Returns: JPEG Data within the size constraint, or nil if unable.
    func jpegData(maxMB: Double) -> Data? {
        precondition(maxMB > 0, "maxMB must be > 0")
        let maxBytes = Int(maxMB * 1024 * 1024)
        //        print("Buscando compressionQuality con maximo: \(maxBytes)")
        
        guard let maxData = self.jpegData(compressionQuality: 1.0) else { return nil }
        if maxData.count <= maxBytes {
            //            print("compressionQuality: 1.0, Bytes: \(maxData.count)")
            return maxData
        }
        guard let minData = self.jpegData(compressionQuality: 0.0) else { return nil }
        if minData.count > maxBytes {
            //            print("compressionQuality: 0.0, Bytes: \(minData.count)")
            return minData
        }
        
        var low: CGFloat = 0.0
        var high: CGFloat = 1.0
        var bestUnder: (q: CGFloat, data: Data)? = (0.0, minData)
        var lastLowData: Data = minData
        var lastHighData: Data = maxData
        
        // Iterate until quality interval is sufficiently small
        while true {
            let mid = (low + high) / 2
            guard let data = self.jpegData(compressionQuality: mid) else { break }
            
            //            print("compressionQuality: \(mid), Bytes: \(data.count)")
            
            if data.count > maxBytes {
                high = mid
                lastHighData = data
            } else {
                low = mid
                lastLowData = data
                bestUnder = (mid, data)
            }
            if (high - low) < 0.01 { // stop when interval is small
                break
            }
        }
        
        // Decide between the two boundary datas: pick the one under the limit, preferring the larger size (better quality)
        if let bestUnder {
            return bestUnder.data
        }
        
        // Fallback safety: if both sides exist, choose the smaller of the last two
        let candidates: [Data] = [lastLowData, lastHighData]
        return candidates.min(by: { $0.count < $1.count })
    }
    
    enum ImageResolution {
        case p4K
        case p1080
        case p720
        case p480
        case p360
        case p240
        case p144
        case custom(maxDimension: CGFloat)
        
        var maxDimension: CGFloat {
            switch self {
            case .p4K: return 3840
            case .p1080: return 1920
            case .p720: return 1280
            case .p480: return 854
            case .p360: return 640
            case .p240: return 426
            case .p144: return 256
            case .custom(let maxDimension): return maxDimension
            }
        }
    }
    
    /// Redimensiona la imagen a la resolución especificada, manteniendo la relación de aspecto.
    func resized(to resolution: ImageResolution) -> UIImage? {
        let maxDim = resolution.maxDimension
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if aspectRatio > 1 {
            // Imagen apaisada
            newSize = CGSize(width: maxDim, height: maxDim / aspectRatio)
        } else {
            // Imagen vertical
            newSize = CGSize(width: maxDim * aspectRatio, height: maxDim)
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        
        //        let previousSize = self.jpegData(compressionQuality: 1)?.count
        let result = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        //        let resultSize = result.jpegData(compressionQuality: 1)?.count
        //        print("Resizing to \(newSize), previousSize: \(previousSize), resultSize: \(resultSize)")
        
        return result
    }
}
