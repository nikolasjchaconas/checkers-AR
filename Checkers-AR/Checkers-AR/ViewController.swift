//
//  ViewController.swift
//  Checkers-AR
//
//  Created by Nikolas Chaconas on 10/21/16.
//  Copyright © 2016 Nikolas Chaconas. All rights reserved.
//

import UIKit
import AVFoundation
import OpenGLES

class ViewController: UIViewController, UINavigationControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, GLKViewDelegate {
    var calibrator : OpenCVWrapper = OpenCVWrapper()
    var openGL : OpenGLWrapper = OpenGLWrapper()
    @IBOutlet weak var calibrationInstructionsLabel: UILabel!
    var totalCalibrated = 0
    @IBOutlet weak var leftToCalibrateLabel: UILabel!
    let ud = UserDefaults.standard
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var previewView: UIImageView!
    @IBOutlet weak var calibrateImageButton: UIButton!
    @IBOutlet weak var beginGameButton: UIButton!
    @IBOutlet weak var beginCalibrationButton: UIButton!
    var calibratePressed : Bool = false
    var session = AVCaptureSession()
    var playing = false
    var rotated = false
    var openGLInitialized = false
    var previewLayer = AVCaptureVideoPreviewLayer()
    var playingLayer = CALayer()
    @IBOutlet weak var successLabel: UILabel!
    @IBOutlet weak var glkView: GLKView!
    var context : EAGLContext = EAGLContext.init(api: EAGLRenderingAPI.openGLES1)
    var effect = GLKBaseEffect()
    var currentImage : UIImage = UIImage()
    var imageSize : CGSize = CGSize()
    var frameBuffer : GLuint = GLuint()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
            beginGameButton.layer.cornerRadius = 5
            calibrateImageButton.layer.cornerRadius = 5
            beginCalibrationButton.layer.cornerRadius = 5
            glkView.delegate = self
            previewView.transform = CGAffineTransform(rotationAngle: 90.0 * 3.14 / 180.0)
        
            if let data = ud.object(forKey: "calibrator") as? NSData {
                print("retrieving calibrator data")
                let sync = ud.synchronize()
                
                if(sync == true) {
                    print("CALIBRATION can be LOADED")
                }
                calibrator = NSKeyedUnarchiver.unarchiveObject(with: data as Data) as! OpenCVWrapper
                
                print("saving calibration data")
                
                
                removeCalibrationPrompts()
            } else {
                print("calibrator not saved")
            }
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func removeCalibrationPrompts() {
        beginCalibrationButton.setTitle("Redo Checkerboard Calibration", for: .normal)
        beginCalibrationButton.alpha = 0.2;
        beginGameButton.alpha = 1.0;
        calibrateImageButton.alpha = 0.0
    }
    
    func finishCalibration() {
        print("done calibrating")
        
        //compute intrinsic camera values
        calibrator.finishCalibration()
        
        //remove all calibration buttons/labels
        removeCalibrationPrompts()

        //save calibration data so we don't have to calibrate next time user uses the app
        ud.set(NSKeyedArchiver.archivedData(withRootObject: calibrator), forKey: "calibrator")
        let sync = ud.synchronize()
        
        if(sync == true) {
            print("CALIBRATION DATA SAVED")
        }
        
        
        //will want to shut off camera and stuff here
        leftToCalibrateLabel.alpha = 0.0
        calibrationInstructionsLabel.alpha = 0.0
        session.stopRunning()
        
        successLabel.alpha = 1.0
        UIView.animate(withDuration: 2.70, animations: {
            self.successLabel.alpha = 0.0
        })
        
        clearLayers()
    }
    
    func calibrateImage(pickedImage: UIImage) {
        print("calibrating Image...")
        //disable button while calibrating
        calibrateImageButton.isEnabled = false;
        var img: UIImage
        img = calibrator.findChessboardCorners(pickedImage, true)
        
        //display calibrated image over camera view
        previewView.alpha = 1.0
        previewView.contentMode = .scaleAspectFill
        previewView.image = img
        
        //have to rotate image 90 degrees...
    
        //fade away calibrated image so user can take another image
        UIView.animate(withDuration: 2.70, animations: {
            self.previewView.alpha = 0.0
        })
        
        //increment calibrated count
        totalCalibrated += 1
        let leftToCalibrate = 10 - totalCalibrated
        leftToCalibrateLabel.text = "\(leftToCalibrate) Images Left To Calibrate"
        
        //only need 10 images to calibrate
        if(totalCalibrated == 10) {
            finishCalibration()
        } else {
            calibrateImageButton.isEnabled = true;
        }
    }

    func setPreviewLayer() {
        clearLayers()
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = imageView.bounds;
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;

        imageView.layer.addSublayer(previewLayer)
    }
    
    @IBAction func beginCalibrationButtonPressed(_ sender: AnyObject) {
        //reset class
        calibrator = OpenCVWrapper()
        session.stopRunning()
        playing = false
        imageView.image = nil
        beginGameButton.alpha = 0.0
        beginCalibrationButton.alpha = 0.0
        calibrateImageButton.isEnabled = true
        totalCalibrated = 0
        leftToCalibrateLabel.text = "10 Images Left To Calibrate"
        print("setting bloop")
        calibrator.setBloop(5000)
        
        //don't need to reinitialize camera if we've already used it
        if(session.inputs.isEmpty) {
            startCameraSession()
        } else {
            setPreviewLayer()
            session.startRunning()
        }
        
        //show calibration labels/buttons
        calibrationInstructionsLabel.alpha = 1.0
        leftToCalibrateLabel.alpha = 1.0
        calibrateImageButton.alpha = 1.0
    }
    
    func startCameraSession() {
        if session.canSetSessionPreset(AVCaptureSessionPresetMedium) {
            session.sessionPreset = AVCaptureSessionPresetMedium
        }
        
        let backCamera = AVCaptureDevice.defaultDevice(withMediaType:AVMediaTypeVideo)
        do
        {
            let input = try AVCaptureDeviceInput(device: backCamera)
            session.addInput(input)
        }
        catch
        {
            print("can't access camera")
            return
        }
        
        if(!playing && (imageView.layer.sublayers) == nil) {
            setPreviewLayer()
        }

        
        let output = AVCaptureVideoDataOutput()
        let queue = DispatchQueue(label: "queue")
        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as NSString: NSNumber(value: kCVPixelFormatType_32BGRA)]

        session.addOutput(output)

        session.startRunning()
    }

    func clearLayers() {
        imageView.layer.sublayers = nil
    }
    
    func setPlayingLayer() {
        clearLayers()
        playingLayer.transform = CATransform3DMakeRotation(90.0 * 3.14 / 180.0, 0.0, 0.0, 1.0);
        playingLayer.frame = self.imageView.bounds
        playingLayer.contentsGravity = kCAGravityCenter
        self.imageView.layer.addSublayer(playingLayer)
    }
    
    @IBAction func beginGameButtonPressed(_ sender: AnyObject) {
        //don't need to reinitialize camera if we've already used it
        playing = !playing;
        if(playing) {
            setPlayingLayer()
            if(session.inputs.isEmpty) {
                startCameraSession()
            } else {
                session.startRunning()
            }
        } else {
            clearLayers()
            session.stopRunning()
        }
    }
    
    func initializeOpenGL() {
        let x = (playingLayer.bounds.height - imageSize.height) / 2.0
        let y = (playingLayer.bounds.width - imageSize.width) / 2.0

        glkView.frame = CGRect(x: x, y: y, width: imageSize.height, height: imageSize.width)
        
        openGL = calibrator.initializeOpenGL()
        openGL.setView(self.glkView)
        
        
        print("setting context")
        EAGLContext.setCurrent(context)
        glkView.context = context
        glkView.enableSetNeedsDisplay = true;
        glkView.drawableColorFormat = GLKViewDrawableColorFormat.RGBA8888
        glkView.drawableDepthFormat = GLKViewDrawableDepthFormat.formatNone
        glkView.drawableStencilFormat = GLKViewDrawableStencilFormat.formatNone
        glkView.drawableMultisample = GLKViewDrawableMultisample.multisampleNone
        glkView.bindDrawable()
        glkView.isOpaque = false
        
        openGL.setParams(effect, cont: glkView.context, width: Double(imageSize.height), height: Double(imageSize.width))
    }
    
    func glkView(_ view: GLKView, drawIn rect: CGRect) {
        openGL.drawObjects()
    }
    
    @IBAction func calibrateImageButtonPressed(_ sender: AnyObject) {
        calibratePressed = true
    }
    
    
    //delegate for when frame is captured
    //override
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        if(calibratePressed) {
            calibratePressed = false
            let img : UIImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer);
            DispatchQueue.main.async {
                self.calibrateImage(pickedImage: img)
            }
        }
        if(playing) {
            let img : UIImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer);
            DispatchQueue.main.async {
                let newImage : UIImage;
                if(!self.calibrator.checkWait()) {
                    newImage = self.calibrator.findChessboardCorners(img, false)
                } else {
                    newImage = img
                }
                self.currentImage = newImage;
                self.glkView.display()
                self.playingLayer.contents = newImage.cgImage;
                
                if(self.openGLInitialized == false) {
                    self.openGLInitialized = true
                    self.imageSize = newImage.size
                    self.initializeOpenGL()
                }
            }
        }
    }
    
    //courtesy of apple documentation
    //https://developer.apple.com/library/content/qa/qa1702/_index.html
    func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        // Get the number of bytes per row for the pixel buffer
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!)
        
        // Get the number of bytes per row for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!)
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(imageBuffer!)
        let height = CVPixelBufferGetHeight(imageBuffer!)
        
        // Create a device-dependent RGB color space
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // Create a bitmap graphics context with the sample buffer data
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        // Create a Quartz image from the pixel data in the bitmap graphics context
        let quartzImage = context!.makeImage();
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer!,CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)));
        
        // Create an image object from the Quartz image
        let image = UIImage(cgImage: quartzImage!, scale: 1.0, orientation: UIImageOrientation.up)
        
        return image
    }

}

