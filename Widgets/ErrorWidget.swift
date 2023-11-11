//
//  ErrorWidget.swift
//  AC Widget by NO-COMMENT
//

import SwiftUI
import WidgetKit

struct ErrorWidget: View {
    let error: APIError

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.red)

            Text("Error")
                .font(.system(size: 22, weight: .medium, design: .rounded))

            Text(error.errorDescription ?? "")
                .multilineTextAlignment(.center)
                .font(.system(size: 14))
        }
        .minimumScaleFactor(0.5)
        .padding()
    }
}

#Preview {
    ErrorWidget(error: .wrongPermissions)
}
#Preview {
    ErrorWidget(error: .exceededLimit)
}
#Preview {
    ErrorWidget(error: .exceededLimit)
}
