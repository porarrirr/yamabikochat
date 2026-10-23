#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const PiNodeRunnerErrorDomain;
typedef NS_ERROR_ENUM(PiNodeRunnerErrorDomain, PiNodeRunnerError) {
    PiNodeRunnerErrorAlreadyStarted = 1,
    PiNodeRunnerErrorPreparationFailed = 2,
};

@interface PiNodeRunner : NSObject
+ (BOOL)startEngineWithArguments:(NSArray<NSString *> *)arguments
                         error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(startEngine(arguments:));
#if DEBUG
+ (NSDictionary<NSString *, NSString *> *)engineDiagnostics;
#endif
@end

NS_ASSUME_NONNULL_END
