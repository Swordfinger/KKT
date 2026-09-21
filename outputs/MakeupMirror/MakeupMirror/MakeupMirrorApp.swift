import SwiftUI
import AVFoundation
import Vision
import CoreImage

@main
struct MakeupMirrorApp: App {
    var body: some Scene { WindowGroup { MirrorScreen() } }
}

enum MakeupStep: Int, CaseIterable {
    case prepare, blush, lips, review
    var title: String { ["准备好你的化妆镜", "轻扫腮红", "描绘唇色", "照镜确认"][rawValue] }
    var instruction: String {
        ["面向柔和的自然光，将整个面部放入画面。准备腮红、刷具和唇膏。",
         "微笑放松，在标示区域少量上色，再向外轻轻晕染。引导区域仅供参考，可按自己的喜好调整。",
         "沿着虚线所示的唇部轮廓，从唇中央向两侧少量涂抹。张嘴或转头时，请暂停描画。",
         "移开手和工具，在镜中检查两侧颜色及边缘。当前版本不能判断妆效；满意后可自行完成，不满意可返回调整。"][rawValue]
    }
}

// Image and landmarks always originate from the same physically rotated/mirrored frame.
struct MirrorFrame {
    let image: CGImage
    let face: CGRect?
    let lips: [CGPoint]
    let cheeks: [CGRect]
    let hint: String
    let ready: Bool
}

final class MirrorCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var frame: MirrorFrame?
    @Published private(set) var status = "点击开始，开启你的化妆镜"
    @Published private(set) var denied = false
    @Published private(set) var active = false
    private let session = AVCaptureSession()
    // All capture configuration and frame analysis run on this serial queue.
    private let queue = DispatchQueue(label: "mirror.capture", qos: .userInitiated)
    private let context = CIContext()
    private var configured = false
    private var lastFrame = -Double.infinity
    private var observers: [NSObjectProtocol] = []
    // Main-thread generation invalidates frames queued before a pause/restart.
    private var generation = 0
    private var captureGeneration = 0

    override init() {
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                self?.stop()
                self?.status = "相机已中断，请点击继续重试"
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start() {
        guard !active else { return }
        generation += 1
        let token = generation
        denied = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: launch(token)
        case .notDetermined:
            status = "请允许使用前置摄像头"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, self.generation == token else { return }
                    if granted { self.launch(token) } else { self.permissionDenied() }
                }
            }
        default: permissionDenied()
        }
    }

    private func permissionDenied() {
        denied = true
        status = "相机不可用，请在系统设置中允许相机访问"
    }

    private func launch(_ token: Int) {
        active = true
        status = "正在启动前置摄像头…"
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                if !self.configured { try self.configure() }
                self.captureGeneration = token
                self.lastFrame = -Double.infinity
                self.session.startRunning()
                if !self.session.isRunning { throw CameraError.unavailable }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.active = false
                    self.status = "无法启动相机，请在真实 iPhone 上重试"
                }
            }
        }
    }

    func stop() {
        generation += 1
        active = false
        frame = nil
        status = "化妆镜已暂停"
        queue.async { [weak self] in self?.session.stopRunning() }
    }

    private enum CameraError: Error { case unavailable }
    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // A failed attempt can be safely retried without duplicate inputs/outputs.
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.sessionPreset = .vga640x480
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { throw CameraError.unavailable }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addOutput(output)
        guard let connection = output.connection(with: .video), connection.isVideoOrientationSupported, connection.isVideoMirroringSupported else { throw CameraError.unavailable }
        connection.videoOrientation = .portrait
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard time - lastFrame >= 1.0 / 12.0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = time
        autoreleasepool {
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let image = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            let request = VNDetectFaceLandmarksRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
            let result: MirrorFrame
            do {
                try handler.perform([request])
                let faces = request.results ?? []
                if faces.count == 1, let face = faces.first {
                    result = Self.makeFrame(image, face)
                } else {
                    result = MirrorFrame(image: image, face: nil, lips: [], cheeks: [], hint: faces.isEmpty ? "请将面部放入画面，并移开遮挡" : "请保持画面内只有一张脸", ready: false)
                }
            } catch {
                result = MirrorFrame(image: image, face: nil, lips: [], cheeks: [], hint: "暂时无法定位，请调整光线并正对镜头", ready: false)
            }
            let token = captureGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.active, self.generation == token else { return }
                self.frame = result
            }
        }
    }

    private static func makeFrame(_ image: CGImage, _ observation: VNFaceObservation) -> MirrorFrame {
        let box = observation.boundingBox
        let face = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            (region?.normalizedPoints ?? []).map { CGPoint(x: box.minX + $0.x * box.width, y: 1 - (box.minY + $0.y * box.height)) }
        }
        func center(_ values: [CGPoint]) -> CGPoint? {
            guard !values.isEmpty else { return nil }
            return CGPoint(x: values.map(\.x).reduce(0, +) / CGFloat(values.count), y: values.map(\.y).reduce(0, +) / CGFloat(values.count))
        }
        let landmarks = observation.landmarks
        let lips = points(landmarks?.outerLips)
        let eyes = [center(points(landmarks?.leftEye)), center(points(landmarks?.rightEye))].compactMap { $0 }
        let frontal = abs(observation.yaw?.doubleValue ?? 0) < 0.22 && abs(observation.roll?.doubleValue ?? 0) < 0.22
        let inside = box.minX > 0.03 && box.maxX < 0.97 && box.minY > 0.03 && box.maxY < 0.97
        let ready = frontal && inside && box.width > 0.27 && observation.confidence > 0.7 && eyes.count == 2 && lips.count > 5
        let cheeks = eyes.map { eye in
            CGRect(x: eye.x - box.width * 0.12, y: eye.y + box.height * 0.13, width: box.width * 0.24, height: box.height * 0.13)
        }
        let hint = ready ? "位置已对齐 · 引导区域仅供参考" : (!frontal ? "请正对镜头，暂时收起引导线" : "请让整张脸清晰入镜，稍微靠近并移开遮挡")
        return MirrorFrame(image: image, face: face, lips: ready ? lips : [], cheeks: ready ? cheeks : [], hint: hint, ready: ready)
    }
}

final class VoiceCoach: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.46
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

struct MirrorScreen: View {
    @StateObject private var camera = MirrorCamera()
    @StateObject private var voice = VoiceCoach()
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = false
    @State private var step: MakeupStep = .prepare
    @State private var spoken = true
    @State private var showGuide = true
    @State private var completed = false
    private let accent = Color(red: 0.96, green: 0.66, blue: 0.61)

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("映妆").font(.title2.bold())
                        Text("你的随身化妆镜").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("本机处理").font(.caption).padding(9).background(.white.opacity(0.08), in: Capsule())
                }
                if started {
                    mirror
                    controls
                    lesson
                } else {
                    Spacer()
                    Image(systemName: "sparkles.rectangle.stack").font(.system(size: 76, weight: .ultraLight)).foregroundStyle(accent)
                    Text("跟着镜子，慢慢化好每一步").font(.title2.bold()).multilineTextAlignment(.center)
                    Text("实时面部引导 · 腮红与唇妆 · 中文语音").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("点击开始后申请相机权限。画面仅用于本机面部定位，不保存、不上传。无需麦克风权限。建议是通用教学，不包含自动妆效评分。").font(.footnote).foregroundStyle(.secondary)
                    Button("开启化妆镜") { started = true; camera.start() }.buttonStyle(PrimaryButton(color: accent))
                }
            }.padding(20)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            // Explicit resume avoids restarting the camera unexpectedly on return.
            if phase == .background { camera.stop(); voice.stop() }
        }
        .onDisappear { camera.stop(); voice.stop() }
        .alert("今天的练习完成了", isPresented: $completed) {
            Button("再练一次") { step = .prepare; camera.start() }
            Button("回到首页") { started = false; step = .prepare }
        } message: { Text("完成状态由你确认；本次画面没有保存。") }
    }

    private var mirror: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let frame = camera.frame {
                    let scale = min(geometry.size.width / CGFloat(frame.image.width), geometry.size.height / CGFloat(frame.image.height))
                    let size = CGSize(width: CGFloat(frame.image.width) * scale, height: CGFloat(frame.image.height) * scale)
                    Image(decorative: frame.image, scale: 1).resizable().frame(width: size.width, height: size.height)
                        .overlay {
                            if showGuide { FaceGuide(frame: frame, step: step).frame(width: size.width, height: size.height) }
                        }
                    VStack {
                        Spacer()
                        Text(frame.hint).font(.caption).padding(10).background(.black.opacity(0.7), in: Capsule()).padding(10)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "viewfinder").font(.largeTitle).foregroundStyle(accent)
                        Text(camera.status).font(.subheadline).multilineTextAlignment(.center)
                        if camera.denied {
                            Button("打开系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    }.padding()
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipShape(RoundedRectangle(cornerRadius: 24))
        }.frame(minHeight: 180, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button { showGuide.toggle() } label: { Label("引导", systemImage: showGuide ? "viewfinder" : "eye.slash") }
                .accessibilityLabel(showGuide ? "隐藏引导" : "显示引导")
            Button { spoken.toggle(); if !spoken { voice.stop() } } label: { Label("语音", systemImage: spoken ? "speaker.wave.2" : "speaker.slash") }
                .accessibilityLabel(spoken ? "关闭语音" : "开启语音")
            Spacer()
            Button(camera.active ? "暂停" : "继续") {
                if camera.active { camera.stop(); voice.stop() } else { camera.start() }
            }
        }.font(.subheadline).tint(accent)
    }

    private var lesson: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                ForEach(MakeupStep.allCases, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? accent : .white.opacity(0.12)).frame(height: 3)
                }
            }
            HStack {
                Text("0\(step.rawValue + 1) / 04").font(.caption.monospacedDigit()).foregroundStyle(accent)
                Text(step.title).font(.headline)
                Spacer()
                Button { voice.speak(step.instruction) } label: { Image(systemName: "play.circle") }.disabled(!spoken).accessibilityLabel("朗读本步骤")
            }
            ScrollView { Text(step.instruction).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 72)
            HStack {
                Button("上一步") { changeStep(-1) }.disabled(step == .prepare).padding(.trailing, 8)
                Button(step == .review ? "我已确认，完成" : "我准备好了，下一步") {
                    if step == .review { camera.stop(); voice.stop(); completed = true } else { changeStep(1) }
                }.buttonStyle(PrimaryButton(color: accent)).disabled(!camera.active || camera.frame?.ready != true)
            }
        }.padding(16).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
    }

    private func changeStep(_ delta: Int) {
        guard let next = MakeupStep(rawValue: step.rawValue + delta) else { return }
        step = next
        if spoken { voice.speak(step.instruction) }
    }
}

struct FaceGuide: View {
    let frame: MirrorFrame
    let step: MakeupStep
    var body: some View {
        Canvas { context, size in
            func rect(_ value: CGRect) -> CGRect { CGRect(x: value.minX * size.width, y: value.minY * size.height, width: value.width * size.width, height: value.height * size.height) }
            if step == .prepare, let face = frame.face {
                context.stroke(Path(roundedRect: rect(face), cornerRadius: 25), with: .color(frame.ready ? .mint : .orange), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            }
            if step == .blush {
                for cheek in frame.cheeks {
                    let path = Path(ellipseIn: rect(cheek))
                    context.fill(path, with: .color(.pink.opacity(0.19)))
                    context.stroke(path, with: .color(.pink.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            if step == .lips, let first = frame.lips.first {
                var path = Path()
                path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                for point in frame.lips.dropFirst() { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
                path.closeSubpath()
                context.stroke(path, with: .color(.pink), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PrimaryButton: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 15)
            .foregroundStyle(.black).background(color.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 15))
    }
}
