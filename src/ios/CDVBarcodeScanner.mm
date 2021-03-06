/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AudioToolbox/AudioToolbox.h>

//------------------------------------------------------------------------------
// use the all-in-one version of zxing that we built
//------------------------------------------------------------------------------
#import "zxing-all-in-one.h"
#import <Cordova/CDVPlugin.h>

#import "TextResponseSerializer.h"
#import "HttpManager.h"

//------------------------------------------------------------------------------
// Delegate to handle orientation functions
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>

- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotate;

@end

@interface AlertView: UIAlertView<UIAlertViewDelegate>
@property (copy, nonatomic) void (^completion)(BOOL, NSInteger);

- (id)initWithTitle:(NSString *)title message:(NSString *)message cancelButtonTitle:(NSString *)cancelButtonTitle otherButtonTitles:(NSArray *)otherButtonTitles;

@end

@implementation AlertView
    
- (id)initWithTitle:(NSString *)title message:(NSString *)message cancelButtonTitle:(NSString *)cancelButtonTitle otherButtonTitles:(NSArray *)otherButtonTitles {
    
    self = [self initWithTitle:title message:message delegate:self cancelButtonTitle:cancelButtonTitle otherButtonTitles:nil];
    
    if (self) {
        for (NSString *buttonTitle in otherButtonTitles) {
            [self addButtonWithTitle:buttonTitle];
        }
    }
    return self;
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    
    if (self.completion) {
        self.completion(buttonIndex==self.cancelButtonIndex, buttonIndex);
        self.completion = nil;
    }
}


@end

//------------------------------------------------------------------------------
// Adds a shutter button to the UI, and changes the scan from continuous to
// only performing a scan when you click the shutter button.  For testing.
//------------------------------------------------------------------------------
#define USE_SHUTTER 0

//------------------------------------------------------------------------------
@class CDVbcsProcessor;
@class CDVbcsViewController;

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVBarcodeScanner : CDVPlugin {}
@property (nonatomic, retain) NSString*                 action;

- (NSString*)isScanNotPossible;
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)encode:(CDVInvokedUrlCommand*)command;
- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback;
- (void)decode: (CDVInvokedUrlCommand*)command;
- (void)returnSuccess:(NSString*)scannedText scanner:(CDVbcsProcessor*)scanner host:(NSString*)host parkinglotId:(NSString*)parkinglotId format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessor : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate> {}
@property (nonatomic, retain) CDVBarcodeScanner*           plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewController*        viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSString*                   alternateXib;
@property (nonatomic)         BOOL                        is1D;
@property (nonatomic)         BOOL                        is2D;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic, retain) NSString*                   resText;
@property (nonatomic, retain) NSString*                   host;
@property (nonatomic, retain) NSString*                   parkinglotId;
@property (nonatomic)         BOOL                        isFrontCamera;
@property (nonatomic)         BOOL                        isFlipped;
@property (nonatomic)         BOOL                        isDecode;


- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback host:(NSString*)host parkinglotId:(NSString*)parkinglotId parentViewController:(UIViewController*)parentViewController alterateOverlayXib:(NSString *)alternateXib;
- (void)scanBarcode;
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (void)openDialog;
- (NSString*)setUpCaptureSession;
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection;
- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format;
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer;
- (zxing::Ref<zxing::LuminanceSource>) getLuminanceSourceFromSample:(CMSampleBufferRef)sampleBuffer imageBytes:(uint8_t**)ptr;
- (UIImage*) getImageFromLuminanceSource:(zxing::LuminanceSource*)luminanceSource;
- (void)dumpImage:(UIImage*)image;
@end

//------------------------------------------------------------------------------
// Qr encoder processor
//------------------------------------------------------------------------------
@interface CDVqrProcessor: NSObject
@property (nonatomic, retain) CDVBarcodeScanner*          plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) NSString*                   stringToEncode;
@property                     NSInteger                   size;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode;
- (void)generateImage;
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@interface CDVbcsViewController : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
@property (nonatomic, retain) CDVbcsProcessor*  processor;
@property (nonatomic, retain) NSString*        alternateXib;
@property (nonatomic)         BOOL             shutterPressed;
@property (nonatomic, retain) IBOutlet UIView* overlayView;
// unsafe_unretained is equivalent to assign - used to prevent retain cycles in the property below
@property (nonatomic, unsafe_unretained) id orientationDelegate;
@property (nonatomic, retain) UILabel* uiLabel;

- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib;
- (void)startCapturing;
- (UIView*)buildOverlayView;
- (UIImage*)buildReticleImage;
- (void)shutterButtonPressed;
- (IBAction)cancelButtonPressed:(id)sender;

@end

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@implementation CDVBarcodeScanner
@synthesize action              = _action;

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;
    
    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }
    
    return result;
}

//--------------------------------------------------------------------------
- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVbcsProcessor* processor;
    NSString*       callback;
    NSString*       capabilityError;
    
    NSMutableDictionary* options = [command.arguments objectAtIndex:0];
    NSString* host = [options objectForKey:@"host"];
    NSString* parkinglotId = [options objectForKey:@"parkinglotId"];
    self.action = @"scan";
    
    callback = command.callbackId;
    
    // We allow the user to define an alternate xib file for loading the overlay.
    NSString *overlayXib = nil;
//    if ( [command.arguments count] >= 1 )
//    {
//        overlayXib = [command.arguments objectAtIndex:0];
//    }
    
    capabilityError = [self isScanNotPossible];
    if (capabilityError) {
        [self returnError:capabilityError callback:callback];
        return;
    }
    
    processor = [[CDVbcsProcessor alloc]
                 initWithPlugin:self
                 callback:callback
                 host:host
                 parkinglotId:parkinglotId
                 parentViewController:self.viewController
                 alterateOverlayXib:overlayXib
                 isDecode:false
                 ];
    [processor retain];
    [processor retain];
    [processor retain];
    // queue [processor scanBarcode] to run on the event loop
    [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (void)encode:(CDVInvokedUrlCommand*)command {
    if([command.arguments count] < 1)
        [self returnError:@"Too few arguments!" callback:command.callbackId];
    
    CDVqrProcessor* processor;
    NSString*       callback;
    callback = command.callbackId;
    
    processor = [[CDVqrProcessor alloc]
                 initWithPlugin:self
                 callback:callback
                 stringToEncode: command.arguments[0][@"data"]
                 ];
    
    [processor retain];
    [processor retain];
    [processor retain];
    // queue [processor generateImage] to run on the event loop
    [processor performSelector:@selector(generateImage) withObject:nil afterDelay:0];
}

- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback{
    NSMutableDictionary* resultDict = [[[NSMutableDictionary alloc] init] autorelease];
    [resultDict setObject:format forKey:@"format"];
    [resultDict setObject:filePath forKey:@"file"];
    
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary:resultDict
                               ];
    
    [[self commandDelegate] sendPluginResult:result callbackId:callback];
}

-(void)decode:(CDVInvokedUrlCommand *)command{
    CDVbcsProcessor* processor;
    NSString*       callback;
    NSString*       capabilityError;
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText scanner:(CDVbcsProcessor*)scanner host:(NSString *)host parkinglotId:(NSString *)parkinglotId format:(NSString *)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString *)callback{
    if (!cancelled){
        if([self.action isEqualToString:@"scan"]){
            NSArray *scannedTextArray = [scannedText componentsSeparatedByString:@"parkinglotcouponuser="];
            if ([scannedTextArray count] == 2) {
                NSString *res = [scannedTextArray objectAtIndex: 1];
                NSArray *resArray = [res componentsSeparatedByString:@"__"];
                if ([resArray count] == 2) {
                    NSString *parkinglotcouponuserPk = [resArray objectAtIndex:0];
                    NSString *code = [resArray objectAtIndex:1];
                    NSString *url = [NSString stringWithFormat:@"%@/parking/parkinglotcouponusers/%@/parkinglot/%@/code/%@/check?no_use=1", host, parkinglotcouponuserPk, parkinglotId, code];
                    
                    scanner.viewController.uiLabel.text = @"请求中...";
                    HttpManager *manager = [HttpManager sharedClient];
                    manager.responseSerializer = [AFJSONResponseSerializer serializer];
                    [manager POST:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
                        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
                        [dictionary setObject:[NSNumber numberWithInt:operation.response.statusCode] forKey:@"status"];
                        [dictionary setObject:responseObject forKey:@"data"];
                        
                        NSDictionary *dic = (NSDictionary *) responseObject;
                        NSString *content = @"";
                        NSDate *date = nil;
                        if([dic objectForKey:@"parkinglot_coupon_name"]){
                            content = [content stringByAppendingFormat:@"%@\n", [dic objectForKey:@"parkinglot_coupon_name"]];
                        }
                        if(![[dic objectForKey: @"check"] boolValue]){
                            
                            if([dic objectForKey: @"used_at"] != [NSNull null]){
                                content = [content stringByAppendingString: @"该抵扣券已被使用\n"];
                                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                                [dateFormatter setDateFormat: @"yyyy-MM-dd'T'HH:mm:ss.SSS"];
                                date = [dateFormatter dateFromString: [dic objectForKey: @"used_at"]];
                                [dateFormatter release];
                            }else{
                                content = [content stringByAppendingString: @"该抵扣券已过期\n"];
                            }
                        }else{
//                            content = [content stringByAppendingString: @"抵扣券有效\n"];
                            date = [NSDate date];
                        }
                        content = [content stringByAppendingFormat: @"抵扣券价格：%@\n", [dic objectForKey:@"origin_price"]];
                        if(date != nil && ![[dic objectForKey: @"check"] boolValue]){
                            content = [content stringByAppendingString:@"使用时间："];
                            long interval = -[date timeIntervalSinceNow];
                            if(interval < 5){
                                content = [content stringByAppendingString:@"现在"];
                            }else if(interval < 60){
                                content = [content stringByAppendingFormat:@"%ld秒前", interval];
                            }else{
                                long minute = interval / 60;
                                if(minute < 60){
                                    content = [content stringByAppendingFormat:@"%ld分钟前", minute];
                                }else{
                                    long hour = minute / 60;
                                    if(hour < 24){
                                        content = [content stringByAppendingFormat:@"%ld小时前", hour];
                                    }else{
                                        long day = hour / 24;
                                        hour = hour - day *24;
                                        if(hour >0){
                                            content = [content stringByAppendingFormat:@"%ld天%ld小时前", day, hour];
                                        }else{
                                            content = [content stringByAppendingFormat:@"%ld天前", day];
                                        }
                                    }
                                }
                            }
                            content = [content stringByAppendingString:@"\n"];
                        }
                        
                        NSString* dialogString = [NSString stringWithString:content];
                        if([dic objectForKey:@"parkinglot_coupon_desc"] && [[dic objectForKey:@"parkinglot_coupon_desc"] length] > 0){
                            dialogString = [dialogString stringByAppendingFormat:@"\n%@", [dic objectForKey:@"parkinglot_coupon_desc"]];
                        }
                        AlertView* alertView = nil;
                        if(![[dic objectForKey: @"check"] boolValue]){
                            alertView = [[AlertView alloc] initWithTitle:@"抵扣券" message:dialogString cancelButtonTitle:@"取消" otherButtonTitles:nil];
                            alertView.completion = ^(BOOL cancelled, NSInteger index){
                                scanner.viewController.uiLabel.text = @"初始化";
                                scanner.resText = @"";
                            };
                        }else{
                            alertView = [[AlertView alloc] initWithTitle:@"抵扣券" message:dialogString cancelButtonTitle:@"取消" otherButtonTitles:@[@"使用"]];
                            alertView.completion = ^(BOOL cancelled, NSInteger buttonIndex){
                                if(!cancelled){
                                    NSString* url = [NSString stringWithFormat:@"%@/parking/parkinglotcouponusers/%@/parkinglot/%@/code/%@/check", host, parkinglotcouponuserPk, parkinglotId, code];
                                    HttpManager *manager = [HttpManager sharedClient];
                                    manager.responseSerializer = [AFJSONResponseSerializer serializer];
                                    [manager POST:url parameters:nil success:^(AFHTTPRequestOperation *operation, id responseObject) {
                                        scanner.viewController.uiLabel.text = content;
                                        scanner.resText = @"";
                                    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                        if(operation.response != nil && operation.response.statusCode == 404){
                                            AlertView *alertView = [self showAlertDialog:@"该抵扣券非本停车场抵扣券"];
                                            alertView.completion = ^(BOOL cancelled, NSInteger index){
                                                scanner.viewController.uiLabel.text = @"初始化";
                                                scanner.resText = @"";
                                            };
                                            [alertView show];
                                        }else{
                                            NSString *string = @"发生错误：";
                                            string = [string stringByAppendingFormat: @"%ld，请重新打开扫码", (long)error.code];
                                            
                                            scanner.viewController.uiLabel.text = string;
                                        }
                                        scanner.resText = @"";
                                    }];
                                }else{
                                    scanner.viewController.uiLabel.text = @"初始化";
                                    scanner.resText = @"";
                                }
                            };
                        }
                        
                        [alertView show];

//                        scanner.viewController.uiLabel.text = content;
                        
                    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                        if(operation.response != nil && operation.response.statusCode == 404){
                            AlertView *alertView = [self showAlertDialog:@"该抵扣券非本停车场抵扣券"];
                            alertView.completion = ^(BOOL cancelled, NSInteger index){
                                scanner.viewController.uiLabel.text = @"初始化";
                                scanner.resText = @"";
                            };

                        }else{
                            NSString *string = @"发生错误：";
                            string = [string stringByAppendingFormat: @"%ld，请重新打开扫码", (long)error.code];
                            
                            scanner.viewController.uiLabel.text = string;
                        }
                        scanner.resText = @"";
                    }];
                }else{
                    AlertView *alertView = [self showAlertDialog:@"二维码不可用"];
                    alertView.completion = ^(BOOL cancelled, NSInteger index){
                        scanner.viewController.uiLabel.text = @"初始化";
                        scanner.resText = @"";
                    };

                    [alertView show];
                }
            }else{
                AlertView *alertView = [self showAlertDialog:@"二维码不可用"];
                alertView.completion = ^(BOOL cancelled, NSInteger index){
                    scanner.viewController.uiLabel.text = @"初始化";
                    scanner.resText = @"";
                };
                [alertView show];
            }

        }else if([self.action isEqualToString:@"decode"]){
            NSNumber* cancelledNumber = [NSNumber numberWithInt:(cancelled?1:0)];
            
            NSMutableDictionary* resultDict = [[NSMutableDictionary alloc] init];
            [resultDict setObject:scannedText     forKey:@"text"];
            [resultDict setObject:format          forKey:@"format"];
            [resultDict setObject:cancelledNumber forKey:@"cancelled"];
            
            CDVPluginResult* result = [CDVPluginResult
                                       resultWithStatus: CDVCommandStatus_OK
                                       messageAsDictionary: resultDict
                                       ];
            [self.commandDelegate sendPluginResult:result callbackId:callback];
        }
    }else{
        CDVPluginResult* result = [CDVPluginResult
                                   resultWithStatus: CDVCommandStatus_ERROR
                                   messageAsDictionary: nil
                                   ];
        [self.commandDelegate sendPluginResult:result callbackId:callback];

    }
}

- (AlertView*)showAlertDialog:(NSString*)message {
    AlertView *alertView = [[AlertView alloc] initWithTitle:@"验证抵扣券" message:message cancelButtonTitle:@"确定" otherButtonTitles:nil];
    return alertView;
}

//--------------------------------------------------------------------------
- (void)returnError:(NSString*)message callback:(NSString*)callback {
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_ERROR
                               messageAsString: message
                               ];
    
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@implementation CDVbcsProcessor

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize alternateXib         = _alternateXib;
@synthesize is1D                 = _is1D;
@synthesize is2D                 = _is2D;
@synthesize capturing            = _capturing;
@synthesize resText              = _resText;
@synthesize host                 = _host;
@synthesize parkinglotId         = _parkinglotId;
@synthesize isDecode             = _isDecode;

SystemSoundID _soundFileObject;

//--------------------------------------------------------------------------
- (id)initWithPlugin:(CDVBarcodeScanner*)plugin
            callback:(NSString*)callback
                host:(NSString*)host
        parkinglotId:(NSString*)parkinglotId
parentViewController:(UIViewController*)parentViewController
  alterateOverlayXib:(NSString *)alternateXib
            isDecode:(BOOL)isDecode{
    self = [super init];
    if (!self) return self;
    
    self.plugin               = plugin;
    self.callback             = callback;
    self.host                 = host;
    self.parkinglotId         = parkinglotId;
    self.parentViewController = parentViewController;
    self.alternateXib         = alternateXib;
    self.isDecode             = isDecode;
    
    self.is1D      = YES;
    self.is2D      = YES;
    self.capturing = NO;
    self.resText = @"";
    
    CFURLRef soundFileURLRef  = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("CDVBarcodeScanner.bundle/beep"), CFSTR ("caf"), NULL);
    AudioServicesCreateSystemSoundID(soundFileURLRef, &_soundFileObject);
    
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.host = nil;
    self.parkinglotId = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.alternateXib = nil;
    
    self.capturing = NO;
    self.resText = @"";
    
    AudioServicesRemoveSystemSoundCompletion(_soundFileObject);
    AudioServicesDisposeSystemSoundID(_soundFileObject);
    
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)scanBarcode {
    
//    self.captureSession = nil;
//    self.previewLayer = nil;
    NSString* errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        [self barcodeScanFailed:errorMessage];
        return;
    }
    
    self.viewController = [[CDVbcsViewController alloc] initWithProcessor: self alternateOverlay:self.alternateXib];
    // here we set the orientation delegate to the MainViewController of the app (orientation controlled in the Project Settings)
    self.viewController.orientationDelegate = self.plugin.viewController;
    
    // delayed [self openDialog];
    [self performSelector:@selector(openDialog) withObject:nil afterDelay:1];
}

//--------------------------------------------------------------------------
- (void)openDialog {
    [self.parentViewController
     presentViewController:self.viewController
     animated:YES completion:nil
     ];
}

//--------------------------------------------------------------------------
- (void)barcodeScanDone {
    self.capturing = NO;
    [self.captureSession stopRunning];
    [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
    
    // viewcontroller holding onto a reference to us, release them so they
    // will release us
    self.viewController = nil;
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format {
    dispatch_sync(dispatch_get_main_queue(), ^{
    	if(self.isDecode){
            AudioServicesPlaySystemSound(_soundFileObject);
        	[self barcodeScanDone];
    	}
    	if (![self.resText isEqualToString:text]) {
            AudioServicesPlaySystemSound(_soundFileObject);
        	self.resText = text;
        	[self.plugin returnSuccess:text scanner:self host:self.host parkinglotId:self.parkinglotId format:format cancelled:FALSE flipped:FALSE callback:self.callback];
    	}
        
    });
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    [self barcodeScanDone];
    [self.plugin returnError:message callback:self.callback];
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    [self barcodeScanDone];
    [self.plugin returnSuccess:@"" scanner:self host:self.host parkinglotId:self.parkinglotId format:@"" cancelled:TRUE flipped:self.isFlipped callback:self.callback];
    if (self.isFlipped) {
        self.isFlipped = NO;
    }
}


- (void)flipCamera
{
    self.isFlipped = YES;
    self.isFrontCamera = !self.isFrontCamera;
    [self performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
    [self performSelector:@selector(scanBarcode) withObject:nil afterDelay:0.1];
}

//--------------------------------------------------------------------------
- (NSString*)setUpCaptureSession {
    NSError* error = nil;
    
    AVCaptureSession* captureSession = [[AVCaptureSession alloc] init];
    self.captureSession = captureSession;
    
    AVCaptureDevice* __block device = nil;
    if (self.isFrontCamera) {
        
        NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        [devices enumerateObjectsUsingBlock:^(AVCaptureDevice *obj, NSUInteger idx, BOOL *stop) {
            if (obj.position == AVCaptureDevicePositionFront) {
                device = obj;
            }
        }];
    } else {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (!device) return @"没有找到拍照设备";
        
    }
    
    
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) return @"请在设置中允许相机";
    
    AVCaptureVideoDataOutput* output = [[AVCaptureVideoDataOutput alloc] init];
    if (!output) return @"unable to obtain video capture output";
    
    NSDictionary* videoOutputSettings = [NSDictionary
                                         dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                         forKey:(id)kCVPixelBufferPixelFormatTypeKey
                                         ];
    
    output.alwaysDiscardsLateVideoFrames = YES;
    output.videoSettings = videoOutputSettings;
    
    [output setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];
    
    if (![captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        return @"unable to preset medium quality video capture";
    }
    
    captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    
    if ([captureSession canAddInput:input]) {
        [captureSession addInput:input];
    }
    else {
        return @"unable to add video capture device input to session";
    }
    
    if ([captureSession canAddOutput:output]) {
        [captureSession addOutput:output];
    }
    else {
        return @"unable to add video capture output to session";
    }
    
    // setup capture preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    
    // run on next event loop pass [captureSession startRunning]
    [captureSession performSelector:@selector(startRunning) withObject:nil afterDelay:0];
    
    return nil;
}

//--------------------------------------------------------------------------
// this method gets sent the captured frames
//--------------------------------------------------------------------------
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection {
    
    if (!self.capturing) return;
    
#if USE_SHUTTER
    if (!self.viewController.shutterPressed) return;
    self.viewController.shutterPressed = NO;
    
    UIView* flashView = [[UIView alloc] initWithFrame:self.viewController.view.frame];
    [flashView setBackgroundColor:[UIColor whiteColor]];
    [self.viewController.view.window addSubview:flashView];
    
    [UIView
     animateWithDuration:.4f
     animations:^{
         [flashView setAlpha:0.f];
     }
     completion:^(BOOL finished){
         [flashView removeFromSuperview];
     }
     ];
    
    //         [self dumpImage: [[self getImageFromSample:sampleBuffer] autorelease]];
#endif
    
    
    using namespace zxing;
    
    // LuminanceSource is pretty dumb; we have to give it a pointer to
    // a byte array, but then can't get it back out again.  We need to
    // get it back to free it.  Saving it in imageBytes.
    uint8_t* imageBytes;
    
    //        NSTimeInterval timeStart = [NSDate timeIntervalSinceReferenceDate];
    
    try {
        DecodeHints decodeHints;
        decodeHints.addFormat(BarcodeFormat_QR_CODE);
        decodeHints.addFormat(BarcodeFormat_DATA_MATRIX);
        decodeHints.addFormat(BarcodeFormat_UPC_E);
        decodeHints.addFormat(BarcodeFormat_UPC_A);
        decodeHints.addFormat(BarcodeFormat_EAN_8);
        decodeHints.addFormat(BarcodeFormat_EAN_13);
        decodeHints.addFormat(BarcodeFormat_CODE_128);
        decodeHints.addFormat(BarcodeFormat_CODE_39);
        decodeHints.addFormat(BarcodeFormat_ITF);
        
        // here's the meat of the decode process
        Ref<LuminanceSource>   luminanceSource   ([self getLuminanceSourceFromSample: sampleBuffer imageBytes:&imageBytes]);
        //            [self dumpImage: [[self getImageFromLuminanceSource:luminanceSource] autorelease]];
        Ref<Binarizer>         binarizer         (new HybridBinarizer(luminanceSource));
        Ref<BinaryBitmap>      bitmap            (new BinaryBitmap(binarizer));
        Ref<MultiFormatReader> reader            (new MultiFormatReader());
        Ref<Result>            result            (reader->decode(bitmap, decodeHints));
        Ref<String>            resultText        (result->getText());
        BarcodeFormat          formatVal =       result->getBarcodeFormat();
        NSString*              format    =       [self formatStringFrom:formatVal];
        
        
        const char* cString      = resultText->getText().c_str();
        NSString*   resultString = [[NSString alloc] initWithCString:cString encoding:NSUTF8StringEncoding];
        
        [self barcodeScanSucceeded:resultString format:format];
        
    }
    catch (zxing::ReaderException &rex) {
        //            NSString *message = [[[NSString alloc] initWithCString:rex.what() encoding:NSUTF8StringEncoding] autorelease];
        //            NSLog(@"decoding: ReaderException: %@", message);
    }
    catch (zxing::IllegalArgumentException &iex) {
        //            NSString *message = [[[NSString alloc] initWithCString:iex.what() encoding:NSUTF8StringEncoding] autorelease];
        //            NSLog(@"decoding: IllegalArgumentException: %@", message);
    }
    catch (...) {
        //            NSLog(@"decoding: unknown exception");
        //            [self barcodeScanFailed:@"unknown exception decoding barcode"];
    }
    
    //        NSTimeInterval timeElapsed  = [NSDate timeIntervalSinceReferenceDate] - timeStart;
    //        NSLog(@"decoding completed in %dms", (int) (timeElapsed * 1000));
    
    // free the buffer behind the LuminanceSource
    if (imageBytes) {
        free(imageBytes);
    }
}

//--------------------------------------------------------------------------
// convert barcode format to string
//--------------------------------------------------------------------------
- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format {
    if (format == zxing::BarcodeFormat_QR_CODE)      return @"QR_CODE";
    if (format == zxing::BarcodeFormat_DATA_MATRIX)  return @"DATA_MATRIX";
    if (format == zxing::BarcodeFormat_UPC_E)        return @"UPC_E";
    if (format == zxing::BarcodeFormat_UPC_A)        return @"UPC_A";
    if (format == zxing::BarcodeFormat_EAN_8)        return @"EAN_8";
    if (format == zxing::BarcodeFormat_EAN_13)       return @"EAN_13";
    if (format == zxing::BarcodeFormat_CODE_128)     return @"CODE_128";
    if (format == zxing::BarcodeFormat_CODE_39)      return @"CODE_39";
    if (format == zxing::BarcodeFormat_ITF)          return @"ITF";
    return @"???";
}

//--------------------------------------------------------------------------
// convert capture's sample buffer (scanned picture) into the thing that
// zxing needs.
//--------------------------------------------------------------------------
- (zxing::Ref<zxing::LuminanceSource>) getLuminanceSourceFromSample:(CMSampleBufferRef)sampleBuffer imageBytes:(uint8_t**)ptr {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    size_t   bytesPerRow =            CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t   width       =            CVPixelBufferGetWidth(imageBuffer);
    size_t   height      =            CVPixelBufferGetHeight(imageBuffer);
    uint8_t* baseAddress = (uint8_t*) CVPixelBufferGetBaseAddress(imageBuffer);
    
    // only going to get 90% of the min(width,height) of the captured image
    size_t    greyWidth  = 9 * MIN(width, height) / 10;
    uint8_t*  greyData   = (uint8_t*) malloc(greyWidth * greyWidth);
    
    // remember this pointer so we can free it later
    *ptr = greyData;
    
    if (!greyData) {
        CVPixelBufferUnlockBaseAddress(imageBuffer,0);
        throw new zxing::ReaderException("out of memory");
    }
    
    size_t offsetX = (width  - greyWidth) / 2;
    size_t offsetY = (height - greyWidth) / 2;
    
    // pixel-by-pixel ...
    for (size_t i=0; i<greyWidth; i++) {
        for (size_t j=0; j<greyWidth; j++) {
            // i,j are the coordinates from the sample buffer
            // ni, nj are the coordinates in the LuminanceSource
            // in this case, there's a rotation taking place
            size_t ni = greyWidth-j;
            size_t nj = i;
            
            size_t baseOffset = (j+offsetY)*bytesPerRow + (i + offsetX)*4;
            
            // convert from color to grayscale
            // http://en.wikipedia.org/wiki/Grayscale#Converting_color_to_grayscale
            size_t value = 0.11 * baseAddress[baseOffset] +
            0.59 * baseAddress[baseOffset + 1] +
            0.30 * baseAddress[baseOffset + 2];
            
            greyData[nj*greyWidth + ni] = value;
        }
    }
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    using namespace zxing;
    
    Ref<LuminanceSource> luminanceSource (
                                          new GreyscaleLuminanceSource(greyData, (int)greyWidth, (int)greyWidth, 0, 0, (int)greyWidth, (int)greyWidth)
                                          );
    
    return luminanceSource;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (UIImage*) getImageFromLuminanceSource:(zxing::LuminanceSource*)luminanceSource  {
    unsigned char* bytes = luminanceSource->getMatrix();
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(
                                                 bytes,
                                                 luminanceSource->getWidth(), luminanceSource->getHeight(), 8, luminanceSource->getWidth(),
                                                 colorSpace,
                                                 kCGImageAlphaNone
                                                 );
    
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage*   image   = [[UIImage alloc] initWithCGImage:cgImage];
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);
    free(bytes);
    
    return image;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width       = CVPixelBufferGetWidth(imageBuffer);
    size_t height      = CVPixelBufferGetHeight(imageBuffer);
    
    uint8_t* baseAddress    = (uint8_t*) CVPixelBufferGetBaseAddress(imageBuffer);
    int      length         = (int)(height * bytesPerRow);
    uint8_t* newBaseAddress = (uint8_t*) malloc(length);
    memcpy(newBaseAddress, baseAddress, length);
    baseAddress = newBaseAddress;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
                                                 baseAddress,
                                                 width, height, 8, bytesPerRow,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst
                                                 );
    
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage*   image   = [[UIImage alloc] initWithCGImage:cgImage];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);
    
    free(baseAddress);
    
    return image;
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (void)dumpImage:(UIImage*)image {
    NSLog(@"writing image to library: %dx%d", (int)image.size.width, (int)image.size.height);
    ALAssetsLibrary* assetsLibrary = [[ALAssetsLibrary alloc] init];
    [assetsLibrary
     writeImageToSavedPhotosAlbum:image.CGImage
     orientation:ALAssetOrientationUp
     completionBlock:^(NSURL* assetURL, NSError* error){
         if (error) NSLog(@"   error writing image to library");
         else       NSLog(@"   wrote image to library %@", assetURL);
     }
     ];
}

@end

//------------------------------------------------------------------------------
// qr encoder processor
//------------------------------------------------------------------------------
@implementation CDVqrProcessor
@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize stringToEncode       = _stringToEncode;
@synthesize size                 = _size;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode{
    self = [super init];
    if (!self) return self;
    
    self.plugin          = plugin;
    self.callback        = callback;
    self.stringToEncode  = stringToEncode;
    self.size            = 300;
    
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.stringToEncode = nil;
    
    [super dealloc];
}
//--------------------------------------------------------------------------
- (void)generateImage{
    /* setup qr filter */
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    
    /* set filter's input message
     * the encoding string has to be convert to a UTF-8 encoded NSData object */
    [filter setValue:[self.stringToEncode dataUsingEncoding:NSUTF8StringEncoding]
              forKey:@"inputMessage"];
    
    /* on ios >= 7.0  set low image error correction level */
    if (floor(NSFoundationVersionNumber) >= NSFoundationVersionNumber_iOS_7_0)
        [filter setValue:@"L" forKey:@"inputCorrectionLevel"];
    
    /* prepare cgImage */
    CIImage *outputImage = [filter outputImage];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:outputImage
                                       fromRect:[outputImage extent]];
    
    /* returned qr code image */
    UIImage *qrImage = [UIImage imageWithCGImage:cgImage
                                           scale:1.
                                     orientation:UIImageOrientationUp];
    /* resize generated image */
    CGFloat width = _size;
    CGFloat height = _size;
    
    UIGraphicsBeginImageContext(CGSizeMake(width, height));
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    [qrImage drawInRect:CGRectMake(0, 0, width, height)];
    qrImage = UIGraphicsGetImageFromCurrentImageContext();
    
    /* clean up */
    UIGraphicsEndImageContext();
    CGImageRelease(cgImage);
    
    /* save image to file */
    NSString* filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmpqrcode.jpeg"];
    [UIImageJPEGRepresentation(qrImage, 1.0) writeToFile:filePath atomically:YES];
    
    /* return file path back to cordova */
    [self.plugin returnImage:filePath format:@"QR_CODE" callback: self.callback];
}
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@implementation CDVbcsViewController
@synthesize processor      = _processor;
@synthesize shutterPressed = _shutterPressed;
@synthesize alternateXib   = _alternateXib;
@synthesize overlayView    = _overlayView;
@synthesize uiLabel        = _uiLabel;


//--------------------------------------------------------------------------
- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;
    
    self.processor = processor;
    self.shutterPressed = NO;
    self.alternateXib = alternateXib;
    self.overlayView = nil;
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.view = nil;
//    self.processor = nil;
    self.shutterPressed = NO;
    self.alternateXib = nil;
    self.overlayView = nil;
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame: self.processor.parentViewController.view.frame];
    
    // setup capture preview layer
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    if ([previewLayer.connection isVideoOrientationSupported]) {
        [previewLayer.connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    }
    
    [self.view.layer insertSublayer:previewLayer below:[[self.view.layer sublayers] objectAtIndex:0]];
    
    [self.view addSubview:[self buildOverlayView]];
}

//--------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {
    
    // set video orientation to what the camera sees
    self.processor.previewLayer.connection.videoOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    
    // this fixes the bug when the statusbar is landscape, and the preview layer
    // starts up in portrait (not filling the whole view)
    self.processor.previewLayer.frame = self.view.bounds;
}

//--------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated {
    [self startCapturing];
    
    [super viewDidAppear:animated];
}

//--------------------------------------------------------------------------
- (void)startCapturing {
    self.processor.capturing = YES;
}

//--------------------------------------------------------------------------
- (void)shutterButtonPressed {
    self.shutterPressed = YES;
}

//--------------------------------------------------------------------------
- (IBAction)cancelButtonPressed:(id)sender {
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
}

- (void)flipCameraButtonPressed:(id)sender
{
    [self.processor performSelector:@selector(flipCamera) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (UIView *)buildOverlayViewFromXib
{
    [[NSBundle mainBundle] loadNibNamed:self.alternateXib owner:self options:NULL];
    
    if ( self.overlayView == nil )
    {
        NSLog(@"%@", @"An error occurred loading the overlay xib.  It appears that the overlayView outlet is not set.");
        return nil;
    }
    
    return self.overlayView;
}

//--------------------------------------------------------------------------
- (UIView*)buildOverlayView {
    
    if ( nil != self.alternateXib )
    {
        return [self buildOverlayViewFromXib];
    }
    CGRect bounds = self.view.bounds;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    
    UIView* overlayView = [[UIView alloc] initWithFrame:bounds];
    overlayView.autoresizesSubviews = YES;
    overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlayView.opaque              = NO;
//    
//    UIToolbar* toolbar = [[[UIToolbar alloc] init] autorelease];
//    toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
//    
//    id cancelButton = [[[UIBarButtonItem alloc] autorelease]
//                       initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
//                       target:(id)self
//                       action:@selector(cancelButtonPressed:)
//                       ];
//    
//    
//    id flexSpace = [[[UIBarButtonItem alloc] autorelease]
//                    initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
//                    target:nil
//                    action:nil
//                    ];
//    
//    id flipCamera = [[[UIBarButtonItem alloc] autorelease]
//                       initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
//                       target:(id)self
//                       action:@selector(flipCameraButtonPressed:)
//                       ];
//
//    
//#if USE_SHUTTER
//    id shutterButton = [[UIBarButtonItem alloc]
//                        initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
//                        target:(id)self
//                        action:@selector(shutterButtonPressed)
//                        ];
//    
//    toolbar.items = [NSArray arrayWithObjects:flexSpace,cancelButton,flexSpace, flipCamera ,shutterButton,nil];
//#else
//    toolbar.items = [NSArray arrayWithObjects:flexSpace,cancelButton,flexSpace, flipCamera,nil];
//#endif
//    bounds = overlayView.bounds;
//    
//    [toolbar sizeToFit];
//    CGFloat toolbarHeight  = [toolbar frame].size.height;
    CGFloat rootViewHeight = CGRectGetHeight(bounds);
    CGFloat rootViewWidth  = CGRectGetWidth(bounds);
//    CGRect  rectArea       = CGRectMake(0, rootViewHeight - toolbarHeight, rootViewWidth, toolbarHeight);
//    [toolbar setFrame:rectArea];
    
//    [overlayView addSubview: toolbar];
    
    UIImage* reticleImage = [self buildReticleImage];
    UIView* reticleView = [[UIImageView alloc] initWithImage: reticleImage];
    CGFloat minAxis = MIN(rootViewHeight, rootViewWidth);
    
    CGRect rectArea = CGRectMake(
                          0.5 * (rootViewWidth  - minAxis),
                          0.5 * (rootViewHeight - minAxis),
                          minAxis,
                          minAxis
                          );
    
    [reticleView setFrame:rectArea];
    
    reticleView.opaque           = NO;
    reticleView.contentMode      = UIViewContentModeScaleAspectFit;
    reticleView.autoresizingMask = 0
    | UIViewAutoresizingFlexibleLeftMargin
    | UIViewAutoresizingFlexibleRightMargin
    | UIViewAutoresizingFlexibleTopMargin
    | UIViewAutoresizingFlexibleBottomMargin
    ;
    
    [overlayView addSubview: reticleView];
    
    self.uiLabel = [[[UILabel alloc] initWithFrame: CGRectMake(30, 80, rootViewWidth - 2 * 30, 120)] autorelease];
    self.uiLabel.textAlignment = NSTextAlignmentCenter;
    self.uiLabel.backgroundColor = [UIColor colorWithRed: 0 green: 0 blue: 0 alpha:0.6];
    self.uiLabel.textColor = [UIColor whiteColor];
    self.uiLabel.numberOfLines = 0;
    
    self.uiLabel.text = @"请将二维码置于取景框内扫描。";
    
    [overlayView addSubview: self.uiLabel];
    
    UIButton* button = [[[UIButton alloc] initWithFrame: CGRectMake(10, 20, 40, 30)] autorelease];
    [button setTitle:@"取消" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:255 alpha:255] forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0];
    
    [button addTarget:(id)self action:@selector(cancelButtonPressed:) forControlEvents:UIControlEventTouchDown];
    [overlayView addSubview:button];
    
    return overlayView;
}

//--------------------------------------------------------------------------

#define RETICLE_SIZE    500.0f
#define RETICLE_WIDTH    5.0f
#define RETICLE_OFFSET   120.0f
#define RETICLE_ALPHA     0.4f

//-------------------------------------------------------------------------
// builds the green box and red line
//-------------------------------------------------------------------------
- (UIImage*)buildReticleImage {
    UIImage* result;
    UIGraphicsBeginImageContext(CGSizeMake(RETICLE_SIZE, RETICLE_SIZE));
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    if (self.processor.is1D) {
        // UIColor* color = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:RETICLE_ALPHA];
        // CGContextSetStrokeColorWithColor(context, color.CGColor);
        // CGContextSetLineWidth(context, RETICLE_WIDTH);
        // CGContextBeginPath(context);
        // CGFloat lineOffset = RETICLE_OFFSET+(0.5*RETICLE_WIDTH);
        // CGContextMoveToPoint(context, lineOffset, RETICLE_SIZE/2);
        // CGContextAddLineToPoint(context, RETICLE_SIZE-lineOffset, 0.5*RETICLE_SIZE);
        // CGContextStrokePath(context);
    }
    
    if (self.processor.is2D) {
        UIColor* color = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH);
        
        CGContextStrokeRect(context,
                            CGRectMake(
                                       RETICLE_OFFSET,
                                       RETICLE_OFFSET,
                                       RETICLE_SIZE-2*RETICLE_OFFSET,
                                       RETICLE_SIZE-2*RETICLE_OFFSET
                                       )
                            );
    }
    
    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark CDVBarcodeScannerOrientationDelegate

- (BOOL)shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }
    
    return YES;
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration
{
    [CATransaction begin];
    
    self.processor.previewLayer.connection.videoOrientation = orientation;
    [self.processor.previewLayer layoutSublayers];
    self.processor.previewLayer.frame = self.view.bounds;
    
    [CATransaction commit];
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
}

@end
