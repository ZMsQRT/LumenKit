# LumenKit

项目无关的 iOS 工具库，包含文本与日期格式化、缓存路径恢复、SwiftUI 样式和刷新组件，以及音视频播放基础能力。最低支持 iOS 17。

在 Podfile 中添加 LumenKit 索引源和 CocoaPods 官方源，然后声明版本：

```ruby
source 'https://github.com/ZMsQRT/LumenKit.git'
source 'https://cdn.cocoapods.org/'

pod 'LumenKit', '0.1.0'
```

也可以直接通过 Git 版本标签接入：

```ruby
pod 'LumenKit', :git => 'https://github.com/ZMsQRT/LumenKit.git', :tag => '0.1.0'
```

本地开发时也可以在 Podfile 中使用：

```ruby
pod 'LumenKit', :path => 'LumenKit'
```

播放器通过构造参数接收 URL 解析、资源路径查找和日志回调；刷新组件允许调用方传入颜色和文案。库自身不包含业务配置或资源。

在应用中使用时导入 `LumenKit`；格式化、文本工具、视图组件和播放器分别通过 `NumberFormatting`、`DateFormatting`、`TextUtilities`、`AnimatedCounter`、`VideoPlaybackController` 和 `AudioPlayback` 等接口提供。原项目保留了兼容层，以便现有调用方继续使用原有配置。

新版本发布时更新 `LumenKit.podspec` 中的版本号，创建同名 Git 标签，再将对应 podspec 放入 `Specs/LumenKit/<版本号>/`。已经发布的版本索引和标签应保持不变。
