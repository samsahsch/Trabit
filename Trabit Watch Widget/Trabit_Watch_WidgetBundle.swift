import WidgetKit
import SwiftUI

@main
struct Trabit_Watch_WidgetBundle: WidgetBundle {
    var body: some Widget {
        TrabitCircularComplication()
        TrabitRectangularComplication()
        TrabitCornerComplication()
        TrabitInlineComplication()
        Trabit_Watch_WidgetControl()
    }
}
