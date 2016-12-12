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

### Swipe - 侧滑 ###

<!-- This example implements a full screen presentation that transitions between view controllers by sliding the presented view controller on and off the screen.  You will learn how to implement UIPercentDrivenInteractiveTransition to add interactivity to your transitions. -->

该示例实现控制器间通过把视图控制器滑出滑入屏幕实现转换。你将学习如何实现 `UIPercentDrivenInteractiveTransition` 向过渡添加交互。

### Custom Presentation - 自定义 ###

<!-- This example implements a custom presentation that displays the presented view controller in the lower third of the screen.  You will learn how to implement your own UIPresentationController subclass that defines a custom layout for the presented view controller, and responds to changes to the presented view controller's preferredContentSize. -->

该示例实现了一个呈现视图控制在屏幕三分之一的位置显示的自定义转换。你将学习如何实现自己的 `UIPresentationController` 子类来为呈现的视图控制器定义一个布局，并响应呈现的视图控制器的 `preferredContentSize` 值的改变。

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
