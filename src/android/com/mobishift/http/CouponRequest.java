package com.mobishift.http;

import com.phonegap.plugins.barcodescanner.BarcodeScanner;
import com.squareup.okhttp.MediaType;
import com.squareup.okhttp.OkHttpClient;
import com.squareup.okhttp.Request;
import com.squareup.okhttp.RequestBody;
import com.squareup.okhttp.Response;
/**
 * Created by Gamma on 15/3/25.
 */
public class CouponRequest {
    public static final MediaType JSON = MediaType.parse("application/json; charset=utf-8");
    private static final String URL = "/parking/parkinglotcouponusers";

    private static CouponRequest couponRequest = null;

    private OkHttpClient client = new OkHttpClient();
    private String url;
    private String parkinglot;

    private CouponRequest(){
        url = BarcodeScanner.HOST_URL + URL;
        parkinglot = BarcodeScanner.PARKINGLOT;
    }

    public static CouponRequest getCouponRequest(){
        if(couponRequest == null){
            couponRequest = new CouponRequest();
        }
        return couponRequest;
    }

    public void post(String url){
        if(url.contains("parkinglotcouponuser=")){
            String[] strings = url.split("parkinglotcouponuser=")[1].split("__");
            if(strings.length == 2){
                String id = strings[0];
                String code = strings[1];
                String postUrl = url + "/" + id + "/code/" + code;
                RequestBody body = RequestBody.create(JSON, "{}");
                Request request = new Request.Builder().url(postUrl).post(body).build();
                Response response = client.newCall(request).execute();
            }
        }
    }
}
