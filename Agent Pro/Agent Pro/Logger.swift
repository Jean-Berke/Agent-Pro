// Core/Logger.swift
import os.log

enum Logger {
    private static let subsystem = "com.yourcompany.AgentPro"

    static func info(_ message: String, category: String = "app") {
        os_log(.info, log: OSLog(subsystem: subsystem, category: category), "%{public}@", message)
    }

    static func error(_ message: String, category: String = "app") {
        os_log(.error, log: OSLog(subsystem: subsystem, category: category), "%{public}@", message)
    }

    static func debug(_ message: String, category: String = "app") {
        os_log(.debug, log: OSLog(subsystem: subsystem, category: category), "%{public}@", message)
    }
}
