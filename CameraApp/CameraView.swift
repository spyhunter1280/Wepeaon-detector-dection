//
//  ContentView.swift
//  CameraApp
//
//  Created by Ali Asadullah on 9/28/23.
//

import SwiftUI
import AVFoundation
import CoreImage

class CameraViewModel: ObservableObject {
    @Published var captureSession: AVCaptureSession?
    
    init() {
        setupCamera()
    }
    
    func setupCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let captureSession = AVCaptureSession()
            guard let captureDevice = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: captureDevice) else {
                return
            }
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            captureSession.startRunning()
            
            DispatchQueue.main.async {
                self.captureSession = captureSession
            }
        }
    }
}

struct CameraView: View {
    @StateObject private var model = FrameHandler()
    @State var focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
    @State var exposureValue: Float = AVCaptureDevice.currentISO
    @State var maxExposureValue: Float = 0
    @State var minExposureValue: Float = 0
    @State var isAutoExposure = true
    @State var zoom: CGFloat = 0
       
       var body: some View {
           ZStack {
               FrameView(image: model.frame)
                   .frame(width: UIScreen.main.bounds.size.width , height: UIScreen.main.bounds.size.height )
//                   .ignoresSafeArea()
               VStack {
                   VStack {
                       HStack {
                           Spacer().frame(width: 20)
                           Text(String(format: "Zoom: %.2f", zoom))
                           Spacer()
                           Button {
                               changeFocusMode()
                           } label: {
                               Text("A_Foc: \(focusMode == .continuousAutoFocus ? "continuous" : "one time")")
                           }
                           Spacer().frame(width: 20)
                       }
                       Toggle(isOn: $isAutoExposure) {
                           Text("A_Exp:")
                       }
                       .padding(.horizontal, 20)
                   }
                   .foregroundColor(.yellow)
                   .background(.black.opacity(0.2))
                   .cornerRadius(20)
                   .padding(.top, 25)
                   HStack {
                       Button {
                           let input = model.captureSession.inputs[0] as? AVCaptureDeviceInput
                           
                           guard let device = input?.device else { return }
                           self.exposureValue = device.activeFormat.minISO
                       } label: {
                           Text("Min_Exp")
                       }
                       
                       Slider(value: $exposureValue, in: minExposureValue...maxExposureValue)
                       
                       Button {
                           let input = model.captureSession.inputs[0] as? AVCaptureDeviceInput
                           
                           guard let device = input?.device else { return }
                           self.exposureValue = device.activeFormat.maxISO
                       } label: {
                           Text("Max_Exp")
                       }
                   }
                   Spacer()
               }
               .padding()

           }
           .onChange(of: exposureValue, perform: { newValue in
               let input = model.captureSession.inputs[0] as? AVCaptureDeviceInput

               guard let device = input?.device else { return }
               if device.isExposureModeSupported(.custom) {
                   do{
                       try device.lockForConfiguration()
                       self.isAutoExposure = false
                       device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: exposureValue) { (_) in
                           print("Done Exsposure")
                       }
                       device.unlockForConfiguration()
                   }
                   catch{
                       print("ERROR: \(String(describing: error.localizedDescription))")
                   }
               }
           })
           .onChange(of: isAutoExposure, perform: { newValue in
               let input = model.captureSession.inputs[0] as? AVCaptureDeviceInput

               guard let device = input?.device else { return }
               guard  device.isExposureModeSupported(.continuousAutoExposure) else { return }
               
                   do{
                       try device.lockForConfiguration()
                       device.exposureMode = newValue ? .continuousAutoExposure : .autoExpose // can also be continuousAutoExposure same like Auto Focus
                       device.unlockForConfiguration()
                   }
                   catch{
                       print("ERROR: \(String(describing: error.localizedDescription))")
                   }
               
           })
           .onAppear(perform: {
               DispatchQueue.main.asyncAfter(deadline: .now()+1){
                   let input = model.captureSession.inputs[0] as? AVCaptureDeviceInput
                   
                   guard let device = input?.device else { return }
                   self.focusMode = device.focusMode
                   self.maxExposureValue = device.activeFormat.maxISO
                   self.minExposureValue = device.activeFormat.minISO
                   print(exposureValue)
               }
           })
       }
    
    func changeFocusMode() {
        let input = model.captureSession.inputs[0] as? AVCaptureDeviceInput

        guard let device = input?.device else { return }
        switch device.focusMode {
        case .autoFocus, .locked:
            if device.isFocusModeSupported(.continuousAutoFocus) {
                try! device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                self.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
            }
        case .continuousAutoFocus:
            if device.isFocusModeSupported(.autoFocus) {
                try! device.lockForConfiguration()
                device.focusMode = .autoFocus
                self.focusMode = .autoFocus
                device.unlockForConfiguration()
            }
        default:
            break
        }
    }
}


class FrameHandler: NSObject, ObservableObject {
    @Published var frame: CGImage?
    private var permissionGranted = true
    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private let context = CIContext()

    
    override init() {
        super.init()
        self.checkPermission()
        sessionQueue.async { [unowned self] in
            self.setupCaptureSession()
            self.captureSession.startRunning()
        }
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: // The user has previously granted access to the camera.
                self.permissionGranted = true
                
            case .notDetermined: // The user has not yet been asked for camera access.
                self.requestPermission()
                
        // Combine the two other cases into the default case
        default:
            self.permissionGranted = false
        }
    }
    
    func requestPermission() {
        // Strong reference not a problem here but might become one in the future.
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            self.permissionGranted = granted
        }
    }
    
    func setupCaptureSession() {
        let videoOutput = AVCaptureVideoDataOutput()
        
        guard permissionGranted else { return }
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,for: .video, position: .front) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sampleBufferQueue"))
        captureSession.addOutput(videoOutput)
        
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
    }
}


extension FrameHandler: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let cgImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else { return }
        
        // All UI updates should be/ must be performed on the main queue.
        DispatchQueue.main.async { [unowned self] in
            self.frame = cgImage
        }
    }
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            
        
        return cgImage
    }
    
}
struct FrameView: View {
    @State private var orientation: Image.Orientation = .upMirrored
    var image: CGImage?
    private let label = Text("frame")
    
    var body: some View {
        GeometryReader { geometry in
            if let image = image {
                let screenScale = UIScreen.main.scale
                let dynamicScale = min(geometry.size.width, geometry.size.height) / min(CGFloat(image.width) / screenScale, CGFloat(image.height) / screenScale)
                               
                Image(image, scale: dynamicScale, orientation: orientation, label: label)
                
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .magnificationEffect(2, 0, 200)

                    .onRotate { newOrientation in
                        
                        switch newOrientation {
                        case .portrait :
                            orientation = .upMirrored
                        case .landscapeRight :
                            orientation = .rightMirrored
                        case .landscapeLeft :
                            orientation = .leftMirrored
                        case .portraitUpsideDown :
                            orientation = .downMirrored
                        case .unknown:
                            orientation = .upMirrored
                        case .faceUp:
                            orientation = .upMirrored
                        case .faceDown:
                            orientation = .downMirrored
                        @unknown default:
                            orientation = .upMirrored
                        }
                        
                    }
            } else {
                Color.black
            }
        }
    }
}
#Preview {
    CameraView()
}
extension View{
    @ViewBuilder
    func magnificationEffect(_ scale: CGFloat,_ rotation: CGFloat,_ size: CGFloat = 0) -> some View{
        MagnificationEffectHelper(scale: scale, rotation: rotation, size: size) {
            self
        }
    }
}
fileprivate struct MagnificationEffectHelper<Content: View>: View{
    
    var scale: CGFloat
    var rotation: CGFloat
    var size: CGFloat
    var content: Content
    init(scale: CGFloat, rotation: CGFloat, size: CGFloat, @ViewBuilder content: @escaping
         ()->Content) {
        self.scale = scale
        self.rotation = rotation
        self.size = size
        self.content = content ()
        
    }
    @State var offset: CGSize = .zero
    @State var lastStoredOffset: CGSize = .zero
    var body: some View{
        ZStack {
            content
                .overlay {
                    GeometryReader {
                        let newCircleSize = 100.0
                        let size = $0.size
                        Rectangle()
                            .fill(.clear)
                            .offset(x: -offset.width, y: -offset.height)
                            .frame(width: newCircleSize, height: newCircleSize)
                            .scaleEffect(1+scale)
                            .clipShape(Rectangle())
                            .border(.black)
                            .offset(offset)
                            .frame(width: size.width, height: size.height)
                    }
                }
                .contentShape(Rectangle())
            VStack {
                Spacer()
                HStack {
                    let newCircleSize: CGFloat = 200
                    //    let size = $0.size
                    Spacer()
                    content
                        .offset(x: -offset.width, y: -offset.height)
                        .frame(width: newCircleSize, height: newCircleSize)
                        .scaleEffect(1+scale)
                        .clipShape(Rectangle())
                        .border(.black)
                        .frame(width: 300, height: 300)

                }
            }
            .padding(.bottom, 150)
            .padding(.trailing, 50)
        }
            
            .gesture(
                DragGesture()
                    .onChanged({ value in
                        offset = CGSize(width: value.translation.width+lastStoredOffset.width, height: value.translation.height+lastStoredOffset.height)
                    })
                    .onEnded({ _ in
                        lastStoredOffset = offset
                    })
            )
    }
}

struct DeviceRotationViewModifier: ViewModifier {
    let action: (UIDeviceOrientation) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                action(UIDevice.current.orientation)
            }
    }
}

extension View {
    func onRotate(perform action: @escaping (UIDeviceOrientation) -> Void) -> some View {
        self.modifier(DeviceRotationViewModifier(action: action))
    }
}
