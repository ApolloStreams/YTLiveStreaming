//
//  Error.swift
//  LiveEvents
//

import Foundation

public enum YTError: Error {
    case message(String)
    case systemMessage(Int, String)
    case apiError(Int, String)

    public func message() -> String {
        switch self {
        case .message(let message):
            return message
        case .systemMessage(let code, let message):
            return "System error: \(code)\n\(message)"
        case .apiError(let code, let message):
          return "Api error: \(code)\n\(message)"
        }
    }
}
