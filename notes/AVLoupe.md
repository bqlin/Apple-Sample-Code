# AVLoupe

## 图层布局

这里使用了两个AVPlayerLayer：

- `zoomPlayerLayer`：顶部，大尺寸
- `mainPlayerLayer`：底部，原始尺寸。添加在`self.view.layer`上。

为了展示遮罩效果，`zoomPlayerLayer`不是直接布局的，而是作为设置了`mask`的`contentLayer`上，最终是添加在图片`loupeView.layer`。

上面除了`zoomPlayerLayer`，其他视图、图层都是使用控件的尺寸。

## pan移动放大镜

这个过程有点意思，以方便通过改变放大镜视图（`loupeView`/`recognizer.view`）的中点实现位移，另一方面，设置`zoomPlayerLayer.position`，反向微调位移。

```objective-c
- (IBAction)handlePanFrom:(UIPanGestureRecognizer *)recognizer
{
    CGPoint translation = [recognizer translationInView:self.view];
    
    recognizer.view.center = CGPointMake(recognizer.view.center.x + translation.x,
                                         recognizer.view.center.y + translation.y);
    [recognizer setTranslation:CGPointMake(0, 0) inView:self.view];
    
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.zoomPlayerLayer.position = CGPointMake(self.zoomPlayerLayer.position.x - translation.x * ZOOM_FACTOR,
                                            self.zoomPlayerLayer.position.y - translation.y * ZOOM_FACTOR);
    [CATransaction commit];
}
```
