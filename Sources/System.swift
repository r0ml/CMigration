// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import Darwin

public func getShell() -> String {
  let tmpShell = Environment["SHELL"]
  return tmpShell ?? _PATH_BSHELL
}

public struct Sysconf {
  public static var scArgMax : Int {
    return Darwin.sysconf(Darwin._SC_ARG_MAX)
  }
}
