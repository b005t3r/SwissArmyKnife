//
//  File.swift
//  SwissArmyKnife
//
//  Created by Łukasz Łazarecki on 27/02/2026.
//

import Foundation
import CoreMedia

#if os(iOS)
@available(iOS, introduced: 11.0, obsoleted: 16.0)
extension CMTime: Hashable {
    public var hashValue: Int {
        get {
            var hasher = Hasher()
            
            hasher.combine(value)
            hasher.combine(timescale)
            hasher.combine(flags.rawValue)
            hasher.combine(epoch)

            return hasher.finalize()
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(timescale)
        hasher.combine(flags.rawValue)
        hasher.combine(epoch)
    }
}
#endif
