#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PiNodeRunner : NSObject
+ (void)startEngineWithArguments:(NSArray<NSString *> *)arguments;
@end

NS_ASSUME_NONNULL_END
