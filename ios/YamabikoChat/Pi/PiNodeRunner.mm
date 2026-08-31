#import "PiNodeRunner.h"
#import <NodeMobile/NodeMobile.h>

@implementation PiNodeRunner

#if DEBUG
static NSString *PiNodeEngineState = @"notStarted";
static NSString *PiNodeEngineStartedAtMs = @"none";
static NSString *PiNodeEngineFinishedAtMs = @"none";
static NSString *PiNodeEngineExitCode = @"none";
static NSUInteger PiNodeEngineLaunchCount = 0;
#endif

+ (void)startEngineWithArguments:(NSArray<NSString *> *)arguments {
#if DEBUG
    @synchronized(self) {
        PiNodeEngineState = @"starting";
        PiNodeEngineStartedAtMs = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000.0];
        PiNodeEngineFinishedAtMs = @"none";
        PiNodeEngineExitCode = @"none";
        PiNodeEngineLaunchCount += 1;
    }
#endif
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        size_t size = 0;
        for (NSString *argument in arguments) {
            size += strlen(argument.UTF8String) + 1;
        }

        char *buffer = (char *)calloc(size, sizeof(char));
        char **argv = (char **)calloc(arguments.count, sizeof(char *));
        char *position = buffer;
        for (NSUInteger index = 0; index < arguments.count; index++) {
            const char *value = arguments[index].UTF8String;
            const size_t length = strlen(value);
            memcpy(position, value, length);
            argv[index] = position;
            position += length + 1;
        }

#if DEBUG
        @synchronized(self) {
            PiNodeEngineState = @"executing";
        }
        int exitCode = node_start((int)arguments.count, argv);
        @synchronized(self) {
            PiNodeEngineState = @"exited";
            PiNodeEngineFinishedAtMs = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000.0];
            PiNodeEngineExitCode = [NSString stringWithFormat:@"%d", exitCode];
        }
#else
        node_start((int)arguments.count, argv);
#endif
        free(argv);
        free(buffer);
    }];
    thread.name = @"Yamabiko Pi Agent";
    thread.stackSize = 2 * 1024 * 1024;
    [thread start];
}

#if DEBUG
+ (NSDictionary<NSString *, NSString *> *)engineDiagnostics {
    @synchronized(self) {
        return @{
            @"nativeEngineState": PiNodeEngineState,
            @"nativeEngineStartedAtMs": PiNodeEngineStartedAtMs,
            @"nativeEngineFinishedAtMs": PiNodeEngineFinishedAtMs,
            @"nativeEngineExitCode": PiNodeEngineExitCode,
            @"nativeEngineLaunchCount": [NSString stringWithFormat:@"%lu", (unsigned long)PiNodeEngineLaunchCount]
        };
    }
}
#endif

@end
