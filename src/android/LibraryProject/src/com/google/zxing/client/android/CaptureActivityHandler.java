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
        String url = intent.getStringExtra("SCAN_RESULT");
        if(!handleText.equals(url)){
            handleText = url;
            activity.setCouponText("请求中...");
            CouponRequest couponRequest = CouponRequest.getCouponRequest();
            boolean isCoupon = couponRequest.get(url, new retrofit.Callback<CouponRequest.Coupon>() {
                @Override
                public void success(CouponRequest.Coupon coupon, Response response) {
                    if(coupon != null){
                        Date date = null;
                        if(coupon.check){
                            date = Calendar.getInstance().getTime();
                        }else{
                            if(coupon.used_at != null){
                                SimpleDateFormat simpleDateFormat =  new SimpleDateFormat("yyyy-MM-d'T'HH:mm:ss");
                                try{
                                    date = simpleDateFormat.parse(coupon.used_at);
                                }catch (ParseException ex){

                                }
                            }
                        }
                        activity.setCouponView(coupon.parkinglot_coupon_name, coupon.check, date, coupon.origin_price);
                    }else{
                        Toast.makeText(activity, "发生错误，请重新扫描", Toast.LENGTH_SHORT).show();
                    }
                    restartPreviewAndDecode();
                }

                @Override
                public void failure(RetrofitError retrofitError) {
                    switch (retrofitError.getKind()){
                        case NETWORK:
                            Toast.makeText(activity, "请检查网络链接", Toast.LENGTH_SHORT).show();
                            activity.setCouponText("请检查网络链接");
                            break;
                        case HTTP:
                            int status = retrofitError.getResponse().getStatus();
                            if(status == 404){
                                Toast.makeText(activity, "该优惠券非本停车场优惠券", Toast.LENGTH_SHORT).show();
                                activity.setCouponText("该优惠券非本停车场优惠券");
                            }else{
                                Toast.makeText(activity, "发生错误:" + status, Toast.LENGTH_SHORT).show();
                                activity.setCouponText("发生错误:" + status);
                            }
                            break;
                        case UNEXPECTED:
    //                        Log.d("UNEXPECTED", retrofitError.getUrl());
    //                        Log.d("UNEXPECTED", retrofitError.getResponse().getStatus() + "");
    //                        Log.d("UNEXPECTED", retrofitError.getResponse().getReason());
                            Toast.makeText(activity, "未知错误:" + retrofitError.getMessage() , Toast.LENGTH_SHORT).show();
                            activity.setCouponText("未知错误:" + retrofitError.getMessage());
                            break;
                    }
                    restartPreviewAndDecode();
                }
            });
            if(!isCoupon){
                Toast.makeText(activity, "二维码非法", Toast.LENGTH_SHORT).show();
                restartPreviewAndDecode();
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
