//
//  AppDelegate.swift
//  CustomHLS
//
//  Created by Maxim Bezdenezhnykh on 04/10/2024.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        let window = UIWindow(frame: .init(origin: .zero, size: UIScreen.main.bounds.size))
        let controller = ViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        
        return true
    }
}
