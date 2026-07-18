import Foundation

final class InputMethodRuntime {
    static let shared = InputMethodRuntime()

    let busyAppsSnapshot: BusyAppsSnapshot
    let hostBackendFactory: HostBackendFactory
    lazy var inputMethodServer = InputMethodServer()

    init(busyAppsSnapshot: BusyAppsSnapshot = .load()) {
        self.busyAppsSnapshot = busyAppsSnapshot
        hostBackendFactory = HostBackendFactory(busyAppsSnapshot: busyAppsSnapshot)
    }
}
