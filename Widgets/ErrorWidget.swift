#if canImport(WidgetKit)
import SwiftUI
import WidgetKit

struct ErrorWidget: View {
    let error: APIError

    var body: some View {
        VStack(alignment: .leading) {
            Text("App Sales")
                .font(.headline)
                .widgetAccentable()
            
            Text("Error")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
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
