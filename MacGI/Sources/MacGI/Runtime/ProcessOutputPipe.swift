import Foundation

func readAvailableProcessOutput(from handle: FileHandle) -> Data? {
    let data = handle.availableData
    guard !data.isEmpty else {
        handle.readabilityHandler = nil
        return nil
    }
    return data
}
