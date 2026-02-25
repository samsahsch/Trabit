//
//  Trabit_WidgetLiveActivity.swift
//  Trabit Widget
//
//  Created by Sahel-Schackis, Samuel on 2/25/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Trabit_WidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Trabit_WidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Trabit_WidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Trabit_WidgetAttributes {
    fileprivate static var preview: Trabit_WidgetAttributes {
        Trabit_WidgetAttributes(name: "World")
    }
}

extension Trabit_WidgetAttributes.ContentState {
    fileprivate static var smiley: Trabit_WidgetAttributes.ContentState {
        Trabit_WidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Trabit_WidgetAttributes.ContentState {
         Trabit_WidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Trabit_WidgetAttributes.preview) {
   Trabit_WidgetLiveActivity()
} contentStates: {
    Trabit_WidgetAttributes.ContentState.smiley
    Trabit_WidgetAttributes.ContentState.starEyes
}
