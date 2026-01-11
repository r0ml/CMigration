// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

public extension OptionSet {
  func containsAny(of: Self) -> Bool {
    return !self.intersection(of).isEmpty
  }
}
