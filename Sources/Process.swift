// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import SystemPackage
import Darwin

public struct Environment {
  /// Return the value of the environment variable given as argument.  Return `nil` if the environment variable is not set
/*  public static func getenv(_ name: String) -> String? {
    if let a = Darwin.getenv(name) {
      return String(cString: a)
    } else {
      return nil
    }
  }
*/
  
  public static subscript(_ name : String) -> String? {
    get {if let a = Darwin.getenv(name) {
      return String(cString: a)
    } else {
      return nil
    }
    }
  }

  /// Return  a dictionary mapping environment variable names to values
  public static func getenv() -> [String:String] {
    var env = [String: String]()

    var ptr = environ
    while let current = ptr.pointee {
      if let entry = String(validatingCString: current) {
        if let equalIndex = entry.firstIndex(of: "=") {
          let key = String(entry[..<equalIndex])
          let value = String(entry[entry.index(after: equalIndex)...])
          env[key] = value
        }
      }
      ptr = ptr.advanced(by: 1)
    }
    return env
  }

  /// Set the environment variable specified by @arg name to the value specified by @arg value.`
  /// A subscript `set` specifier cannot throw -- so I need a separate function
  public static func setenv(_ name : String, _ value: String) throws(POSIXErrno) {
    let k = Darwin.setenv(name, value, 1)
    if k == -1 {
      throw POSIXErrno()
    }
  }

  /// Unset the environment variable @arg name
  public static func unsetenv(_ name : String) throws(POSIXErrno) {
    let k = Darwin.unsetenv(name)
    if k == -1 {
      throw POSIXErrno()
    }
  }

  /// Return the name of the currently executing command
  public static var progname : String {
    let k = String(cString: getprogname())
    return k
  }
}

/// Running a sub process (using `ProcessRunner` will return the contents of standard output and standard error wrapped in this struct
public struct ProcessResult : Sendable {
    public let stdout: String
    public let stderr: String
}

/// Running a subprocess (using `ProcessRunner` will throw a ProcessError if
/// a) the subprocess fails to run (`spawnFailed`) or
/// b) the subprocess runs and terminates with a non-zero exit status (`nonZeroExit`)
public enum ProcessError: Error, CustomStringConvertible {
    case nonZeroExit(code: Int32, stdout: String, stderr: String)
    case spawnFailed(errno: Int32)

    public var description: String {
        switch self {
        case .nonZeroExit(let code, let out, let err):
            return "Process failed with exit code \(code).\nstdout:\n\(out)\nstderr:\n\(err)"
        case .spawnFailed(let errno):
            return "posix_spawn failed with errno \(errno): \(String(cString: strerror(errno)))"
        }
    }
}

/*
public struct ProcessRunner {
  public static func run(command: String, arguments: [String],
                         currentDirectory : String? = nil,
                         environment: [String: String]? = nil,
                         prelaunch: (@Sendable (pid_t) async -> ())? = nil,
                         captureStdout: Bool = true,
                         captureStderr: Bool = true) throws -> ProcessResult {

    var stdoutPipe : (readEnd: FileDescriptor, writeEnd: FileDescriptor)? = nil

    if captureStdout {
      stdoutPipe = try FileDescriptor.pipe()
    }

    var stderrPipe : (readEnd: FileDescriptor, writeEnd: FileDescriptor)? = nil

    if captureStderr {
      stderrPipe = try FileDescriptor.pipe()
    }

        defer {
            try? stdoutPipe?.readEnd.close()
            try? stdoutPipe?.writeEnd.close()
            try? stderrPipe?.readEnd.close()
            try? stderrPipe?.writeEnd.close()
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)

      if let cwd = currentDirectory {
        // FIXME: not available on iOS
          posix_spawn_file_actions_addchdir_np(&fileActions, cwd)
      }
      
        // Redirect stdout and stderr
    if captureStdout {
      posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe!.writeEnd.rawValue, STDOUT_FILENO)
      posix_spawn_file_actions_addclose(&fileActions, stdoutPipe!.readEnd.rawValue)
    }

    if captureStderr {
      posix_spawn_file_actions_adddup2(&fileActions, stderrPipe!.writeEnd.rawValue, STDERR_FILENO)
      posix_spawn_file_actions_addclose(&fileActions, stderrPipe!.readEnd.rawValue)
    }

        let argv: [UnsafeMutablePointer<CChar>?] = ([command] + arguments).map { strdup($0) } + [nil]

        var pid: pid_t = 0
    
    var ev = environ
    if let environment {
      ev = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: environment.count + 1)
      defer { ev.deallocate() }
      var i = 0
      for (k, v) in environment {
        ev[i] = strdup("\(k)=\(v)")
        i += 1
      }
      ev[i] = nil
    }
        let spawnResult = posix_spawn(&pid, command, &fileActions, nil, argv, ev)

        for ptr in argv where ptr != nil {
            free(ptr)
        }
    
        posix_spawn_file_actions_destroy(&fileActions)

        guard spawnResult == 0 else {
            throw ProcessError.spawnFailed(errno: spawnResult)
        }
    
    if let prelaunch { let p = pid; Task { await prelaunch(p) } }

    

        // Close child ends in parent
    var stdo : String = ""
    var stde : String = ""

    if captureStdout {
      // Capture stdout
      try stdoutPipe!.writeEnd.close()
      stdo = try readAll(from: stdoutPipe!.readEnd)
    }
    if captureStderr {
      try stderrPipe!.writeEnd.close()
      stde = try readAll(from: stderrPipe!.readEnd)
    }




        // Wait for child
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1

        if exitCode != 0 {
            throw ProcessError.nonZeroExit(code: exitCode, stdout: stdo, stderr: stde)
        }

        return ProcessResult(stdout: stdo, stderr: stde)
    }

    private static func readAll(from fd: FileDescriptor) throws -> String {
        var output = ""
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = try buffer.withUnsafeMutableBytes {
                try fd.read(into: $0)
            }
            if bytesRead == 0 { break }
                output += String(decoding: buffer[..<bytesRead], as: UTF8.self)
        }

        return output
    }
}

 */

/**
 example usage:
 
 do {
     let result = try ProcessRunner.run(command: "/bin/ls", arguments: ["-l", "/no/such/dir"], forwardStdoutToParent: true)
     // When forwarding is enabled, the corresponding field in ProcessResult will be an empty string.
     print(result.stdout)
 } catch {
     print("Error: \(error)")
 }
 */

/// THis protocol identifies the classes which can be passed as standard input to `ProcessRunner`
public protocol Stdinable : Sendable {}
extension String : Stdinable {}
extension FileDescriptor : Stdinable {}
extension AsyncStream<UInt8> : Stdinable {}
extension [UInt8] : Stdinable {}

/// This struct is used to spawn a subprocess and run it.
public struct ProcessRunner {
  var command : String
  var arguments: [String]
  var environment : [String : String]?
  var currentDirectory : String?

  public init(command: String, arguments: [String], currentDirectory: String? = nil, environment: [String: String]? = nil) {
    self.command = command
    self.arguments = arguments
    self.environment = environment
    self.currentDirectory = currentDirectory
  }

  public func run(
    input: (any Stdinable)? = nil,
    prelaunch: (@Sendable (pid_t) async -> ())? = nil,
    captureStdout: Bool = true,
    captureStderr: Bool = true) async throws -> ProcessResult {

      var stdinPipe : (readEnd: FileDescriptor, writeEnd: FileDescriptor)? = nil
      if input == nil {
        stdinPipe = try FileDescriptor.pipe()
      }

      var stdoutPipe : (readEnd: FileDescriptor, writeEnd: FileDescriptor)? = nil

      if captureStdout {
        stdoutPipe = try FileDescriptor.pipe()
      }

      var stderrPipe : (readEnd: FileDescriptor, writeEnd: FileDescriptor)? = nil

      if captureStderr {
        stderrPipe = try FileDescriptor.pipe()
      }

      defer {
        try? stdoutPipe?.readEnd.close()
        try? stdoutPipe?.writeEnd.close()
        try? stderrPipe?.readEnd.close()
        try? stderrPipe?.writeEnd.close()
      }

      var fileActions: posix_spawn_file_actions_t?
      posix_spawn_file_actions_init(&fileActions)

      if let cwd = currentDirectory {
        // FIXME: not available on iOS
        posix_spawn_file_actions_addchdir_np(&fileActions, cwd)
      }


      posix_spawn_file_actions_adddup2(&fileActions, stdinPipe!.writeEnd.rawValue, STDIN_FILENO)

      // Redirect stdout and stderr
      if captureStdout {
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe!.writeEnd.rawValue, STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe!.readEnd.rawValue)
      }

      if captureStderr {
        posix_spawn_file_actions_adddup2(&fileActions, stderrPipe!.writeEnd.rawValue, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe!.readEnd.rawValue)
      }

      let argv: [UnsafeMutablePointer<CChar>?] = ([command]+arguments).map { strdup($0) } + [nil]

      var pid: pid_t = 0

      var ev = environ
      if let environment {
        ev = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: environment.count + 1)
        defer {
 /*         var i = 0
          while let j = ev[i] {
            free(j)
          }
  */
          ev.deallocate()
       }
        var i = 0
        for (k, v) in environment {
          ev[i] = strdup("\(k)=\(v)")
          i += 1
        }
        ev[i] = nil
      }

      let cc = searchPath(for: command)

      let spawnResult = posix_spawn(&pid, cc, &fileActions, nil, argv, ev)

      for ptr in argv where ptr != nil {
        free(ptr)
      }

      posix_spawn_file_actions_destroy(&fileActions)

      guard spawnResult == 0 else {
        throw ProcessError.spawnFailed(errno: spawnResult)
      }

      if let prelaunch { let p = pid; Task { await prelaunch(p) } }



      // Close child ends in parent
      var stdo : String = ""
      var stde : String = ""

      if let ii = input {
        let w = stdinPipe!.writeEnd
        Task.detached {
          switch ii {
            case is [UInt8]:
              try w.writeAll(ii as! [UInt8])
            case is String:
              var j = ii as! String
              let n = try j.withUTF8 { bp in
                try w.writeAll(UnsafeRawBufferPointer(bp) )
              }
            case is AsyncStream<UInt8>:
              var j = ii as! AsyncStream<UInt8>
              for try await i in j {
                try w.write([i])
              }
            case is FileDescriptor:
              var j = ii as! FileDescriptor
              for try await i in j.bytes {
                try w.write([i])
              }
            default:
              fatalError("Unsupported input type \(type(of: ii))")
          }
        }
      }
      if captureStdout {
        // Capture stdout
        try stdoutPipe!.writeEnd.close()
        stdo = try readAll(from: stdoutPipe!.readEnd)
      }
      if captureStderr {
        try stderrPipe!.writeEnd.close()
        stde = try readAll(from: stderrPipe!.readEnd)
      }

      // Wait for child
      let status = try await waitpidAsync(pid)
      let exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : -1

      if exitCode != 0 {
        throw ProcessError.nonZeroExit(code: exitCode, stdout: stdo, stderr: stde)
      }

      return ProcessResult(stdout: stdo, stderr: stde)
    }

  private func readAll(from fd: FileDescriptor) throws -> String {
    var output = ""
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
      let bytesRead = try buffer.withUnsafeMutableBytes {
        try fd.read(into: $0)
      }
      if bytesRead == 0 { break }
      output += String(decoding: buffer[..<bytesRead], as: UTF8.self)
    }

    return output
  }




  /// Asynchronously wait for a process with the given PID to exit.
  /// - Parameters:
  ///   - pid: The process ID to wait for.
  ///   - options: POSIX wait options (e.g., WNOHANG, WUNTRACED).
  /// - Returns: The exit status of the child process.
  private func waitpidAsync(_ pid: pid_t, options: CInt = 0) async throws -> CInt {
    return try await withCheckedThrowingContinuation { continuation in
      var status: CInt = 0
      let result = waitpid(pid, &status, options)

      if result == -1 {
        continuation.resume(throwing: POSIXErrno())
      } else {
        continuation.resume(returning: status)
      }
    }
  }
}

/**
 example usage:

 do {
     let result = try ProcessRunner2(command: "/bin/ls", arguments: ["-l", "/no/such/dir"]).run(input: "input")
 // When forwarding is enabled, the corresponding field in ProcessResult will be an empty string.
     print(result.stdout)
 } catch {
     print("Error: \(error)")
 }
*/


/**
 Implemented for find.
  */
public func execvp(_ x : String, _ a : [String]) -> POSIXErrno {
  let az = a.map { $0.withCString { strdup($0) } } + [UnsafeMutablePointer<CChar>.init(bitPattern: 0)]
  Darwin.execvp(x, az )
  return POSIXErrno()
}
