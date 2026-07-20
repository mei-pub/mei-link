import Foundation

class FrpcProcess {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private let logger = Logger(subsystem: "com.meilink", category: "FrpcProcess")

    var isRunning: Bool { process?.isRunning ?? false }
    var processID: Int32? { process?.processIdentifier }

    func start(configPath: String) throws {
        guard let frpcPath = Bundle.main.path(forResource: "frpc", ofType: nil) else {
            throw FrpcProcessError.binaryNotFound
        }

        process = Process()
        process?.executableURL = URL(fileURLWithPath: frpcPath)
        process?.arguments = ["-c", configPath]

        outputPipe = Pipe()
        errorPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = errorPipe

        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                self?.logger.info("frpc: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        errorPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                self?.logger.error("frpc stderr: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        process?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.logger.info("frpc 进程已退出，状态码: \(process.terminationStatus)")
            }
        }

        try process?.run()
        logger.info("frpc 进程已启动，PID: \(process?.processIdentifier ?? 0)")
    }

    func stop() {
        guard let process = process, process.isRunning else { return }

        process.terminate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.process?.isRunning == true {
                self?.process?.interrupt()
            }
        }
    }
}

enum FrpcProcessError: Error, LocalizedError {
    case binaryNotFound

    var errorDescription: String? {
        switch self {
        case .binaryNotFound: return "未找到 frpc 二进制文件"
        }
    }
}
