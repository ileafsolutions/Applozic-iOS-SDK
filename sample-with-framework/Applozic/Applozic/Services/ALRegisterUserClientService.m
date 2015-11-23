//
//  ALRegisterUserClientService.m
//  ChatApp
//
//  Created by devashish on 18/09/2015.
//  Copyright (c) 2015 AppLogic. All rights reserved.
//

#define INVALID_APPLICATIONID = @"INVALID_APPLICATIONID"


#import "ALRegisterUserClientService.h"
#import "ALRequestHandler.h"
#import "ALResponseHandler.h"
#import "ALUtilityClass.h"
#import "ALRegistrationResponse.h"
#import "ALUserDefaultsHandler.h"
#import "ALMessageDBService.h"
#import "MQTTClient/MQTTSession.h"
#import "ALApplozicSettings.h"

@implementation ALRegisterUserClientService

static MQTTSession *session;

-(void) initWithCompletion:(ALUser *)user withCompletion:(void(^)(ALRegistrationResponse * response, NSError *error)) completion
{
    NSString * theUrlString = [NSString stringWithFormat:@"%@/rest/ws/register/client",KBASE_URL];
    [ALUserDefaultsHandler setApplicationKey: user.applicationId];
    [user setDeviceType:1];
    [user setPrefContactAPI:2];
    [user setEmailVerified:true];
    [user setDeviceType:4];
    [user setAppVersionCode: @"71"];
    [user setRegistrationId: [ALUserDefaultsHandler getApnDeviceToken]];
    
    //NSString * theParamString = [ALUtilityClass generateJsonStringFromDictionary:userInfo];
    NSError *error;
    NSData *postdata = [NSJSONSerialization dataWithJSONObject:user.dictionary options:0 error:&error];
    NSString *theParamString = [[NSString alloc]initWithData:postdata encoding:NSUTF8StringEncoding];
    
    NSMutableURLRequest * theRequest = [ALRequestHandler createPOSTRequestWithUrlString:theUrlString paramString:theParamString];
    
    [ALResponseHandler processRequest:theRequest andTag:@"CREATE ACCOUNT" WithCompletionHandler:^(id theJson, NSError *theError) {
        NSLog(@"server response received %@", theJson);
        
        NSString *statusStr = (NSString *)theJson;
        
        /*NSMutableDictionary *errorDetail = [NSMutableDictionary dictionary];
        
        if ([statusStr rangeOfString: @"<html"].location != NSNotFound) {
            //[errorDetail setValue:@"Failed to process from server" forKey:NSLocalizedDescriptionKey];
            theError = [NSError errorWithDomain:@"server" code:200 userInfo:errorDetail];
        }
        
        if ([statusStr rangeOfString: @"INVALID_APPLICATIONID"].location != NSNotFound) {
            //[errorDetail setValue:@"Invalid Application Id" forKey:NSLocalizedDescriptionKey];
            theError = [NSError errorWithDomain:@"server" code:200 userInfo:errorDetail];
        }*/
        
        if (theError) {
            
            completion(nil,theError);
            
            return ;
        }
        
        ALRegistrationResponse *response = [[ALRegistrationResponse alloc] initWithJSONString:statusStr];
        
        //Todo: figure out how to set country code
        //mobiComUserPreference.setCountryCode(user.getCountryCode());
        //mobiComUserPreference.setContactNumber(user.getContactNumber());

        [ALUserDefaultsHandler setUserId:user.userId];
        [ALUserDefaultsHandler setEmailVerified: user.emailVerified];
        [ALUserDefaultsHandler setDisplayName: user.displayName];
        [ALUserDefaultsHandler setEmailId:user.emailId];
        [ALUserDefaultsHandler setDeviceKeyString:response.deviceKey];
        [ALUserDefaultsHandler setUserKeyString:response.userKey];
        [ALUserDefaultsHandler setLastSyncTime:(NSNumber *)response.lastSyncTime];
        //[ALRegisterUserClientService connect];
        
        completion(response,nil);
    }];
    
}

-(void) updateApnDeviceTokenWithCompletion:(NSString *)apnDeviceToken withCompletion:(void(^)(ALRegistrationResponse * response, NSError *error)) completion
{
    [ALUserDefaultsHandler setApnDeviceToken:apnDeviceToken];
    if ([ALUserDefaultsHandler isLoggedIn])
    {
        //call server again
        ALUser *user = [[ALUser alloc] init];
        [user setApplicationId: [ALUserDefaultsHandler getApplicationKey]];
        [user setUserId:[ALUserDefaultsHandler getUserId]];
        [self initWithCompletion:user withCompletion: completion];
    }
}

+(void) connectToMQTT {
    if (![ALUserDefaultsHandler isLoggedIn]) {
        return;
    }
    NSLog(@"connecting to mqtt server");
    session = [[MQTTSession alloc]initWithClientId:[NSString stringWithFormat:@"%@-%f",
                                                    [ALUserDefaultsHandler getUserKeyString],fmod([[NSDate date] timeIntervalSince1970], 10.0)]];
    
    session.protocolLevel = 4;
    session.willFlag = TRUE;
    session.willTopic = @"status";
    session.willMsg = [[NSString stringWithFormat:@"%@,%@", [ALUserDefaultsHandler getUserKeyString], @"0"] dataUsingEncoding:NSUTF8StringEncoding];
    session.willQoS = MQTTQosLevelAtMostOnce;
    
    // Set delegate appropriately to receive various events
    // See MQTTSession.h for information on various handlers
    // you can subscribe to.
    //[session setDelegate:self];
    NSLog(@"waiting for connect...");

    [session connectAndWaitToHost:MQTT_URL port:[MQTT_PORT intValue] usingSSL:NO];
    NSLog(@"connected...");
}

+(void) connect {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![ALUserDefaultsHandler isLoggedIn]) {
            return;
        }
        if (session == nil) {
            [ALRegisterUserClientService connectToMQTT];
        }
        //[session subscribeToTopic:@"status" atLevel:MQTTQosLevelAtLeastOnce];
        [session publishAndWaitData:[[NSString stringWithFormat:@"%@,%@", [ALUserDefaultsHandler getUserKeyString], @"1"] dataUsingEncoding:NSUTF8StringEncoding]
                            onTopic:@"status"
                             retain:NO
                                qos:MQTTQosLevelAtMostOnce];
        NSLog(@"published");
    });
}

+(void) disconnect {
    if (![ALUserDefaultsHandler isLoggedIn] && session == nil) {
        return;
    }
    NSLog(@"disconnecting from mqtt server");
    [session publishAndWaitData:[[NSString stringWithFormat:@"%@,%@", [ALUserDefaultsHandler getUserKeyString], @"0"] dataUsingEncoding:NSUTF8StringEncoding]
                        onTopic:@"status"
                        retain:YES
                            qos:MQTTQosLevelAtMostOnce];
    [session close];
    
}

-(void) logout
{
    [ALRegisterUserClientService disconnect];
    [[UIApplication sharedApplication] unregisterForRemoteNotifications];
    [ALUserDefaultsHandler clearAll];
    [ALApplozicSettings clearAllSettings];
    ALMessageDBService* messageDBService = [[ALMessageDBService alloc]init];
    [messageDBService deleteAllObjectsInCoreData];
}

@end