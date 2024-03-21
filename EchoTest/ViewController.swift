import UIKit
import AVFoundation
import Vision
import CropViewController

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let captureQueue = DispatchQueue(label: "captureQueue")
    var isLookingStraight = false
    var photoOutput: AVCapturePhotoOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var captureButton = UIButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func setupCaptureSession() {
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)
            session.addInput(input)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            session.addOutput(videoOutput)

            photoOutput = AVCapturePhotoOutput()
            session.addOutput(photoOutput!)

            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer?.videoGravity = .resizeAspectFill
            if let previewLayer = previewLayer {
                view.layer.addSublayer(previewLayer)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        } catch {
            print(error.localizedDescription)
        }
    }

    private func setupUI() {
        captureButton = UIButton(type: .system)
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.layer.borderWidth = 3
        captureButton.clipsToBounds = true
        view.addSubview(captureButton)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalTo: captureButton.widthAnchor)
        ])

        updateCaptureButtonAvailability()
    }

    @objc private func captureButtonTapped() {
        checkCameraPermission()
        if isLookingStraight {
            capturePhoto()
        }
    }

    private func capturePhoto() {
        guard let videoConnection = session.outputs.first?.connection(with: .video) else {
            return
        }

        let settings = AVCapturePhotoSettings()
        videoConnection.videoOrientation = .portrait

        photoOutput?.capturePhoto(with: settings, delegate: self)
    }
    
    private func showCrop(image: UIImage) {
        let cropController = CropViewController(croppingStyle: .default, image: image)
        cropController.aspectRatioPreset = .presetSquare
        cropController.toolbarPosition = .bottom
        cropController.doneButtonColor = .white
        cropController.cancelButtonColor = .white

        cropController.delegate = self

        cropController.modalTransitionStyle = .crossDissolve

        present(cropController, animated: true)
    }
    
    private func updateCaptureButtonAvailability() {
        captureButton.backgroundColor = isLookingStraight ?  UIColor.green : UIColor.red
    }
    
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            print("Разрешение на использование камеры получено")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    print("Разрешение на использование камеры получено")
                } else {
                    print("Разрешение на использование камеры не получено")
                    self.showCameraPermissionAlert()
                }
            }
        case .denied, .restricted:
            print("Разрешение на использование камеры отклонено или ограничено")
            showCameraPermissionAlert()
        @unknown default:
            print("Неизвестный статус разрешения на использование камеры")
            showCameraPermissionAlert()
        }
    }

    func showCameraPermissionAlert() {
        let alertController = UIAlertController(title: "Нет разрешения на использование камеры", message: "Для использования камеры необходимо предоставить разрешение. Вы можете включить разрешение в настройках приложения.", preferredStyle: .alert)
        
        let settingsAction = UIAlertAction(title: "Настройки", style: .default) { _ in
            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            
            if UIApplication.shared.canOpenURL(settingsUrl) {
                UIApplication.shared.open(settingsUrl)
            }
        }
        
        let cancelAction = UIAlertAction(title: "Отмена", style: .cancel, handler: nil)
        
        alertController.addAction(settingsAction)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: false)
    }
}

extension ViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print(error.localizedDescription)
            return
        }

        guard let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) else {
            return
        }
        
        showCrop(image: image)
    }
}

extension ViewController: CropViewControllerDelegate {
    func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
        cropViewController.dismiss(animated: true)
    }

    func cropViewController(_ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
        cropViewController.dismiss(animated: true)
        ImageUploadService().uploadImage(image) { result in
            switch result {
            case .success(let message):
                print(message)
            case .failure(let error):
                print(error)
            }
        }
    }
}

extension ViewController {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let request = VNDetectFaceLandmarksRequest(completionHandler: handleFaceDetection)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print(error)
        }
    }
    
    func handleFaceDetection(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNFaceObservation] else {
            return
        }
        
        for observation in observations {
            if let landmarks = observation.landmarks, let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye {
                let leftEyePosition = leftEye.normalizedPoints.first
                let rightEyePosition = rightEye.normalizedPoints.first
                
                if let leftEyePos = leftEyePosition, let rightEyePos = rightEyePosition,
                   leftEyePos.x > 0, leftEyePos.x < 1, leftEyePos.y > 0, leftEyePos.y < 1,
                   rightEyePos.x > 0, rightEyePos.x < 1, rightEyePos.y > 0, rightEyePos.y < 1 {
                    
                    let lookThreshold: CGFloat = 0.05
                    
                    let isLookingAtCamera = abs(leftEyePos.y - rightEyePos.y) < lookThreshold
                    
                    DispatchQueue.main.sync {
                        self.isLookingStraight = isLookingAtCamera
                        self.updateCaptureButtonAvailability()
                    }
                }
            }
        }
    }
}
