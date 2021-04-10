//
// Created by Bq Lin on 2021/4/10.
//

import UIKit

class NewDetailViewController: UIViewController {
    static var level = 0
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Detail - \(Self.level)" // 标题越长，返回按钮展示的信息越少，上一级标题>返回>仅返回图标
        view.backgroundColor = .cyan
        
        // 交错设置，偶数页为🔼，奇数页为🔽
        var backImage = UIImage(named: "UpArrow")
        if Self.level % 2 == 1 {
            backImage = UIImage(named: "DownArrow")
            view.backgroundColor = .orange
        }
        backImage = backImage?.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: backImage!.size.width - 1, bottom: 0, right: 0))
        
        // 获取navigationBar，对比两种获取方式的微妙之处
        var bar: UINavigationBar
        bar = navigationController!.navigationBar
        // if #available(iOS 9.0, *) {
        //     bar = UINavigationBar.appearance(whenContainedInInstancesOf: [CustomBackButtonNavController.self])
        // }
        
        // 设置返回按钮左侧图标
        bar.backIndicatorImage = backImage
        bar.backIndicatorTransitionMaskImage = backImage
        
        // 设置下一级返回图标右侧按钮
        // image: backImage
        // title: "\(Self.level)
        navigationItem.backBarButtonItem = UIBarButtonItem(image: backImage, style: .plain, target: nil, action: nil)
        // 隐藏右侧内容
        // navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        
        // 隐藏整个返回按钮
        // self.navigationItem.hidesBackButton = true
        Self.level += 1
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        navigationController?.pushViewController(NewDetailViewController(), animated: true)
    }
    
    deinit {
        Self.level -= 1
    }
}
