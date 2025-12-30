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
  func runCommand(_ options : CommandOptions) async throws(CmdErr)
  var usage : String { get }
  init()
}

extension ShellCommand {

  public static func main() async {
    // set up the locale for commands
    setlocale(LC_ALL, "")
    let z = await Self().main()
    exit(z)
  }
  
  public func main() async -> Int32 {
    var options : CommandOptions
    do {
      options = try await parseOptions()
    } catch(let e) {
      var fh = FileDescriptor.standardError
      if (!e.message.isEmpty) { print("\(e.message)", to: &fh) }
      print(usage, to: &fh) 
      return Int32(e.code)
    }
    
    do {
      try await runCommand(options)
      return 0
    } catch(let e) {
      var fh = FileDescriptor.standardError
      if (!e.message.isEmpty) { print("\(String(cString: getprogname()!)): \(e.message)", to: &fh) }
      return Int32(e.code)
    }
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

extension Character {
  public static func from(_ c : Int8?) -> Character? {
    guard let c else { return nil }
    return Character(UnicodeScalar(UInt8(c)))
  }

  public static func from(_ c : UInt8?) -> Character? {
    guard let c else { return nil }
    return Character(UnicodeScalar(c))
  }
}

/*
#if swift(>=6.0)

 extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
      let data = Data(string.utf8)
      self.write(data)
    }
  }
#else
  extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
      let data = Data(string.utf8)
      self.write(data)
    }
  }
#endif
*/


public func WEXITSTATUS(_ x : Int32) -> Int32 { return (x >> 8) & 0x0ff }
public func WIFEXITED(_ x : Int32) -> Bool { return (x & 0x7f) == 0 }
public func WIFSIGNALED(_ x : Int32) -> Bool {
  let y = x & 0x7f
  return y != _WSTOPPED && y != 0
}

