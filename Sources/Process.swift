// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import SystemPackage
import Darwin

public func getenv(_ name: String) -> String? {
  if let a = Darwin.getenv(name) {
    return String(cString: a)
  } else {
    return nil
  }
}

public func getenv() -> [String:String] {
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

public func setenv(_ name : String, _ value: String) throws(POSIXErrno) {
  let k = Darwin.setenv(name, value, 1)
  if k == -1 {
    throw POSIXErrno()
  }
}

public func unsetenv(_ name : String) throws(POSIXErrno) {
  let k = Darwin.unsetenv(name)
  if k == -1 {
    throw POSIXErrno()
  }
}



public struct ProcessResult {
    public let stdout: String
    public let stderr: String
}

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

/**
 Implemented for find.
 This could possibly be replaced by using posix_spawn
 */
public func execvp(_ x : String, _ a : [String]) -> POSIXErrno {
  let az = a.map { $0.withCString { strdup($0) } } + [UnsafeMutablePointer<CChar>.init(bitPattern: 0)]
  Darwin.execvp(x, az )
  return POSIXErrno()
}
