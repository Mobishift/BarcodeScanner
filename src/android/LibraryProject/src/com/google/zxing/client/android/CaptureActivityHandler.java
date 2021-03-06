/*
 * Copyright (C) 2008 ZXing authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.google.zxing.client.android;

import android.content.ActivityNotFoundException;
import android.content.DialogInterface;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.provider.Browser;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.Result;
import com.google.zxing.client.android.camera.CameraManager;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.widget.Toast;

import com.google.zxing.FakeR;
import com.mobishift.http.CouponRequest;
import com.phonegap.plugins.barcodescanner.BarcodeScanner;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Collection;
import java.util.Date;

import retrofit.Callback;
import retrofit.RetrofitError;
import retrofit.client.Response;

/**
 * This class handles all the messaging which comprises the state machine for capture.
 *
 * @author dswitkin@google.com (Daniel Switkin)
 */
public final class CaptureActivityHandler extends Handler {

  private static final String TAG = CaptureActivityHandler.class.getSimpleName();
  private final CaptureActivity activity;
  private final DecodeThread decodeThread;
  private State state;
  private final CameraManager cameraManager;
  private String handleText = "";

  private enum State {
    PREVIEW,
    SUCCESS,
    DONE
  }

  private static FakeR fakeR;

  CaptureActivityHandler(CaptureActivity activity,
                         Collection<BarcodeFormat> decodeFormats,
                         String characterSet,
                         CameraManager cameraManager) {
  fakeR = new FakeR(activity);
    this.activity = activity;
    decodeThread = new DecodeThread(activity, decodeFormats, characterSet,
        new ViewfinderResultPointCallback(activity.getViewfinderView()));
    decodeThread.start();
    state = State.SUCCESS;

    // Start ourselves capturing previews and decoding.
    this.cameraManager = cameraManager;
    cameraManager.startPreview();
    restartPreviewAndDecode();
  }

  @Override
  public void handleMessage(Message message) {
    if (message.what == fakeR.getId("id", "restart_preview")) {
        Log.d(TAG, "Got restart preview message");
        restartPreviewAndDecode();
    } else if (message.what == fakeR.getId("id", "decode_succeeded")) {
        Log.d(TAG, "Got decode succeeded message");
        state = State.SUCCESS;
        Bundle bundle = message.getData();
        Bitmap barcode = bundle == null ? null :
            (Bitmap) bundle.getParcelable(DecodeThread.BARCODE_BITMAP);
        activity.handleDecode((Result) message.obj, barcode);
    } else if (message.what == fakeR.getId("id", "decode_failed")) {
        // We're decoding as fast as possible, so when one decode fails, start another.
        state = State.PREVIEW;
        cameraManager.requestPreviewFrame(decodeThread.getHandler(), fakeR.getId("id", "decode"));
    } else if (message.what == fakeR.getId("id", "return_scan_result")) {
        Log.d(TAG, "Got return scan result message");
//        activity.setResult(Activity.RESULT_OK, (Intent) message.obj);
        Intent intent = (Intent) message.obj;
        final String url = intent.getStringExtra("SCAN_RESULT");
        final DialogInterface.OnDismissListener dismissListener = new DialogInterface.OnDismissListener() {
            @Override
            public void onDismiss(DialogInterface dialog) {
                activity.setCouponText("初始化");
                restartPreviewAndDecode();
            }
        };
        if(activity.getRequestCode() == BarcodeScanner.DECODE_CODE){
            Log.d(TAG, "Got return scan result message");
            activity.setResult(Activity.RESULT_OK, (Intent) message.obj);
            activity.finish();
        }else if(activity.getRequestCode() == BarcodeScanner.REQUEST_CODE){
            activity.setCouponText("请求中...");
            final CouponRequest couponRequest = CouponRequest.getCouponRequest();
            boolean isCoupon = couponRequest.get(url, new CouponRequest.CouponReqeustCallback() {
                @Override
                public void success(CouponRequest.Coupon coupon) {
                    activity.showCouponDialog(coupon.parkinglot_coupon_name,
                            coupon.check,
                            coupon.getUsedAt(),
                            coupon.origin_price,
                            coupon.parkinglot_coupon_desc,
                            new DialogInterface.OnClickListener() {
                                @Override
                                public void onClick(DialogInterface dialog, int which) {
                                    dialog.dismiss();
                                    couponRequest.checkCode(url, new CouponRequest.CouponReqeustCallback() {
                                        @Override
                                        public void success(CouponRequest.Coupon coupon) {
                                            activity.setCouponView(coupon.parkinglot_coupon_name,
                                                    coupon.check,
                                                    coupon.getUsedAt(),
                                                    coupon.origin_price);
                                            restartPreviewAndDecode();
                                        }

                                        @Override
                                        public void failure(String message) {
                                            Toast.makeText(activity, message, Toast.LENGTH_SHORT).show();
                                            activity.setCouponText(message);
                                            restartPreviewAndDecode();
                                        }
                                    });
                                }
                            },
                            dismissListener);
                }

                @Override
                public void failure(String message) {
                    activity.showDialog(message, dismissListener);
                }
            });
            if(!isCoupon){
                activity.showDialog("二维码不可用", dismissListener);
            }
        }else{
            restartPreviewAndDecode();
        }
//        activity.finish();
    } else if (message.what == fakeR.getId("id", "launch_product_query")) {
        Log.d(TAG, "Got product query message");
        String url = (String) message.obj;
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_WHEN_TASK_RESET);
        intent.setData(Uri.parse(url));
        ResolveInfo resolveInfo =
            activity.getPackageManager().resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY);
        String browserPackageName = null;
        if (resolveInfo.activityInfo != null) {
          browserPackageName = resolveInfo.activityInfo.packageName;
          Log.d(TAG, "Using browser in package " + browserPackageName);
        }
        // Needed for default Android browser only apparently
        if ("com.android.browser".equals(browserPackageName)) {
          intent.setPackage(browserPackageName);
          intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
          intent.putExtra(Browser.EXTRA_APPLICATION_ID, browserPackageName);
        }
        try {
          activity.startActivity(intent);
        } catch (ActivityNotFoundException anfe) {
          Log.w(TAG, "Can't find anything to handle VIEW of URI " + url);
        }
    }
  }

  public void quitSynchronously() {
    state = State.DONE;
    cameraManager.stopPreview();
    Message quit = Message.obtain(decodeThread.getHandler(), fakeR.getId("id", "quit"));
    quit.sendToTarget();
    try {
      // Wait at most half a second; should be enough time, and onPause() will timeout quickly
      decodeThread.join(500L);
    } catch (InterruptedException e) {
      // continue
    }

    // Be absolutely sure we don't send any queued up messages
    removeMessages(fakeR.getId("id", "decode_succeeded"));
    removeMessages(fakeR.getId("id", "decode_failed"));
  }

  private void restartPreviewAndDecode() {
    if (state == State.SUCCESS) {
      state = State.PREVIEW;
      cameraManager.requestPreviewFrame(decodeThread.getHandler(), fakeR.getId("id", "decode"));
      activity.drawViewfinder();
    }

  }

}
