//
//  DownloadsIconsGraphic.swift
//  WidgetsExtension
//
//  Created by 256 Arts Developer on 2023-10-28.
//

import SwiftUI

struct DownloadsIconsGraphic: View {
    
    let apps: [AppPerformanceSummary]
    let daysRange = 30
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom) {
                ForEach(apps) { app in
                    Group {
                        if let path = app.cachedIconURL?.path(), let data = FileManager.default.contents(atPath: path), let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                        } else {
                            Color.secondary
                        }
                    }
                    .frame(width: geometry.size.height * fractionOfBestApp(app), height: geometry.size.height * fractionOfBestApp(app))
                    .clipShape(RoundedRectangle(cornerRadius: geometry.size.height * fractionOfBestApp(app) / 4))
                    .background {
                        RoundedRectangle(cornerRadius: geometry.size.height * fractionOfBestApp(app) / 4)
                            .fill(Color(UIColor.systemFill))
                            .padding(-0.5)
                    }
                }
            }
        }
    }
    
    private func fractionOfBestApp(_ app: AppPerformanceSummary) -> CGFloat {
        guard let bestApp = apps.max(by: { $0.downloads < $1.downloads }) else { return 1.0 }
        
        // Use logarithmic scale since icons have area of length^2
        return max(0.2, sqrt(CGFloat(app.downloads)) / sqrt(CGFloat(bestApp.downloads)))
    }
}

//#Preview {
//    DownloadsIconsGraphic()
//}
