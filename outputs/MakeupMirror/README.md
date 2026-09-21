# 映妆 · 实时化妆镜 iPhone 原型

这是原生 SwiftUI 项目源码，不是已签名安装包。目标设备为 iOS 16 及以上的 iPhone，竖屏运行，无第三方依赖。当前制作环境是 Windows，没有 Xcode、iOS SDK 或真机；尚未编译或完成真机验证。

## 已编写的功能

- 前置镜像相机画面，Vision 本机面部关键点检测。
- 准备、腮红、唇妆、用户确认四个步骤，上一页/下一页。
- 腮红示意区域、唇部轮廓跟随同一帧面部位置；引导可关闭。
- 中文语音朗读，可关闭、重播；不使用麦克风、不支持语音指令。
- 单脸、正面、完整入镜的粗略检测；定位不满足条件时收起化妆引导。
- 权限拒绝提示、系统设置入口、相机中断提示和手动重试。
- 暂停/进入后台时停止相机，清空当前画面；回到前台手动继续。
- 没有文件保存、网络请求、账号、分析埋点或人脸身份识别。

## 在 Mac 上运行

1. 将整个 MakeupMirror 文件夹复制到 Mac，使用带 iOS 16+ SDK 的 Xcode 打开 `MakeupMirror.xcodeproj`。
2. 在项目的 Signing & Capabilities 中选择自己的开发 Team，把 Bundle Identifier 改为唯一值。
3. 连接 iPhone，完成设备信任和开发者模式设置，在 Xcode 中选择该 iPhone 为运行设备。
4. 点击 Run，进入 App 后点击“开启化妆镜”，允许相机访问。
5. 正面入镜后进入腮红、唇妆步骤，检查引导是否正确跟随面部。模拟器只能用于界面检查，不能代替相机真机测试。

也可以先在 Mac 上执行不签名的模拟器编译，检查 Swift 和工程配置：

```sh
xcodebuild -project MakeupMirror.xcodeproj -scheme MakeupMirror -sdk iphonesimulator -configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

## 原型的准确边界

“实时”指从摄像头连续取得画面并定位面部，处理上限约 12 帧/秒；实际速度取决于设备。预览与关键点共用一帧，使用等比例完整显示，避免预览裁切与引导坐标不一致。不是已经验证的流畅度或延迟指标。

腮红区域由眼睛位置和脸部宽高通过固定规则生成，仅作教学示意；唇部采用 Vision 轮廓。没有针对个人五官审美优化、肤色判断、妆容浓淡/均匀度识别、化妆动作识别、可靠的遮挡检测或光照测量。部分遮挡仍可能产生错误关键点。

“下一步”和“完成”是用户自己确认，不表示 AI 判定化妆正确。教程目前是内置文字与语音，无视频库。尚未实现后置摄像头切换、发型分析、全身穿搭、语音口令、账号和收藏。

使用兼容 iOS 16 的 videoOrientation 设置竖屏；新版 SDK 可能产生弃用警告，后续可迁移到 videoRotationAngle。生产版可使用独立高帧率预览层，同时验证关键点延迟补偿、镜像变换和设备发热。

## 真机验收清单（未执行）

- 首次允许/拒绝相机权限；拒绝后从设置返回，点击继续能重试。
- 在不同屏幕尺寸上确认中文、按钮、步骤说明可读；检查大字号与 VoiceOver。
- 面部左右移动、靠近、远离时，唇部轮廓和腮红提示不发生镜像或偏移错误。
- 无人脸、两个人、侧脸、低光、手/刷子遮挡时观察误判，不把结果当作妆效评价。
- 点击隐藏引导，所有引导消失；语音关闭后停止播报，重播按钮禁用。
- 暂停后画面清空；后台相机停止；来电或相机中断后可以重试。
- 完成四步、返回上一步、完成后重新练习、回首页均可操作。
- 连续运行 10 分钟，记录帧率、延迟、温度和电量消耗。
- 用系统网络工具确认无上传；确认相册、应用目录没有保存照片或视频。

## 下一阶段

先完成编译与真机定位验证，再收集经用户明确同意的测试反馈。之后把妆容检查作为独立模块研发：在用户点击“检查本步骤”后，对稳定画面输出有限、可解释的建议，并对不确定结果明确提示。不要直接将当前面部关键点逻辑用于妆效评分。

## Apple 技术参考

- [面部关键点检测](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest)
- [视频帧输出](https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput)
- [视频方向与物理缓冲旋转](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videoorientation)
- [镜像视频帧](https://developer.apple.com/documentation/avfoundation/avcaptureconnection/isvideomirrored)
