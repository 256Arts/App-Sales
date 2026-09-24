import SwiftUI

/// An app's icon: the fetched artwork when it is available, the App Group's cached copy while that
/// downloads, and a plain fill when neither is there yet. An app with no artwork at all (removed from
/// sale, or unreleased) gets `AppIconPlaceholder`.
struct AppIconView: View {

    let app: AppPerformanceSummary
    let length: CGFloat

    var body: some View {
        AsyncImage(url: app.iconURL) { image in
            image
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
        } placeholder: {
            if let icon = app.cachedIcon {
                icon
                    .resizable()
                    .widgetAccentedRenderingMode(.accentedDesaturated)
            } else if app.iconURL == nil {
                AppIconPlaceholder()
            } else {
                Color.secondary
            }
        }
        .frame(width: length, height: length)
        .clipShape(RoundedRectangle(cornerRadius: length / 4))
    }
}

/// A blank app icon, for an app with no artwork to show. Fills whatever frame it is given.
struct AppIconPlaceholder: View {

    var body: some View {
        GeometryReader { proxy in
            Image(systemName: "app.dashed")
                .font(.system(size: proxy.size.width * 0.6))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.fill.secondary)
    }
}
