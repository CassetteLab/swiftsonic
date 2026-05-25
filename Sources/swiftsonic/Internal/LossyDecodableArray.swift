// LossyDecodableArray.swift — SwiftSonic (Internal)
//
// A Decodable wrapper for arrays that skips malformed items rather than
// propagating errors and discarding all results.
//
// The Wrapper pattern is the key: Wrapper.init(from:) never throws,
// so the UnkeyedDecodingContainer cursor always advances past each element,
// even if the inner Element decode fails.

import Foundation
import os

private let _lossyDecodingLogger = Logger(subsystem: "SwiftSonic", category: "Decoding")

// MARK: - LossyDecodableArray

struct LossyDecodableArray<Element: Decodable & Sendable>: Decodable, Sendable {

    let elements: [Element]

    // Never throws — catches Element decode failures internally.
    private struct Wrapper: Decodable {
        let value: Element?
        init(from decoder: any Decoder) throws {
            value = try? Element(from: decoder)
        }
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        var skipped = 0

        while !container.isAtEnd {
            let wrapper = try container.decode(Wrapper.self)
            if let element = wrapper.value {
                result.append(element)
            } else {
                skipped += 1
            }
        }

        if skipped > 0 {
            _lossyDecodingLogger.debug(
                "[\(Element.self)] Skipped \(skipped) malformed item(s) — server may be returning non-standard fields"
            )
        }

        self.elements = result
    }
}

// MARK: - KeyedDecodingContainer helper

extension KeyedDecodingContainer {
    /// Decodes an optional array lossily — skips malformed items instead of
    /// failing the entire array.
    func decodeLossily<T: Decodable & Sendable>(
        _ type: [T].Type,
        forKey key: Key
    ) throws -> [T]? {
        guard contains(key) else { return nil }
        return try decodeIfPresent(LossyDecodableArray<T>.self, forKey: key)?.elements
    }
}
