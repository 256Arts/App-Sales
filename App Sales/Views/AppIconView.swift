import SwiftUI

/// An app's icon: the fetched artwork when it is available, the App Group's cached copy while that
/// downloads, and a plain fill when neither is there yet.
struct AppIconView: View {

    let app: AppPerformanceSummary
    let length: CGFloat

    var body: some View {
        AsyncImage(url: app.iconURL) { image in
            image
                .resizable()
        } placeholder: {
            if let icon = app.cachedIcon {
                icon
                    .resizable()
            } else {
                Color.secondary
            }
        }
        .frame(width: length, height: length)
        .clipShape(RoundedRectangle(cornerRadius: length / 4))
    }
}
