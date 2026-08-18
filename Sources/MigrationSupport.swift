
/*
  The MIT License (MIT)
  Copyright © 2024 Robert (r0ml) Lefkowitz

  Permission is hereby granted, free of charge, to any person obtaining a copy of this software
  and associated documentation files (the "Software"), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
  and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
  subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
  OR OTHER DEALINGS IN THE SOFTWARE.
 */

@_exported import System

import locale_h
import Darwin

/// An error type used by shell command implementations to signal a non-zero exit and an optional message.
public struct CmdErr : Error {
  /// The process exit code that should be returned to the shell.
  public var code : Int
  /// A human-readable description of the error, written to standard error before exiting.
  public var message : String
  
  /// Creates a `CmdErr` with the given exit code and message.
  ///
  /// - Parameters:
  ///   - code: The exit code.
  ///   - message: A description of the error. Defaults to an empty string.
  public init(_ code : Int, _ message : String = "") {
    self.code = code
    self.message = message
  }
}

/// A protocol that models a POSIX-style shell command with option parsing and execution.
///
/// Conforming types provide an associated `CommandOptions` type, implement option
/// parsing via ``parseOptions()``, and implement the command body via ``runCommand()``.
public protocol ShellCommand {
  /// The parsed options type returned by ``parseOptions()``.
  associatedtype CommandOptions
  /// Parses command-line arguments and returns the typed options.
  ///
  /// - Throws: ``CmdErr`` if the arguments are invalid.
  func parseOptions() async throws(CmdErr) -> CommandOptions
  /// Executes the command using the previously parsed options.
  ///
  /// - Throws: ``CmdErr`` if the command fails.
  func runCommand() async throws(CmdErr)
  /// A brief usage string printed to standard error when option parsing fails.
  var usage : String { get }
  /// The parsed options, set by the default ``main()`` implementation before ``runCommand()`` is called.
  var options : CommandOptions! { get set }
  /// A no-argument initializer required so the default ``main()`` can construct an instance.
  init()
}

public extension ShellCommand {

  /// The static entry point that creates an instance of the conforming type and runs it.
  ///
  /// Sets the locale to `""` (the user's environment locale), then calls the instance
  /// ``main()`` method and exits with its return value.
  static func main() async {
    
    setlocale(LC_ALL, "")
    
    var m = Self()
    let z = await m.main()
    exit(z)
  }

  /// Parses options then runs the command, returning the appropriate exit code.
  ///
  /// Writes the error message and usage string to standard error if option parsing fails.
  /// Writes the error message to standard error if the command itself fails.
  ///
  /// - Returns: `0` on success, or the non-zero exit code from the thrown ``CmdErr``.
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

  /// The name of the running program, obtained from `getprogname(3)`.
  var programName : String {
    String(cString: getprogname()!)
  }
}

/// Prints a formatted error message to standard error and exits with the given code.
///
/// The message is prefixed with the program's `basename`.
///
/// - Parameters:
///   - a: The exit code.
///   - b: The error message to print.
/// - Returns: Never returns.
public func errx(_ a : Int, _ b : String) -> Never {
  fputs(basename(CommandLine.unsafeArgv[0]), stderr)
  fputs(": \(b)\n", stderr)
  exit(Int32(a))
}

/// Prints an error message and the POSIX `strerror` description to standard error, then exits.
///
/// - Parameters:
///   - a: The exit code.
///   - b: An optional context string prepended to the `strerror` description.
/// - Returns: Never returns.
public func err(_ a : Int, _ b : String?) -> Never {
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

/// Prints a warning message to standard error without exiting.
///
/// The message is prefixed with the program's `basename`.
///
/// - Parameter b: The warning message.
public func warnx(_ b : String) {
  fputs(basename(CommandLine.unsafeArgv[0]), stderr)
  fputs(": \(b)\n", stderr)
}

/// Prints a warning message and the POSIX `strerror` description to standard error without exiting.
///
/// - Parameter b: The warning context string.
public func warn(_ b : String) {
  let e = String(cString: strerror(errno))
  fputs(basename(CommandLine.unsafeArgv[0]), stderr)
  fputs(": \(b): \(e)\n", stderr)
}

/// Prints a warning message and the `strerror` description for the given code to standard error without exiting.
///
/// - Parameters:
///   - cod: The `errno` code to describe.
///   - b: The warning context string.
public func warnc(_ cod : Int32, _ b : String) {
  let e = String(cString: strerror(cod))
  fputs(basename(CommandLine.unsafeArgv[0]), stderr)
  fputs(": \(b): \(e)\n", stderr)
}

/// Helpers for constructing a `Character` from a raw byte value.
extension Character {
  /// Creates a `Character` from a signed byte, or returns `nil` if the input is `nil`.
  ///
  /// - Parameter c: An `Int8` byte value, or `nil`.
  /// - Returns: The corresponding `Character`, or `nil`.
  public static func from(_ c : Int8?) -> Character? {
    guard let c else { return nil }
    return Character(UnicodeScalar(UInt8(c)))
  }

  /// Creates a `Character` from an unsigned byte, or returns `nil` if the input is `nil`.
  ///
  /// - Parameter c: A `UInt8` byte value, or `nil`.
  /// - Returns: The corresponding `Character`, or `nil`.
  public static func from(_ c : UInt8?) -> Character? {
    guard let c else { return nil }
    return Character(UnicodeScalar(c))
  }
}

/// Extracts the exit status from a `waitpid(2)` status value.
///
/// Equivalent to the C macro `WEXITSTATUS(x)`.
///
/// - Parameter x: The raw wait status value.
/// - Returns: The 8-bit exit code.
public func WEXITSTATUS(_ x : Int32) -> Int32 { return (x >> 8) & 0x0ff }

/// Returns `true` if the process terminated normally (not by a signal).
///
/// Equivalent to the C macro `WIFEXITED(x)`.
///
/// - Parameter x: The raw wait status value.
/// - Returns: `true` if the process exited normally.
public func WIFEXITED(_ x : Int32) -> Bool { return (x & 0x7f) == 0 }

/// Returns `true` if the process was terminated by a signal.
///
/// Equivalent to the C macro `WIFSIGNALED(x)`.
///
/// - Parameter x: The raw wait status value.
/// - Returns: `true` if the process was killed by a signal.
public func WIFSIGNALED(_ x : Int32) -> Bool {
  let y = x & 0x7f
  return y != _WSTOPPED && y != 0
}

/// Extracts the signal number from a `waitpid(2)` status value.
///
/// Equivalent to the C macro `WTERMSIG(x)`.
///
/// - Parameter s: The raw wait status value.
/// - Returns: The signal number that terminated the process.
public func WTERMSIG(_ s: Int32) -> Int32 { return s & 0x7f }

/// Generates a new random UUID and returns it as a lowercase hyphenated string.
///
/// - Returns: A UUID string in the form `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.
public func uuidString() -> String {
  var u = withUnsafeTemporaryAllocation(of: uuid_t.self, capacity: 1) { p in
    uuid_generate_random(p.baseAddress!)
    return p[0]
  }

  var buf = [CChar](repeating: 0, count: 37)
  uuid_unparse_lower(&u, &buf)

  return String(platformString: buf)
}
