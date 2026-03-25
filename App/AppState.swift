import SwiftUI

enum AppPage {
    case landing
    case canvas
}

@Observable
class AppState {
    var currentPage: AppPage = .landing
}
