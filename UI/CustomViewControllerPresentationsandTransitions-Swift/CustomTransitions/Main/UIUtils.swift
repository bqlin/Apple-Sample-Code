//
//  UIUtils.swift
//  
//  Created by Bq on 2025/10/24.
//

import Foundation
import UIKit

extension UIView {
    func prepareForAutoLayout() {
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    func centerTo(_ view: UIView) {
        prepareForAutoLayout()
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
    
    func centerBottomTo(_ view: UIView) {
        prepareForAutoLayout()
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }
    
    func setupContentLabel(text: String) {
        let view = self
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 120)
        label.textColor = UIColor(white: 0, alpha: 0.25)
        view.addSubview(label)
        label.centerTo(view)
    }
    
    @discardableResult
    func setupBaseUI(text: String, buttonTitle: String) -> UIButton {
        let view = self
        setupContentLabel(text: text)
        
        let button = UIButton(type: .system)
        button.setTitle(buttonTitle, for: .normal)
        view.addSubview(button)
        button.centerBottomTo(view)
        return button
    }
}

extension UIViewController {
    
}

extension UIColor {
    /// 通过十六进制字符串创建颜色
    /// - Parameter hex: 十六进制颜色字符串，支持格式：
    ///   - "#RGB" (12位)
    ///   - "#RGBA" (16位)
    ///   - "#RRGGBB" (24位)
    ///   - "#RRGGBBAA" (32位)
    ///   - "RRGGBB" (不带#)
    convenience init(_ hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            self.init()
            return
        }
        
        let length = hexSanitized.count
        let r, g, b, a: CGFloat
        
        switch length {
        case 3: // RGB (12-bit)
            r = CGFloat((rgb & 0xF00) >> 8) / 15.0
            g = CGFloat((rgb & 0x0F0) >> 4) / 15.0
            b = CGFloat(rgb & 0x00F) / 15.0
            a = 1.0
            
        case 4: // RGBA (16-bit)
            r = CGFloat((rgb & 0xF000) >> 12) / 15.0
            g = CGFloat((rgb & 0x0F00) >> 8) / 15.0
            b = CGFloat((rgb & 0x00F0) >> 4) / 15.0
            a = CGFloat(rgb & 0x000F) / 15.0
            
        case 6: // RRGGBB (24-bit)
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
            
        case 8: // RRGGBBAA (32-bit)
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
            
        default:
            fatalError("颜色格式不支持：\(hex)")
        }
        
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

class TrackingView: UIView {
    deinit {
        print("🚧 \(self)\(#function), next: \(String(describing: next)).")
    }
}
