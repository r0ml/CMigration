// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import Darwin

public func getShell() -> String {
  let tmpShell = getenv("SHELL")
  return tmpShell ?? Darwin._PATH_BSHELL
}

public var scArgMax : Int {
  return Darwin.sysconf(Darwin._SC_ARG_MAX)
}
