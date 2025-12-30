// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

public enum ExpandNumberError: Error {
    case invalidFormat
    case overflow
}

public func expand_number(_ input: String) throws -> UInt64 {
    let suffixMultipliers: [Character: UInt64] = [
        "B": 1,         // Bytes
        "K": 1024,      // Kilobytes
        "M": 1024 * 1024, // Megabytes
        "G": 1024 * 1024 * 1024, // Gigabytes
        "T": 1024 * 1024 * 1024 * 1024, // Terabytes
        "P": 1024 * 1024 * 1024 * 1024 * 1024, // Petabytes
        "E": 1024 * 1024 * 1024 * 1024 * 1024 * 1024 // Exabytes
    ]

  let trimmed = input.drop { $0.isWhitespace || $0.isNewline }.uppercased()
    let regex = try! Regex("^([0-9]+)([BKMGTPE]?)$")

    guard let match = try regex.firstMatch(in: trimmed) else {
        throw ExpandNumberError.invalidFormat
    }

  guard let numberString = match.output[1].substring else {
    throw ExpandNumberError.invalidFormat
  }

    guard let number = UInt64(numberString) else {
        throw ExpandNumberError.invalidFormat
    }

    var multiplier: UInt64 = 1
  if let mr = match.output[2].range {
      if let suffix = trimmed[mr].first {
        multiplier = suffixMultipliers[suffix] ?? 1
      } else {
          multiplier = 1
      }
    }

    let result = number.multipliedReportingOverflow(by: multiplier)
    if result.overflow {
        throw ExpandNumberError.overflow
    }

    return result.partialValue
}
