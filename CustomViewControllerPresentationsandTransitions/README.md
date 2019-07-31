# Custom View Controller Presentations and Transitions

<!-- Custom View Controller Presentations and Transitions demonstrates using the view controller transitioning APIs to implement your own view controller presentations and transitions.  Learn from a collection of easy to understand examples how to use UIViewControllerAnimatedTransitioning, UIViewControllerInteractiveTransitioning, and UIPresentationController to create unique presentation styles that adapt to the available screen space. -->

该演示项目使用视图控制器过渡接口来实现你自己视图控制器的呈现和过渡。从简单的例子来学习如何使用 `UIViewControllerAnimatedTransitioning`、`UIViewControllerInteractiveTransitioning` 和 `UIPresentationController`集合来创建独特的呈现效果来使用可用的屏幕空间。

<!-- **IMPORTANT**: This sample should be run on an iOS device. Some animations may not display correctly in the iOS Simulator. -->

> **注意**
>
> 该示例应在 iOS 设备上运行。在 iOS 模拟器中，一些动画可能无法正常显示。

### Cross Dissolve - 交叉溶解 ###

<!-- This example implements a full screen presentation that transitions between view controllers using a cross dissolve animation.  It demonstrates the minimum configuration necessary to implement a custom transition. -->

该例子实现了控制器间使用交叉溶解动画实现全屏显示。它演示实现自定义过渡的最小配置。

- `transitioningDelegate<UIViewControllerTransitioningDelegate>`，该代理告诉谁来负责动画、谁来控制动画、谁来控制整个过渡过程

### Swipe - 侧滑 ###

<!-- This example implements a full screen presentation that transitions between view controllers by sliding the presented view controller on and off the screen.  You will learn how to implement UIPercentDrivenInteractiveTransition to add interactivity to your transitions. -->

该示例实现控制器间通过把视图控制器滑出滑入屏幕实现转换。你将学习如何实现 `UIPercentDrivenInteractiveTransition` 向过渡添加交互。

该示例重点在于实现从侧边过渡的动画，以及对动画过程的控制。

- AAPLSwipeTransitionDelegate 实现了 `UIViewControllerTransitioningDelegate` 协议，接收了一些属性，用于创建与配置需要返回的几个对象：
	- AAPLSwipeTransitionAnimator（实现了 `UIViewControllerAnimatedTransitioning`），提供了进场与退场动画的实现；
	- AAPLSwipeTransitionInteractionController（`UIPercentDrivenInteractiveTransition`），控制了进场、退场动画的过程（progress）；

### Custom Presentation - 自定义 ###

<!-- This example implements a custom presentation that displays the presented view controller in the lower third of the screen.  You will learn how to implement your own UIPresentationController subclass that defines a custom layout for the presented view controller, and responds to changes to the presented view controller's preferredContentSize. -->

该示例实现了一个呈现视图控制在屏幕三分之一的位置显示的自定义转换。你将学习如何实现自己的 `UIPresentationController` 子类来为呈现的视图控制器定义一个布局，并响应呈现的视图控制器的 `preferredContentSize` 值的改变。

该示例动用了许多自定义的操作，很巧妙，而且似乎相当实用。

AAPLCustomPresentationController，是 `UIPresentationController` 的子类，也实现了 `UIViewControllerTransitioningDelegate` 协议。在该类中实现中，动画实现、过渡管理都是自身。这样的做法以致于，AAPLCustomPresentationController 对象本身无需找地方引用着，生命周期伴随着 presented view controller。

该类在使用中，只需要调用 `-initWithPresentedViewController:presentingViewController:` 方法进行创建，再复制给第二个页面的 `transitioningDelegate` 属性即可。而在该初始化方法中，可将 presentedViewController 的 `modalPresentationStyle` 配置为 `UIModalPresentationCustom`。

#### 暗色、圆角、阴影效果

通过返回自定义的 `presentedView` 来对弹出的 presentedViewController 的视图进行包装，实现圆角、阴影效果。

而自定义 `presentedView` 是在 `-presentationTransitionWillBegin` 方法中完成，这时的 presentedViewController 视图层级已经就绪了。值得注意的是，通过调用父类的 `presentedView` 方法可以获取 presentedViewController 的视图。

这里的配置也很巧妙，使用 3 层的视图包装来实现圆角、阴影效果。因为圆角需要裁剪子视图，所以圆角层需要在阴影层之上，又因为只需要实现顶部的两个圆角，所以直接让底部的两个圆角超出视图范围被裁剪掉即可。另外，为了不影响 presentedViewController 的布局，还最后需要一层 presentedViewControllerWrapperView 在原本的位置布局。在这些包装视图布局过程中，充分使用了 autoresizingMask，使之具有自动布局属性。

暗色层，dimmingView，也是在 `-presentationTransitionWillBegin` 方法中完成创建与布局。不同的是，dimmingView 是添加到 `self.containerView` 上。最后还通过 `self.presentingViewController.transitionCoordinator` 的 `-animateAlongsideTransition:completion:` 方法实现 dimmingView 的动画淡入。

对应地，在 `-dismissalTransitionWillBegin` 方法中，用同样的方式对 dimmingView 动画淡出。

#### 动态改变视图大小

该示例最大的特点还在于其可以动态改变推出的视图的大小。其实现主要为：

1. `-preferredContentSizeDidChangeForChildContentContainer:`

该方法在视图控制器的 `preferredContentSize` 改变时进行调用，这里用于触发该控制器视图的自身布局。

2. `-sizeForChildContentContainer:withParentContainerSize:`

提供 presentedViewController 的 `preferredContentSize`。

3. `-frameOfPresentedViewInContainerView`

根据 containerView 提供 presentedView 的布局。

4. `-containerViewWillLayoutSubviews`

布局 dimmingView 和 presentationWrappingView。

#### 其他

其次，该类还实现了动画（`<UIViewControllerAnimatedTransitioning>`）和过渡代理（`<UIViewControllerTransitioningDelegate>`）。

### Adaptive Presentation - 自适应 ###

<!-- This example implements a custom presentation that responds to size class changes.  You will learn how to implement UIAdaptivePresentationControllerDelegate to adapt your presentation to the compact horizontal size class. -->

该示例实现了响应 size class 改变的自定义转换。你将学习如何实现 `UIAdaptivePresentationControllerDelegate` 来让你的转换适应水平紧凑 size class。

### Checkerboard - 棋盘 ###

<!-- This example implements a transition between two view controllers in a UINavigationController.  You will learn how to take your transitions into the third dimension with perspective transforms, and how to leverage the snapshotting APIs to create copies of views. -->

该示例实现在两个 UINavigationController 间的过渡。你将学习如何使用三维转换进行视角转换，并通过快照接口创建视图副本。

### Slide - 滑动 ###

<!-- This example implements an interactive transition between two view controllers in a UITabBarController.  You will learn how to implement an interactive transition where the destination view controller could change in the middle of the transition. -->

此示例实现了在 UITabBarController 中两个视图控制器之间的交互过渡。你将学习如何实现一个目标视图控制器在过渡中可变的可交互的过渡。


REQUIREMENTS
--------------------------------------------------------------------------------

### Build ###

Xcode 6 or later

### Runtime ###

iOS 7.1 or later (Some examples require iOS 8.0 or later)

CHANGES FROM PREVIOUS VERSIONS:
--------------------------------------------------------------------------------

+ Version 1.0 
    - First release.



================================================================================
Copyright (C) 2016 Apple Inc. All rights reserved.
