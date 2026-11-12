import SwiftUI

public enum LoadMoreState: Equatable {
    case idle, loading, noMore, failed(String)
}

public struct LoadMoreFooter: View {
    public var state: LoadMoreState
    public var noMoreText: String
    public var networkErrorText: String
    public var retryText: String
    public var accentColor: Color
    public var secondaryColor: Color
    public var font: Font
    public var spacing: CGFloat
    public var height: CGFloat
    public var onRetry: (() -> Void)?

    public init(state: LoadMoreState, noMoreText: String = "No more data", networkErrorText: String = "Network error", retryText: String = "Retry", accentColor: Color = .accentColor, secondaryColor: Color = .secondary, font: Font = .caption, spacing: CGFloat = 8, height: CGFloat = 48, onRetry: (() -> Void)? = nil) {
        self.state = state; self.noMoreText = noMoreText; self.networkErrorText = networkErrorText
        self.retryText = retryText; self.accentColor = accentColor; self.secondaryColor = secondaryColor
        self.font = font; self.spacing = spacing; self.height = height; self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: spacing) {
            switch state {
            case .idle: Color.clear.frame(height: 1)
            case .loading: ProgressView().progressViewStyle(.circular).tint(accentColor).scaleEffect(0.8)
            case .noMore: Text(noMoreText).font(font).foregroundStyle(secondaryColor)
            case .failed(let message):
                Text(message.isEmpty ? networkErrorText : message).font(font).foregroundStyle(secondaryColor)
                Button(retryText) { onRetry?() }.font(font).foregroundStyle(accentColor)
            }
        }.frame(maxWidth: .infinity).frame(height: height)
    }
}

public extension View {
    func loadMoreTrigger(_ action: @escaping () async -> Void) -> some View { task { await action() } }
}
