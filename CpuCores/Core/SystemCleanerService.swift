import Combine
import Foundation
import UIKit

enum CleanerAction: Equatable {
    case ram
    case disk
}

final class SystemCleanerService: ObservableObject {
    @Published private(set) var activeAction: CleanerAction?
    @Published private(set) var ramMessage: String?
    @Published private(set) var diskMessage: String?

    private let workerQueue = DispatchQueue(
        label: "com.cpucores.system-cleaner",
        qos: .utility
    )
    private let cancellation: UnsafeMutablePointer<CCCleanerCancellation>
    private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        cancellation = .allocate(capacity: 1)
        cancellation.initialize(to: CCCleanerCancellation())
        CCCleanerCancellationReset(cancellation)

        let notificationCenter = NotificationCenter.default
        lifecycleObservers.append(notificationCenter.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cancel()
        })
        lifecycleObservers.append(notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cancel()
        })

        let temporaryDirectory = NSTemporaryDirectory()
        workerQueue.async {
            temporaryDirectory.withCString { directory in
                CCCleanerRemoveStaleAPFSFiles(directory)
            }
        }
    }

    deinit {
        CCCleanerCancellationRequest(cancellation)
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        cancellation.deinitialize(count: 1)
        cancellation.deallocate()
    }

    func cleanRAM() {
        guard activeAction == nil else { return }

        CCCleanerCancellationReset(cancellation)
        ramMessage = nil
        activeAction = .ram

        workerQueue.async { [weak self] in
            guard let self else { return }
            let result = CCCleanRAM(self.cancellation)
            let message = Self.ramMessage(for: result)
            DispatchQueue.main.async { [weak self] in
                self?.ramMessage = message
                self?.activeAction = nil
            }
        }
    }

    func cleanDisk() {
        guard activeAction == nil else { return }

        CCCleanerCancellationReset(cancellation)
        diskMessage = nil
        activeAction = .disk
        let temporaryDirectory = NSTemporaryDirectory()

        workerQueue.async { [weak self] in
            guard let self else { return }
            let result = temporaryDirectory.withCString { directory in
                CCCleanAPFS(directory, self.cancellation)
            }
            let message = Self.diskMessage(for: result)
            DispatchQueue.main.async { [weak self] in
                self?.diskMessage = message
                self?.activeAction = nil
            }
        }
    }

    func cancel() {
        guard activeAction != nil else { return }
        CCCleanerCancellationRequest(cancellation)
    }

    private static func ramMessage(for result: CCRAMCleanerResult) -> String {
        switch result.status {
        case UInt32(CC_CLEANER_STATUS_SUCCESS):
            return CCFormatted("clean.ram.result.success", format(result.committedBytes))
        case UInt32(CC_CLEANER_STATUS_CANCELLED):
            return CCLocalized("clean.ram.result.cancelled")
        case UInt32(CC_CLEANER_STATUS_NO_WORK):
            return CCLocalized("clean.ram.result.no_work")
        case UInt32(CC_CLEANER_STATUS_ALLOCATION_FAILED):
            return CCLocalized("clean.ram.result.limit")
        default:
            return CCLocalized("clean.ram.result.unavailable")
        }
    }

    private static func diskMessage(for result: CCDiskCleanerResult) -> String {
        switch result.status {
        case UInt32(CC_CLEANER_STATUS_SUCCESS):
            var message = CCFormatted(
                "clean.disk.result.success",
                format(result.temporaryBytesWritten)
            )
            if result.estimatedReclaimedBytes > 0 {
                message += " " + CCFormatted(
                    "clean.disk.result.reclaimed",
                    format(result.estimatedReclaimedBytes)
                )
            }
            return message
        case UInt32(CC_CLEANER_STATUS_CANCELLED):
            return CCLocalized("clean.disk.result.cancelled")
        case UInt32(CC_CLEANER_STATUS_NO_WORK):
            return CCLocalized("clean.disk.result.no_work")
        case UInt32(CC_CLEANER_STATUS_ALLOCATION_FAILED):
            return CCLocalized("clean.disk.result.memory")
        case UInt32(CC_CLEANER_STATUS_IO_ERROR):
            return CCLocalized("clean.disk.result.io_error")
        default:
            return CCLocalized("clean.disk.result.unavailable")
        }
    }

    private static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .file
        )
    }
}
