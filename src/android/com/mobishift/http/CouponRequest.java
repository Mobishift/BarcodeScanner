package com.mobishift.http;

import com.phonegap.plugins.barcodescanner.BarcodeScanner;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;

import retrofit.Callback;
import retrofit.RestAdapter;
import retrofit.RetrofitError;
import retrofit.client.Response;
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

    public boolean get(String urlString, final CouponReqeustCallback callback){
        boolean isValid = true;
        if(urlString.contains("parkinglotcouponuser=")){
            String[] strings = urlString.split("parkinglotcouponuser=")[1].split("__");
            if(strings.length == 2){
                String id = strings[0];
                String code = strings[1];
                couponService.getCoupon(id, parkinglot, code, new Callback<Coupon>() {
                    @Override
                    public void success(Coupon coupon, Response response) {
                        callback.success(coupon);
                    }

                    @Override
                    public void failure(RetrofitError retrofitError) {
                        String message = getFailureMessage(retrofitError);
                        callback.failure(message);
                    }
                });
            }else{
                isValid = false;
            }
        }else{
            isValid = false;
        }
        return isValid;
    }

    public boolean checkCode(String urlString, final CouponReqeustCallback callback){
        boolean isValid = true;
        if(urlString.contains("parkinglotcouponuser=")){
            String[] strings = urlString.split("parkinglotcouponuser=")[1].split("__");
            if(strings.length == 2){
                String id = strings[0];
                String code = strings[1];
                couponService.checkCoupon(id, parkinglot, code, new Callback<Coupon>() {
                    @Override
                    public void success(Coupon coupon, Response response) {
                        callback.success(coupon);
                    }

                    @Override
                    public void failure(RetrofitError retrofitError) {
                        String message = getFailureMessage(retrofitError);
                        callback.failure(message);
                    }
                });
            }else{
                isValid = false;
            }
        }else{
            isValid = false;
        }
        return isValid;
    }

    private String getFailureMessage(RetrofitError retrofitError){
        String message = "获取优惠券失败";
        switch (retrofitError.getKind()){
            case NETWORK:
                message = "请检查网络链接";
                break;
            case HTTP:
                int status = retrofitError.getResponse().getStatus();
                if(status == 404){
                    message = "该优惠券非本停车场优惠券";
                }else{
                    message = "发生错误:" + status;
                }
                break;
            case UNEXPECTED:
                message = "未知错误:" + retrofitError.getMessage();
                break;
        }
        return message;
    }



    public interface CouponService{
        @POST("/parking/parkinglotcouponusers/{id}/parkinglot/{parkinglot}/code/{code}/check")
        void checkCoupon(@Path("id") String id,@Path("parkinglot") String parkinglot, @Path("code") String code, Callback<Coupon> cb);
        @POST("/parking/parkinglotcouponusers/{id}/parkinglot/{parkinglot}/code/{code}/check?no_use=1")
        void getCoupon(@Path("id") String id,@Path("parkinglot") String parkinglot, @Path("code") String code, Callback<Coupon> cb);
    }

    public final class Coupon{
        public String parkinglot_coupon_name;
        public String parkinglot;
        public boolean check;
        public String used_at;
        public double price;
        public double origin_price;
        public String desc;

        public Date getUsedAt(){
            Date date = null;
            if(this.check){
                date = Calendar.getInstance().getTime();
            }else{
                if(this.used_at != null){
                    SimpleDateFormat simpleDateFormat =  new SimpleDateFormat("yyyy-MM-d'T'HH:mm:ss");
                    try{
                        date = simpleDateFormat.parse(this.used_at);
                    }catch (ParseException ex){

                    }
                }
            }
            return date;
        }
    }

    public interface CouponReqeustCallback {
        void success(Coupon coupon);
        void failure(String message);
    }
}
