//
//  zenmux_monitorApp.swift
//  zenmux-monitor
//
//  Zenmux 菜单栏监控小程序入口
//

import SwiftUI

@main
struct zenmux_monitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

