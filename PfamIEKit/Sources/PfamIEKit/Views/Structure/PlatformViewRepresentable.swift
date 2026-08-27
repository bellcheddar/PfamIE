import SwiftUI

/// One representable protocol for both UIKit and AppKit.
///
/// PfamIEKit is meant to be free of platform UI frameworks, and it nearly is:
/// this file and MolViewer are the only exceptions, because there is no
/// SwiftUI-native web view and the structure layer needs one. Keeping the seam
/// here means nothing else in the package has to know which platform it is on.
#if canImport(UIKit) && !os(watchOS)
import UIKit

public protocol PlatformViewRepresentable: UIViewRepresentable {
    associatedtype PlatformView: UIView
    func makePlatformView(context: Context) -> PlatformView
    func updatePlatformView(_ view: PlatformView, context: Context)
}

public extension PlatformViewRepresentable {
    func makeUIView(context: Context) -> PlatformView { makePlatformView(context: context) }
    func updateUIView(_ view: PlatformView, context: Context) {
        updatePlatformView(view, context: context)
    }
}

#elseif canImport(AppKit)
import AppKit

public protocol PlatformViewRepresentable: NSViewRepresentable {
    associatedtype PlatformView: NSView
    func makePlatformView(context: Context) -> PlatformView
    func updatePlatformView(_ view: PlatformView, context: Context)
}

public extension PlatformViewRepresentable {
    func makeNSView(context: Context) -> PlatformView { makePlatformView(context: context) }
    func updateNSView(_ view: PlatformView, context: Context) {
        updatePlatformView(view, context: context)
    }
}
#endif
