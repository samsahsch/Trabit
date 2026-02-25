import WidgetKit
import SwiftUI

@main
struct Trabit_WidgetBundle: WidgetBundle {
    var body: some Widget {
        TrabitSmallWidget()
        TrabitMediumWidget()
        TrabitLockScreenWidget()
        TrabitRectangularWidget()
        TrabitWidgetControl()
    }
}
