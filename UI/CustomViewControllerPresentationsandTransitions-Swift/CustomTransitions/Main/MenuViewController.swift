//
//  MenuViewController.swift
//  
//  Created by Bq on 2025/10/24.
//

import Foundation
import UIKit

class MenuViewController: UITableViewController {
    struct GroupInfo {
        var title: String
        var items: [ItemInfo]
    }
    
    struct ItemInfo {
        var title: String
        var detail: String
        var action: () -> Void
    }
    
    var data: [GroupInfo] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
        
        title = "Custom Transitions"
        data = [
            GroupInfo(title: "Presentation Transitions", items: [
                ItemInfo(title: "Cross Dissolve", detail: "A cross dissolve transition.") { [weak self] in
                    guard let self else { return }
                    route(to: CrossDissolveFirstViewController())
                },
                ItemInfo(title: "Swipe", detail: "An interactive transition.") { [weak self] in
                    guard let self else { return }
                    route(to: SwipeFirstViewController())
                },
                ItemInfo(title: "Custom Presentation", detail: "Using a presentation controller to alter the layout of a presented view controller.") { [weak self] in
                    guard let self else { return }
                    route(to: CustomPresentationFirstViewController())
                },
                ItemInfo(title: "Adaptive Presentation", detail: "Building a custom presentation that adapts to horizontally compact environments.") { [weak self] in
                    guard let self else { return }
                    route(to: AdaptivePresentationFirstViewController())
                },
            ]),
            GroupInfo(title: "Navigation Controller Transitions", items: [
                ItemInfo(title: "Checkerboard", detail: "Advanced animations with Core Animation.") { [weak self] in
                    guard let self else { return }
                    route(to: CheckerboardFirstViewController())
                },
            ]),
            GroupInfo(title: "TabBar Controller Transitions", items: [
                ItemInfo(title: "Slide", detail: "Interactive transitions with UITabBarController.") { [weak self] in
                    guard let self else { return }
                    route(to: makeSlideTabBarController())
                },
            ]),
        ]
    }
    
    func route(to viewController: UIViewController) {
        // 场景一：直接 push
        navigationController?.pushViewController(viewController, animated: true)
        
        // 场景二（原版）：present 一个 navigation controller
        // var vc = viewController
        // vc.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Menu", style: .plain, target: self, action: #selector(self.menuAction(_:)))
        // vc = UINavigationController(rootViewController: viewController)
        // vc.modalPresentationStyle = .custom
        // present(vc, animated: true)
    }
    
    func makeSlideTabBarController() -> UITabBarController {
        let tabBarController = UITabBarController()
        
        let backgroundColors = [
            "A": "E6E6FF",
            "B": "FFE6E6",
            "C": "C9E6E6",
        ]
        tabBarController.viewControllers = ["A", "B", "C"].map { contentText in
            let viewController = UIViewController()
            viewController.view.setupContentLabel(text: contentText)
            viewController.view.backgroundColor = UIColor(backgroundColors[contentText]!)
            viewController.tabBarItem.title = contentText
            return viewController
        }
        let slideTransitionDelegate = SlideTransitionDelegate()
        slideTransitionDelegate.tabBarController = tabBarController
        
        return tabBarController
    }
    
    @objc func menuAction(_ sender: AnyObject) {
        dismiss(animated: true)
    }
}

extension MenuViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        data.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        data[section].items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
        let item = data[indexPath.section].items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.detail
        return cell
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        data[section].title
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        data[indexPath.section].items[indexPath.row].action()
    }
}
