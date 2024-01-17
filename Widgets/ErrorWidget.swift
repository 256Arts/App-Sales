//
//  ErrorWidget.swift
//  AC Widget by NO-COMMENT
//

#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

struct ErrorWidget: View {
    let error: APIError

    var body: some View {
        VStack(alignment: .leading) {
            Text("App Sales")
                .font(.headline)
            
            Text("Error")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .leading)
        .containerBackground(backgroundColor, for: .widget)
    }
    
    private var backgroundColor: Color {
        #if canImport(UIKit)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
}

#Preview {
    ErrorWidget(error: .invalidCredentials)
}
#Preview {
    ErrorWidget(error: .wrongPermissions)
}
#Preview {
    ErrorWidget(error: .exceededLimit)
}
#Preview {
    ErrorWidget(error: .noDataAvailable)
}
#Preview {
    ErrorWidget(error: .unknown)
}
#endif
