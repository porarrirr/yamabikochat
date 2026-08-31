#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PiNodeRunner : NSObject
+ (void)startEngineWithArguments:(NSArray<NSString *> *)arguments;
#if DEBUG
+ (NSDictionary<NSString *, NSString *> *)engineDiagnostics;
#endif
@end

NS_ASSUME_NONNULL_END
