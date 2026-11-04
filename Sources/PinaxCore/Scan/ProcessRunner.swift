import Foundation

/// Chạy tiến trình con, đọc stdout, có timeout. Nội bộ cho mdfind / hdiutil.
enum ProcessRunner {
    private final class Box: @unchecked Sendable { var data = Data() }

    /// nil khi không chạy được, hết giờ, bị huỷ hoặc exit ≠ 0.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        // Đọc stdout song song để pipe không đầy làm treo tiến trình con.
        let box = Box()
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global().async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            reading.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        var finished = false
        while Date() < deadline {
            if exited.wait(timeout: .now() + 0.1) == .success { finished = true; break }
            if Task.isCancelled { break }
        }
        if !finished {
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
            reading.wait()
            return nil
        }
        reading.wait()
        return process.terminationStatus == 0 ? box.data : nil
    }
}
