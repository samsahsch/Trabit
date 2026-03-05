import WidgetKit
import SwiftUI

@main
struct Trabit_WidgetBundle: WidgetBundle {
    var body: some Widget {
        TrabitSmallWidget()
        TrabitMediumWidget()
        TrabitLargeWidget()
        TrabitLockScreenInlineWidget()
        TrabitLockScreenRectangularWidget()
        TrabitLockScreenCircularWidget()
        Trabit_WidgetControl()
    }
}
