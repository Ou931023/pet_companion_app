import Flutter
import UIKit

final class NativeHomeBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    NativeHomeBarView(
      frame: frame,
      viewIdentifier: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

final class NativeHomeBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let tabBar = UITabBar()
  private let channel: FlutterMethodChannel
  private let items: [UITabBarItem]

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    channel = FlutterMethodChannel(
      name: "pet_companion/native_home_bar",
      binaryMessenger: messenger
    )
    let params = args as? [String: Any]
    let showMarketplace = params?["showMarketplace"] as? Bool ?? false
    var visibleItems = [
      UITabBarItem(title: "首頁", image: UIImage(systemName: "pawprint"), tag: 0),
    ]
    if showMarketplace {
      visibleItems.append(
        UITabBarItem(title: "商城", image: UIImage(systemName: "storefront"), tag: visibleItems.count)
      )
    }
    visibleItems.append(
      UITabBarItem(title: "紀錄", image: UIImage(systemName: "clock.arrow.circlepath"), tag: visibleItems.count)
    )
    visibleItems.append(
      UITabBarItem(title: "設定", image: UIImage(systemName: "gearshape"), tag: visibleItems.count)
    )
    items = visibleItems
    super.init()

    let selectedIndex = params?["selectedIndex"] as? Int ?? 0
    tabBar.items = items
    tabBar.selectedItem = items.indices.contains(selectedIndex) ? items[selectedIndex] : items[0]
    tabBar.delegate = self
    tabBar.isTranslucent = true
    tabBar.tintColor = .systemIndigo
    tabBar.unselectedItemTintColor = .secondaryLabel
  }

  func view() -> UIView {
    tabBar
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("tabSelected", arguments: item.tag)
  }
}
