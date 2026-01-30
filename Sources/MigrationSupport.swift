/*
  The MIT License (MIT)
  Copyright © 2024 Robert (r0ml) Lefkowitz

  Permission is hereby granted, free of charge, to any person obtaining a copy of this software
  and associated documentation files (the “Software”), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
  and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
  subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
  OR OTHER DEALINGS IN THE SOFTWARE.
 */

@_exported import SystemPackage

import locale_h
import Darwin

public struct CmdErr : Error {
  public var code : Int
  public var message : String
  
  public init(_ code : Int, _ message : String = "") {
    self.code = code
    self.message = message
  }
}

public protocol ShellCommand {
  associatedtype CommandOptions
  func parseOptions() async throws(CmdErr) -> CommandOptions
  func runCommand() async throws(CmdErr)
  var usage : String { get }
  var options : CommandOptions! { get set }
  init()
}

public extension ShellCommand {

  /// the static main to create an instance of the ShellCommand and invoke the instance main method
  static func main() async {
    // set up the locale for commands
    setlocale(LC_ALL, "")
    var m = Self()
    let z = await m.main()
    exit(z)
  }

  /// the main function on an instance of the command so that it can access instance variables
  /// returns the exit code for the command
  mutating func main() async -> Int32 {
    do {
      options = try await parseOptions()
    } catch(let e) {
      var fh = FileDescriptor.standardError
      if (!e.message.isEmpty) { print("\(e.message)", to: &fh) }
      print(usage, to: &fh) 
      return Int32(e.code)
    }
    
    do {
      try await runCommand()
      return 0
    } catch(let e) {
      var fh = FileDescriptor.standardError
      if (!e.message.isEmpty) { print("\(programName): \(e.message)", to: &fh) }
      return Int32(e.code)
    }
  }

  /// the program name (for error messages)
  var programName : String {
    String(cString: getprogname()!)
  }
}

public func errx(_ a : Int, _ b : String) {
  fputs(basename(CommandLine.unsafeArgv[0]), stderr)
  fputs(": \(b)\n", stderr)
  exit(Int32(a))
}

public func err(_ a : Int, _ b : String?) {
  let c = basename(CommandLine.unsafeArgv[0])
  let cc = c == nil ? "" : "\(String(cString: c!)): "
  let e = String(cString: strerror(errno))
  if let b {
    fputs("\(cc)\(b): \(e)\n", stderr)
  } else {
    fputs("\(cc)\(e)\n", stderr)
  }
  exit(Int32(a))
}

public func warnx(_ b : String) {
  fputs(basename(CommandLine.unsafeArgv[0]), stderr)
  fputs(": \(b)\n", stderr)
}

public func warn(_ b : String) {
  let e = String(cString: strerror(errno))
  fputs(basename(CommandLine.unsafeArgv[0]), stderr)
  fputs(": \(b): \(e)\n", stderr)
}

public func warnc(_ cod : Int32, _ b : String) {
  let e = String(cString: strerror(cod))
  fputs(basename(CommandLine.unsafeArgv[0]), stderr)
  fputs(": \(b): \(e)\n", stderr)
}

/// get a Character from a byte whether the representation is signed or unsigned
extension Character {
  /// get a Character from a byte
  public static func from(_ c : Int8?) -> Character? {
    guard let c else { return nil }
    return Character(UnicodeScalar(UInt8(c)))
  }

  /// get a Character from a byte
  public static func from(_ c : UInt8?) -> Character? {
    guard let c else { return nil }
    return Character(UnicodeScalar(c))
  }
}

public func WEXITSTATUS(_ x : Int32) -> Int32 { return (x >> 8) & 0x0ff }
public func WIFEXITED(_ x : Int32) -> Bool { return (x & 0x7f) == 0 }
public func WIFSIGNALED(_ x : Int32) -> Bool {
  let y = x & 0x7f
  return y != _WSTOPPED && y != 0
}
public func WTERMSIG(_ s: Int32) -> Int32 { return s & 0x7f }

public func uuidString() -> String {
  var u = withUnsafeTemporaryAllocation(of: uuid_t.self, capacity: 1) { p in
    uuid_generate_random(p.baseAddress!)
    return p[0]
  }

  // uuid_unparse_lower writes a 36-char + NUL string
  var buf = [CChar](repeating: 0, count: 37)
  uuid_unparse_lower(&u, &buf)

  return String(platformString: buf)
}
