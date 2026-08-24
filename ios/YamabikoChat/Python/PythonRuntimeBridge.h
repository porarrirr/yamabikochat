#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns the single embedded CPython interpreter and confines initialization and
/// execution to one dedicated thread. The watchdog's GIL-attached interruption
/// helper is the only cross-thread Python C API call. This is accident
/// containment, not a security sandbox against a hostile app user.
@interface PythonRuntimeBridge : NSObject

- (instancetype)initWithPythonHome:(NSString *)pythonHome
                        harnessPath:(NSString *)harnessPath
                   sitePackagesPath:(nullable NSString *)sitePackagesPath;

- (void)executeSession:(NSString *)sessionID
                   code:(NSString *)code
            optionsJSON:(NSString *)optionsJSON
             completion:(void (^)(NSString *resultJSON))completion;

- (void)resetSession:(NSString *)sessionID
           completion:(void (^)(NSString * _Nullable errorMessage))completion;

- (void)requestInterruptWithExceptionName:(NSString *)exceptionName;
- (uint64_t)physicalFootprintBytes;

@end

NS_ASSUME_NONNULL_END
