import Flutter
import Testing
import UIKit


@testable import live_updates

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/xcode/swift-testing/ for more information about using
// Swift Testing.

struct RunnerTests {

  @Test func getPlatformVersionSucceeds() throws {
    let plugin = LiveUpdatesPlugin()

    let result = try plugin.getPlatformVersion()
    #expect(result == "iOS " + UIDevice.current.systemVersion)
  }

}
