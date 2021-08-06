# StitchedStreamPlayer

## 监听元数据

通过对AVPlayer对象添加`currentItem.timedMetadata`KVO监听实现对元数据的监听。

获取与处理：

```objective-c
// 获取
NSArray* array = [[player currentItem] timedMetadata];
for (AVMetadataItem *metadataItem in array) 
{
    [self handleTimedMetadata:metadataItem];
}

// 处理
- (void)handleTimedMetadata:(AVMetadataItem*)timedMetadata
{
    /* We expect the content to contain plists encoded as timed metadata. AVPlayer turns these into NSDictionaries. */
    // 获取GeneralEncapsulatedObject键
    if ([(NSString *)[timedMetadata key] isEqualToString:AVMetadataID3MetadataKeyGeneralEncapsulatedObject]) 
    {
        // 以字典格式处理值
        if ([[timedMetadata value] isKindOfClass:[NSDictionary class]]) 
        {
            NSDictionary *propertyList = (NSDictionary *)[timedMetadata value];
            
            // 获取ad-list
            /* Metadata payload could be the list of ads. */
            NSArray *newAdList = [propertyList objectForKey:@"ad-list"];
            if (newAdList != nil) 
            {
                NSLog(@"ad-list is %@", newAdList);
            }
            
            // 获取url
            /* Or it might be an ad record. */
            NSString *adURL = [propertyList objectForKey:@"url"];
            if (adURL != nil) 
            {
                if ([adURL isEqualToString:@""]) 
                {
                    // 清除文本，启用播放控件
                    NSLog(@"enabling seek at %g", CMTimeGetSeconds([player currentTime]));
                }
                else 
                {
                    // 设置文本，禁用播放控件
                    NSLog(@"disabling seek at %g", CMTimeGetSeconds([player currentTime]));
                }
            }
        }
    }
}
```

