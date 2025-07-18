// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2025

import Darwin

public enum YesNo {
  case yes
  case no
  case neither
}
/**
    given the user's response to a yes/no prompt,
    return YesNo.yes if the response is "yes"
    or YesNo.no if the response is "no"
     or YesNo.neither for anything else
 */
public func rpmatch(_ resp : String) -> YesNo {
  let rpy = String(validatingCString: nl_langinfo(YESEXPR)) ?? "^[yY]"
  let py = try? Regex(rpy)

  let rpn = String(validatingCString: nl_langinfo(NOEXPR)) ?? "^[nN]"
  let pn = try? Regex(rpn)

  if let _ = try? py?.firstMatch(in: resp) {
    return .yes
  }
  if let _ = try? pn?.firstMatch(in: resp) {
    return .no
  }
  return .neither
}
