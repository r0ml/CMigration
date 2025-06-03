// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

@_exported import Darwin

public func getenv(_ name: String) -> String? {
  if let a = Darwin.getenv(name) {
    return String(cString: a)
  } else {
    return nil
  }
}
