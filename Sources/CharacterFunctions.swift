// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import SystemPackage


public struct ForwardParserX : Unicode.Parser {
  public init() {}
  public mutating func parseScalar<I>(from input: inout I) -> Unicode.ParseResult<CollectionOfOne<UInt8>> where I : IteratorProtocol, I.Element == UInt8 {
    if let z = input.next() {
      let x = CollectionOfOne(UInt8(z) )
      return Unicode.ParseResult.valid(x)
    } else {
      return Unicode.ParseResult.emptyInput
    }
  }
  
  public typealias Encoding = ISOLatin1
}

public struct ReverseParserX : Unicode.Parser {
  public init() {}
  public mutating func parseScalar<I>(from input: inout I) -> Unicode.ParseResult<CollectionOfOne<UInt8>> where I : IteratorProtocol, I.Element == UInt8 {
    if let z = input.next() {
      let x = CollectionOfOne(UInt8(z) )
      return Unicode.ParseResult.valid(x)
    } else {
      return Unicode.ParseResult.emptyInput
    }
  }
  
  public typealias Encoding = ISOLatin1
  
  
}

public struct ISOLatin1: Unicode.Encoding {
  public static let encodedReplacementCharacter: CollectionOfOne<UInt8> = .init(UInt8(0))
  
  public static func decode(_ content: CollectionOfOne<UInt8>) -> Unicode.Scalar {
    return Unicode.Scalar(content.first!)
  }
  
  public static func encode(_ content: Unicode.Scalar) -> CollectionOfOne<UInt8>? {
    return CollectionOfOne( UInt8(content.value) )
  }
  
  public typealias CodeUnit = UInt8
  public typealias EncodedScalar = CollectionOfOne<UInt8>
  public typealias ForwardParser = ForwardParserX
  public typealias ReverseParser = ReverseParserX
  
/*
  /// Decodes a single ISO Latin 1 code unit into a Unicode scalar.
  static func decode(_ input: EncodedScalar) -> UnicodeDecodingResult {
        guard let first = input.first else {
            return .emptyInput
        }
        let scalar = UnicodeScalar(first)
        return .scalarValue(scalar)
    }

    /// Encodes a single Unicode scalar into an ISO Latin 1 code unit.
  static func encode(_ scalar: UnicodeScalar) -> EncodedScalar {
        precondition(scalar.value <= 0xFF, "Scalar out of ISO-8859-1 range")
        return CollectionOfOne(UInt8(scalar.value))
 }
 */
}

public func regerror(_ n : Int32, _ regx : regex_t )  -> String {
  var re = regx
  let s = withUnsafeMutablePointer(to: &re) { rr in
     regerror(n, rr, nil, 0)
  }
  
  let p = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: s) { b in
    withUnsafeMutablePointer(to: &re) {rr in
      let _ = regerror(n, rr, b.baseAddress!, s)
      return String(cString: b.baseAddress!)
    }
  }
  return p
}

public func posixRename(from oldPath: String, to newPath: String) throws {
    if rename(oldPath, newPath) != 0 {
        // If an error occurs, capture it using errno
//        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
      throw Errno(rawValue: errno)
    }
}

/// Calculates the display width of a character.
/// Swift does not have a direct equivalent to C's `wcwidth`, so we provide a basic implementation.
public func wcwidth(_ ch: Character) -> Int {
  // Simplified: Most characters occupy width 1. You can enhance this with more accurate width calculations if needed.
  let scalars = String(ch).unicodeScalars
  for scalar in scalars {
    if scalar.properties.isIdeographic {
      return 2
    }
  }
  return 1
}

/// Determines the display width of a Unicode character.
/// - Parameter wc: The Unicode scalar to measure.
/// - Returns: The width of the character in column positions.
/*
func wcwidth(_ wc: Unicode.Scalar) -> Int {
  // Simplified version: Most characters occupy width 1.
  // You can enhance this function to handle wide characters appropriately.
  if wc.properties.isEmoji {
    return 2
  } else if wc.properties.generalCategory == .control {
    return 0
  } else {
    return 1
  }
}
*/


/// Returns `true` if the given Unicode scalar is considered printable.
/// - Parameter scalar: A UnicodeScalar to test.
/// - Returns: A Boolean value that is `true` if the scalar is printable.
public func iswprint(_ char: Character) -> Bool {
    // For ASCII, only characters between space (0x20) and tilde (0x7E) are printable.
  let scalars = char.unicodeScalars
  if scalars.count > 1 { return true }
  let scalar = scalars.first!
    if scalar.isASCII {
      return scalar.value >= 0x20 && scalar.value <= 0x7E
    } else {
        // For non-ASCII characters, we consider the scalar printable if its Unicode
        // general category is not one of the following:
        //   - Control (.control)
        //   - Format (.format)
        //   - Surrogate (.surrogate)
        //   - Private Use (.privateUse)
        //   - Unassigned (.unassigned)
      if scalar.value < 256 { return false }
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned:
            return false
        default:
            return true
        }
    }
}


public func cFormat(_ format: String, _ args: CVarArg...) -> String {
    let bufferSize = 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)

  return buffer.withUnsafeMutableBufferPointer { ptr in
    let n = withVaList(args) { vaPtr in
      vsnprintf(ptr.baseAddress!, bufferSize, format, vaPtr)
    }
    let pp = UnsafeBufferPointer(start: ptr.baseAddress!, count: Int(n) )
    return String(decoding: pp, as: ISOLatin1.self)
  }
}

public func cFormat(_ format: String, _ args: String) -> String {
  return args.withCString { c in cFormat(format, c) }
}

public func readFileAsString(at path: String) throws -> String {
    let fd = try FileDescriptor.open(path, .readOnly)
    defer { try? fd.close() }

    var content = [UInt8]()
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
        let bytesRead = try buffer.withUnsafeMutableBytes {
            try fd.read(into: $0)
        }
        if bytesRead == 0 { break }
        content.append(contentsOf: buffer[..<bytesRead])
    }

    // Decode as UTF-8
    return String(decoding: content, as: UTF8.self)
}


extension Substring {
    public func trimming(_ shouldTrim: [Character]) -> Substring {
        var start = startIndex
        var end = endIndex

      while start < end && shouldTrim.contains(self[start]) {
            formIndex(after: &start)
        }

      while end > start && shouldTrim.contains(self[index(before: end)]) {
            formIndex(before: &end)
        }

        return self[start..<end]
    }
}
