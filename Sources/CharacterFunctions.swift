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



extension StringProtocol {
  public func wcwidth() -> Int {
    return self.reduce(0) { (sum : Int, scal : Character) in
      let t = scal.wcwidth
      if t > 0 { return sum + Int(t) }
      else { return sum }
    }
  }
}




extension Character {

  public var isEmoji : Bool {
    // Most emoji-presenting characters have at least one scalar with isEmojiPresentation = true
    // or are in the emoji modifier/base ranges
    return self.unicodeScalars.contains { scalar in
      scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
    }
  }

  /// Returns the display width of a Swift `Character`, based on its visible representation in a terminal.
  /// Returns -1 if it contains any control characters.
  public var wcwidth : Int {
    // If any scalar in the cluster is a control character, return -1
    for scalar in self.unicodeScalars {
      let v = scalar.value
      if (v < 0x20) || (v >= 0x7F && v < 0xA0) {
        return -1
      }
    }

    // Count visible column width across all scalars
    var width = 0
    for scalar in self.unicodeScalars {
      width += scalar.wcwidth
    }

    // Many grapheme clusters are emoji or wide and display as a single unit — normalize to 2 if appropriate
    if self.isEmoji && width >= 2 {
      return 2
    }

    return width
  }


  /// Calculates the display width of a character.
  /// Swift does not have a direct equivalent to C's `wcwidth`, so we provide a basic implementation.
/*  public func wcwidth(_ ch: Character) -> Int {
    // Simplified: Most characters occupy width 1. You can enhance this with more accurate width calculations if needed.
    let scalars = String(ch).unicodeScalars
    for scalar in scalars {
      if scalar.properties.isIdeographic {
        return 2
      }
    }
    return 1
  }
*/

  /// Returns true if the character is printable and not a space,
  /// equivalent to POSIX `iswgraph`.
  public var iswgraph : Bool {
      // Reject control characters or unassigned scalars
      for scalar in self.unicodeScalars {
          switch scalar.properties.generalCategory {
          case .control, .format, .surrogate, .privateUse, .unassigned,
               .spaceSeparator, .lineSeparator, .paragraphSeparator:
              return false
          default:
              continue
          }
      }

      // Reject characters composed entirely of whitespace
      if self.isWhitespace {
          return false
      }

      return true
  }


  /// Returns `true` if the given Unicode scalar is considered printable.
  /// - Parameter scalar: A UnicodeScalar to test.
  /// - Returns: A Boolean value that is `true` if the scalar is printable.
  public var iswprint : Bool {
      // For ASCII, only characters between space (0x20) and tilde (0x7E) are printable.
    let scalars = self.unicodeScalars
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






}

extension UnicodeScalar {

  /// Approximates scalar width used inside `wcwidth(_:)`
  public var wcwidth : Int {
    // Combining marks
    switch self.properties.generalCategory {
      case .nonspacingMark, .enclosingMark:
        return 0
      default:
        break
    }

    // Emoji with presentation form
    if self.properties.isEmojiPresentation {
      return 2
    }

    // Wide characters (see previous wide ranges)
    let wideRanges: [ClosedRange<UInt32>] = [
      0x1100...0x115F, 0x2329...0x232A, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
      0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF00...0xFF60,
      0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD
    ]
    if wideRanges.contains(where: { $0.contains(self.value) }) {
      return 2
    }

    return 1
  }

  /// Returns `true` if the given Unicode scalar is a printable, non-space character.
  /// This mimics the behavior of POSIX `iswgraph`.
  public var iswgraph : Bool {
      if self.isASCII {
          // ASCII printable non-space: 0x21 ('!') to 0x7E ('~')
          return (0x21...0x7E).contains(self.value)
      } else {
          // Non-ASCII: Must be printable and not in any space category
          switch self.properties.generalCategory {
          case .control, .format, .surrogate, .privateUse, .unassigned,
               .spaceSeparator, .lineSeparator, .paragraphSeparator:
              return false
          default:
              return true
          }
      }
  }

}



public func validatedStringFromUTF16Buffer(_ buffer: [UInt16]) -> String? {
    var decoder = UTF16()
    var iterator = buffer.makeIterator()
    var string = ""

    decodeLoop: while true {
        switch decoder.decode(&iterator) {
        case .scalarValue(let scalar):
            string.unicodeScalars.append(scalar)
        case .emptyInput:
            break decodeLoop
        case .error:
            return nil  // invalid UTF-16
        }
    }

    return string
}

func firstInvalidUTF8Index(in bytes: [UInt8]) -> Int? {
    var decoder = UTF8()
    var iterator = bytes.makeIterator()
    var index = 0

    while true {
        let decoding = decoder.decode(&iterator)
        switch decoding {
        case .scalarValue:
            // Valid scalar, move to next
            index += 1
        case .emptyInput:
            // Reached end of input
            return nil
        case .error:
            // Found invalid byte
            return index
        }
    }
}

func getStringEncoding() -> (any Unicode.Encoding.Type)? {
  let codeset = String(cString: nl_langinfo(CODESET))
    switch codeset.uppercased() {
    case "UTF-8":
        return UTF8.self
    case "ISO-8859-1", "LATIN1":
        return ISOLatin1.self
    case "UTF-16":
        return UTF16.self
//    case "US-ASCII", "ASCII":
//        return .ascii
    default:
        return nil
    }
}
