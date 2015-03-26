package com.mobishift.http;

import com.phonegap.plugins.barcodescanner.BarcodeScanner;

import retrofit.Callback;
import retrofit.RestAdapter;
import retrofit.http.POST;
import retrofit.http.Path;

/**
 * Created by Gamma on 15/3/25.
 */
public class CouponRequest {

    private static CouponRequest couponRequest = null;

    private String url;
    private String parkinglot;
    private RestAdapter restAdapter;
    private CouponService couponService;

    private CouponRequest(){
        url = BarcodeScanner.HOST_URL;
        parkinglot = BarcodeScanner.PARKINGLOT;
        restAdapter = new RestAdapter.Builder().setEndpoint(url).build();
        couponService = restAdapter.create(CouponService.class);
    }

    public static CouponRequest getCouponRequest(){
        if(couponRequest == null){
            couponRequest = new CouponRequest();
        }
        return couponRequest;
    }

    public boolean get(String urlString, Callback<Coupon> cb){
        boolean isValid = true;
        if(urlString.contains("parkinglotcouponuser=")){
            String[] strings = urlString.split("parkinglotcouponuser=")[1].split("__");
            if(strings.length == 2){
                String id = strings[0];
                String code = strings[1];
                couponService.getCoupon(id, parkinglot, code, cb);
            }else{
                isValid = false;
            }
        }else{
            isValid = false;
        }
        return isValid;
    }


    public interface CouponService{
        @POST("/parking/parkinglotcouponusers/{id}/parkinglot/{parkinglot}/code/{code}/check")
        void getCoupon(@Path("id") String id,@Path("parkinglot") String parkinglot, @Path("code") String code, Callback<Coupon> cb);
    }

    public final class Coupon{
        public String parkinglot;
        public boolean check;
        public String used_at;
        public double price;
        public double origin_price;
    }
}
